import Foundation
import Observation
import os
import Photos
import ScreenshotKit
import UIKit

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
    @ObservationIgnored private let persistence: any LibraryPersisting
    /// What the store last held, so a save writes only what changed since.
    @ObservationIgnored private var lastSaved: Library
    /// Set when the stored library could not be read: saving then would replace data the app never saw.
    @ObservationIgnored private var isSavingDisabled: Bool
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The write in flight; the next one waits for it so an older snapshot never lands after a newer one.
    @ObservationIgnored private var writeTask: Task<Bool, Never>?
    @ObservationIgnored private var processor: ScreenshotProcessor!

    private static let onboardedKey = "didFinishOnboarding"

    init(
        photos: PhotoLibraryService = .shared,
        recognizer: any ScreenRecognizing = VisionScreenRecognizer(),
        pipeline: ClassificationPipeline = .standard,
        persistence: any LibraryPersisting = LibraryStore.defaultPersistence
    ) {
        self.photos = photos
        self.persistence = persistence
        let stored = Self.loadLibrary(from: persistence)
        var library = stored.library
        library.requeueOutdated(version: ClassificationPipeline.version)
        self.library = library
        lastSaved = stored.library
        isSavingDisabled = !stored.canSave
        let onboarded = UserDefaults.standard.bool(forKey: Self.onboardedKey)
        phase = onboarded && photos.hasAccess ? .app : .welcome
        processor = ScreenshotProcessor(
            photos: photos,
            recognizer: recognizer,
            pipeline: pipeline,
            library: { [unowned self] in self.library },
            mutate: { [unowned self] body in self.mutate(body) }
        )
        processor.onRecognized = { [unowned self] in importProgress.recognized += 1 }
        processor.onIdle = { [unowned self] in finishImportSteps() }
        if phase == .app { startSyncing() }
        if library != lastSaved { scheduleSave() }
    }

    nonisolated static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    nonisolated static var defaultPersistence: any LibraryPersisting {
        JSONLibraryFile(fileURL: defaultFileURL)
    }

    private static func loadLibrary(from persistence: any LibraryPersisting) -> (library: Library, canSave: Bool) {
        do {
            switch try persistence.load() {
            case let .loaded(library):
                return (library, true)
            case .empty:
                return (Library(), true)
            case let .unreadable(backupURL, reason):
                Logger.persistence.error("Library unreadable, moved aside to \(backupURL.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
                return (Library(), true)
            }
        } catch {
            Logger.persistence.error("Library could not be loaded; saving is off until the next launch: \(error, privacy: .public)")
            return (Library(), false)
        }
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
        apply(photos.fetchScreenshots())
    }

    /// Pull-to-refresh: re-reads the Screenshots album off the main thread so the spinner keeps animating.
    func refresh() async {
        guard photos.hasAccess else { return }
        let photos = photos
        let assets = await Task.detached(priority: .userInitiated) { photos.fetchScreenshots() }.value
        apply(assets)
    }

    private func apply(_ assets: [AssetInfo]) {
        isLimitedAccess = photos.isLimited
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

    var processingCount: Int {
        library.count(in: .processing)
    }

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

    /// Starts writing without the debounce, e.g. when the app moves to the background,
    /// and asks for background time so the write can finish.
    func saveNow() {
        saveTask?.cancel()
        let application = UIApplication.shared
        let backgroundTask = application.beginBackgroundTask(withName: "Save library")
        Task {
            await write(library)
            application.endBackgroundTask(backgroundTask)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await write(library)
        }
    }

    private func write(_ snapshot: Library) async {
        guard !isSavingDisabled else { return }
        let changes = snapshot.changes(since: lastSaved)
        guard !changes.isEmpty else { return }
        let persistence = persistence
        let previous = writeTask
        let task = Task.detached(priority: .utility) {
            _ = await previous?.value
            do {
                try persistence.save(snapshot, changes: changes)
                return true
            } catch {
                Logger.persistence.error("Saving the library failed: \(error, privacy: .public)")
                return false
            }
        }
        writeTask = task
        // A failed write leaves `lastSaved` alone, so the next save covers these changes again.
        if await task.value { lastSaved = snapshot }
    }
}
