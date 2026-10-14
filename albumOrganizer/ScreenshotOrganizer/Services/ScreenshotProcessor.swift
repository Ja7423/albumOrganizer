import Foundation
import os
import ScreenshotKit

/// Works through the 處理中 queue: several screenshots at once, each recognized and then classified,
/// with results written back in batches. Once that queue is empty, refines screenshots left in 未分類;
/// new 處理中 work always comes first. Owns no library state; it reads and writes through the closures
/// `LibraryStore` hands it.
@MainActor
final class ScreenshotProcessor {
    private let photos: PhotoLibraryService
    private let recognizer: any ScreenRecognizing
    private let pipeline: ClassificationPipeline
    /// `nil` turns refinement off.
    private let refinement: ClassificationPipeline?
    private let library: () -> Library
    private let mutate: ((inout Library) -> Void) -> Void
    /// How many screenshots to work on at once; asked again before each new one starts.
    private let concurrency: () -> Int

    /// A run starts working through the 處理中 queue.
    var onRunStarted: () -> Void = {}
    /// After each batch of results is written to the library.
    var onBatchApplied: (ProcessingTally) -> Void = { _ in }
    /// The run has no recognition or classification work left, before any refinement.
    var onRunFinished: () -> Void = {}

    private var task: Task<Void, Never>?
    private var queue: ProcessingQueue?
    /// Set when `start()` is called mid-run, e.g. after Photos changed; the queue picks up new screenshots.
    private var needsRefill = false
    /// Set when the refinement layer can't answer right now; the next run tries again.
    private var isRefinementPaused = false

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "albumOrganizer", category: "classification")

    init(
        photos: PhotoLibraryService,
        recognizer: any ScreenRecognizing,
        pipeline: ClassificationPipeline,
        refinement: ClassificationPipeline?,
        library: @escaping () -> Library,
        mutate: @escaping ((inout Library) -> Void) -> Void,
        concurrency: @escaping () -> Int = ScreenshotProcessor.deviceConcurrency
    ) {
        self.photos = photos
        self.recognizer = recognizer
        self.pipeline = pipeline
        self.refinement = refinement
        self.library = library
        self.mutate = mutate
        self.concurrency = concurrency
    }

    nonisolated static func deviceConcurrency() -> Int {
        let info = ProcessInfo.processInfo
        return ProcessingConcurrency.width(thermalState: info.thermalState, isLowPowerModeEnabled: info.isLowPowerModeEnabled)
    }

    /// Starts working through the queue; mid-run, picks up screenshots added since the run began.
    /// Failed recognitions wait for the next run rather than retrying in a tight loop.
    func start() {
        guard task == nil else {
            needsRefill = true
            return
        }
        queue = ProcessingQueue(library: library())
        isRefinementPaused = false
        task = Task { [weak self] in await self?.run() }
    }

    /// Moves a screenshot to the front of the queue (e.g. when its detail page opens).
    func prioritize(_ id: String) {
        guard library().shot(id)?.isProcessing == true else { return }
        start()
        refillIfNeeded()
        queue?.prioritize(id)
    }

    // MARK: - Run

    private func run() async {
        repeat {
            onRunStarted()
            await processQueue()
            onRunFinished()
        } while await refineUntilNewWork()
        queue = nil
        task = nil
    }

    private func processQueue() async {
        let started = ContinuousClock.now
        var buffer = OutcomeBuffer()
        var runTally = ProcessingTally()
        var width = 0
        await withTaskGroup(of: ProcessingOutcome?.self) { group in
            var running = 0
            while true {
                width = concurrency()
                running += addWork(to: &group, upTo: width - running)
                guard running > 0, let result = await group.next() else { break }
                running -= 1
                if let result { buffer.append(result, at: .now) }
                if buffer.shouldFlush(at: .now) { runTally = runTally + apply(buffer.drain()) }
            }
        }
        runTally = runTally + apply(buffer.drain())
        ProcessingSignposts.logRun(runTally, duration: .now - started, width: width)
    }

    /// Starts up to `slots` new screenshots; returns how many it started.
    private func addWork(to group: inout TaskGroup<ProcessingOutcome?>, upTo slots: Int) -> Int {
        refillIfNeeded()
        guard slots > 0 else { return 0 }
        let excluded = library().excludedTargets
        var added = 0
        while added < slots, let work = queue?.next() {
            let job = Job(work: work, excluded: excluded, photos: photos, recognizer: recognizer, pipeline: pipeline)
            group.addTask { await job.perform() }
            added += 1
        }
        return added
    }

    private func refillIfNeeded() {
        guard needsRefill else { return }
        needsRefill = false
        queue?.refill(from: library())
    }

    private func apply(_ outcomes: [ProcessingOutcome]) -> ProcessingTally {
        guard !outcomes.isEmpty else { return ProcessingTally() }
        var tally = ProcessingTally()
        ProcessingSignposts.measure("apply") {
            mutate { tally = $0.applyProcessingOutcomes(outcomes, version: ClassificationPipeline.version) }
        }
        onBatchApplied(tally)
        return tally
    }

    // MARK: - Refinement

    /// Refines 未分類 screenshots one at a time. Returns `true` as soon as new 處理中 work arrives,
    /// so the caller starts another run first.
    private func refineUntilNewWork() async -> Bool {
        guard let refinement else { return false }
        while !isRefinementPaused {
            refillIfNeeded()
            if queue?.isEmpty == false { return true }
            guard let id = library().pendingRefinementIDs.first,
                  let input = library().classifierInput(for: id) else { return false }
            do {
                let verdict = try await refinement.classifyOrThrow(input)
                mutate { $0.applyRefinement(id, verdict: verdict) }
            } catch {
                isRefinementPaused = true
                Self.log.info("Refinement paused until the next run: \(String(describing: error), privacy: .public)")
            }
        }
        return false
    }
}

/// One screenshot's work, run off the main actor: load the image, recognize it, classify the result.
private nonisolated struct Job: Sendable {
    let work: ProcessingQueue.Work
    let excluded: Set<ClassificationTarget>
    let photos: PhotoLibraryService
    let recognizer: any ScreenRecognizing
    let pipeline: ClassificationPipeline

    func perform() async -> ProcessingOutcome? {
        switch work {
        case let .recognizeAndClassify(id, isLastAttempt):
            guard let output = await recognize(id) else {
                // Out of retries: classify it as textless, as the library would on the next run.
                let classification = isLastAttempt ? await classify(blocks: [], barcodes: []) : nil
                return ProcessingOutcome(id: id, recognition: .failed, classification: classification)
            }
            let classification = await classify(blocks: output.blocks, barcodes: output.barcodes)
            return ProcessingOutcome(id: id, recognition: .recognized(blocks: output.blocks, barcodes: output.barcodes), classification: classification)
        case let .classify(id, blocks, barcodes):
            return ProcessingOutcome(id: id, recognition: .unchanged, classification: await classify(blocks: blocks, barcodes: barcodes))
        }
    }

    private func recognize(_ id: String) async -> RecognitionOutput? {
        let image = await ProcessingSignposts.measure("loadImage") { await photos.imageData(for: id) }
        guard let image else { return nil }
        return try? await ProcessingSignposts.measure("recognize") { try await recognizer.recognize(image.0, orientation: image.1) }
    }

    private func classify(blocks: [TextBlock], barcodes: [String]) async -> ProcessingOutcome.Classification {
        await ProcessingSignposts.measure("classify") {
            let input = ClassifierInput(blocks: blocks, barcodes: barcodes, excluded: excluded)
            let verdict = await pipeline.classify(input)
            return ProcessingOutcome.Classification(verdict: verdict, features: FeatureDetector.detect(input.signals))
        }
    }
}
