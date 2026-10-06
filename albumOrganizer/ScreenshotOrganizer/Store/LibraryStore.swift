import Foundation
import Observation
import Photos
import UIKit
import ScreenshotKit

/// Owns the `Library`, keeps it in sync with Photos, feeds the processing queue and saves to disk.
@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable { case welcome, permission, importing, app }

    /// Import progress for the onboarding screen. Steps: 0 掃描, 1 辨識, 2 分類, 3 完成.
    struct ImportProgress: Equatable {
        var found = 0
        var recognized = 0
        var total = 0
        var step = 0

        var fraction: Double {
            let scan = step > 0 ? 1.0 : 0.0
            let ocr = total == 0 ? (step > 1 ? 1 : 0) : Double(recognized) / Double(total)
            let classify = step > 2 ? 1.0 : 0.0
            return scan * 0.2 + ocr * 0.7 + classify * 0.1
        }
    }

    private(set) var library: Library
    var phase: Phase
    private(set) var importProgress = ImportProgress()
    private(set) var permissionDenied = false
    /// The user granted access to selected photos only.
    private(set) var isLimitedAccess = false

    @ObservationIgnored private let photos: PhotoLibraryService
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var processor: ScreenshotProcessor!

    private static let onboardedKey = "didFinishOnboarding"

    init(
        photos: PhotoLibraryService = .shared,
        recognizer: any ScreenRecognizing = VisionScreenRecognizer(),
        pipeline: ClassificationPipeline = .standard,
        fileURL: URL = LibraryStore.defaultFileURL
    ) {
        self.photos = photos
        self.fileURL = fileURL
        var library = (try? JSONDecoder().decode(Library.self, from: Data(contentsOf: fileURL))) ?? Library()
        library.requeueOutdated(version: ClassificationPipeline.version)
        self.library = library
        let onboarded = UserDefaults.standard.bool(forKey: Self.onboardedKey)
        self.phase = onboarded && photos.hasAccess ? .app : .welcome
        self.processor = ScreenshotProcessor(
            photos: photos,
            recognizer: recognizer,
            pipeline: pipeline,
            library: { [unowned self] in self.library },
            mutate: { [unowned self] body in self.mutate(body) }
        )
        processor.onRecognized = { [unowned self] in importProgress.recognized += 1 }
        processor.onIdle = { [unowned self] in finishImportSteps() }
        if phase == .app { startSyncing() }
    }

    nonisolated static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    // MARK: - Onboarding

    func goToPermission() {
        phase = .permission
    }

    /// Shows the system prompt (if not yet answered) and starts importing on success.
    func requestAccess() async {
        var status = photos.authorizationStatus
        if status == .notDetermined {
            status = await photos.requestAuthorization()
        }
        switch status {
        case .authorized, .limited:
            permissionDenied = false
            startImport()
        default:
            permissionDenied = true
        }
    }

    private func startImport() {
        phase = .importing
        importProgress = ImportProgress()
        let assets = photos.fetchScreenshots()
        mutate { $0.sync(with: assets) }
        importProgress.found = library.shots.count
        importProgress.total = library.pendingRecognitionIDs.count
        importProgress.step = 1
        startSyncing(syncFirst: false)
    }

    func finishImport() {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        phase = .app
    }

    // MARK: - Photos sync & recognition

    private func startSyncing(syncFirst: Bool = true) {
        photos.startObserving { [weak self] in self?.syncWithPhotos() }
        if syncFirst { syncWithPhotos() } else { processor.start() }
    }

    func syncWithPhotos() {
        guard photos.hasAccess else { return }
        isLimitedAccess = photos.isLimited
        let assets = photos.fetchScreenshots()
        mutate { $0.sync(with: assets) }
        processor.start()
    }

    /// Views go through the store so they never touch `PhotoLibraryService` directly.
    func presentLimitedLibraryPicker(from controller: UIViewController) {
        photos.presentLimitedLibraryPicker(from: controller)
    }

    /// Moves a screenshot to the front of the queue (e.g. when its detail page opens).
    func prioritize(_ id: String) {
        processor.prioritize(id)
    }

    /// Recognition and classification run together; give the 分類 step a beat on screen before 完成.
    private func finishImportSteps() {
        guard phase == .importing, importProgress.step < 3 else { return }
        importProgress.step = 2
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            importProgress.step = 3
        }
    }

    var processingCount: Int { library.count(in: .processing) }

    // MARK: - Mutations

    /// Deleting a folder sends its automatic screenshots back through classification.
    func deleteFolder(_ id: UUID) {
        mutate { $0.deleteFolder(id) }
        processor.start()
    }

    func mutate(_ body: (inout Library) -> Void) {
        body(&library)
        scheduleSave()
    }

    /// Writes immediately, e.g. when the app moves to the background.
    func saveNow() {
        saveTask?.cancel()
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = library
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
