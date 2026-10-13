import Foundation
import os
import ScreenshotKit

/// Works through the 處理中 queue one screenshot at a time: recognize its text, then classify it.
/// Once that queue is empty, refines screenshots left in 未分類; new 處理中 work always comes first.
/// Owns no library state; it reads and writes through the closures `LibraryStore` hands it.
@MainActor
final class ScreenshotProcessor {
    private enum Work {
        case process(String)
        case refine(String)
    }

    private let photos: PhotoLibraryService
    private let recognizer: any ScreenRecognizing
    private let pipeline: ClassificationPipeline
    /// `nil` turns refinement off.
    private let refinement: ClassificationPipeline?
    private let library: () -> Library
    private let mutate: ((inout Library) -> Void) -> Void

    /// Called after every recognition attempt (for import progress).
    var onRecognized: () -> Void = {}
    /// Called when the 處理中 queue runs dry, before any refinement.
    var onIdle: () -> Void = {}

    private var task: Task<Void, Never>?
    private var priorityIDs: [String] = []
    /// Failed recognitions are retried on the next run, not in a tight loop within this one.
    private var attemptedThisRun: Set<String> = []
    /// Set when the refinement layer can't answer right now; the next run tries again.
    private var isRefinementPaused = false

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "albumOrganizer", category: "classification")

    init(
        photos: PhotoLibraryService,
        recognizer: any ScreenRecognizing,
        pipeline: ClassificationPipeline,
        refinement: ClassificationPipeline?,
        library: @escaping () -> Library,
        mutate: @escaping ((inout Library) -> Void) -> Void
    ) {
        self.photos = photos
        self.recognizer = recognizer
        self.pipeline = pipeline
        self.refinement = refinement
        self.library = library
        self.mutate = mutate
    }

    /// Starts working through the queue; does nothing while a run is in progress.
    func start() {
        guard task == nil else { return }
        attemptedThisRun = []
        isRefinementPaused = false
        task = Task { [weak self] in
            var isQueueDrained = false
            while let self, let work = self.nextWork() {
                switch work {
                case let .process(id):
                    isQueueDrained = false
                    await self.process(id)
                case let .refine(id):
                    if !isQueueDrained {
                        isQueueDrained = true
                        self.onIdle()
                    }
                    await self.refine(id)
                }
            }
            self?.task = nil
            if !isQueueDrained { self?.onIdle() }
        }
    }

    /// Moves a screenshot to the front of the queue (e.g. when its detail page opens).
    func prioritize(_ id: String) {
        guard library().shot(id)?.isProcessing == true else { return }
        priorityIDs.removeAll { $0 == id }
        priorityIDs.insert(id, at: 0)
        start()
    }

    private func process(_ id: String) async {
        if canRecognize(id) {
            await recognize(id)
        }
        if library().pendingClassificationIDs.contains(id) {
            await classify(id)
        }
    }

    private func recognize(_ id: String) async {
        attemptedThisRun.insert(id)
        var output: RecognitionOutput?
        if let image = await photos.imageData(for: id) {
            output = try? await recognizer.recognize(image.0, orientation: image.1)
        }
        mutate { $0.setRecognition(id, blocks: output?.blocks, barcodes: output?.barcodes ?? []) }
        onRecognized()
    }

    private func classify(_ id: String) async {
        guard let input = library().classifierInput(for: id) else { return }
        let verdict = await pipeline.classify(input)
        let features = FeatureDetector.detect(input.signals)
        mutate { $0.applyClassification(id, verdict: verdict, features: features, version: ClassificationPipeline.version) }
    }

    private func refine(_ id: String) async {
        guard let refinement, let input = library().classifierInput(for: id) else { return }
        do {
            let verdict = try await refinement.classifyOrThrow(input)
            mutate { $0.applyRefinement(id, verdict: verdict) }
        } catch {
            isRefinementPaused = true
            Self.log.info("Refinement paused until the next run: \(String(describing: error), privacy: .public)")
        }
    }

    private func nextWork() -> Work? {
        if let id = nextID() { return .process(id) }
        guard refinement != nil, !isRefinementPaused else { return nil }
        return library().pendingRefinementIDs.first.map(Work.refine)
    }

    private func nextID() -> String? {
        let lib = library()
        while let id = priorityIDs.first {
            priorityIDs.removeFirst()
            if canRecognize(id) || lib.pendingClassificationIDs.contains(id) { return id }
        }
        return lib.pendingRecognitionIDs.first(where: canRecognize) ?? lib.pendingClassificationIDs.first
    }

    private func canRecognize(_ id: String) -> Bool {
        library().shot(id)?.needsRecognition == true && !attemptedThisRun.contains(id)
    }
}
