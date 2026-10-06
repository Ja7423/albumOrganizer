import Foundation
import Observation
import Photos
import ScreenshotKit

/// Owns the `Library`, keeps it in sync with Photos, runs text recognition and saves to disk.
@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable { case welcome, permission, importing, app }

    /// Import progress for the onboarding screen. Steps: 0 掃描, 1 辨識, 2 建議, 3 完成.
    struct ImportProgress: Equatable {
        var found = 0
        var recognized = 0
        var total = 0
        var step = 0

        var fraction: Double {
            let scan = step > 0 ? 1.0 : 0.0
            let ocr = total == 0 ? (step > 1 ? 1 : 0) : Double(recognized) / Double(total)
            let suggest = step > 2 ? 1.0 : 0.0
            return scan * 0.2 + ocr * 0.7 + suggest * 0.1
        }
    }

    private(set) var library: Library
    var phase: Phase
    private(set) var importProgress = ImportProgress()
    private(set) var permissionDenied = false

    @ObservationIgnored private let photos: PhotoLibraryService
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var recognitionTask: Task<Void, Never>?
    @ObservationIgnored private var priorityIDs: [String] = []

    private static let onboardedKey = "didFinishOnboarding"

    init(photos: PhotoLibraryService = .shared, fileURL: URL = LibraryStore.defaultFileURL) {
        self.photos = photos
        self.fileURL = fileURL
        self.library = (try? JSONDecoder().decode(Library.self, from: Data(contentsOf: fileURL))) ?? Library()
        let onboarded = UserDefaults.standard.bool(forKey: Self.onboardedKey)
        self.phase = onboarded && photos.hasAccess ? .app : .welcome
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
        if syncFirst { syncWithPhotos() } else { recognizePending() }
    }

    func syncWithPhotos() {
        guard photos.hasAccess else { return }
        let assets = photos.fetchScreenshots()
        mutate { $0.sync(with: assets) }
        recognizePending()
    }

    /// Moves a screenshot to the front of the recognition queue (e.g. when its detail page opens).
    func prioritize(_ id: String) {
        guard library.shot(id)?.recognition == .pending else { return }
        priorityIDs.removeAll { $0 == id }
        priorityIDs.insert(id, at: 0)
        recognizePending()
    }

    private func recognizePending() {
        guard recognitionTask == nil else { return }
        recognitionTask = Task { [weak self] in
            while let self = self, let id = self.nextPendingID() {
                let blocks: [TextBlock]?
                if let image = await self.photos.imageData(for: id) {
                    blocks = try? await TextRecognizer.recognize(image.0, orientation: image.1)
                } else {
                    blocks = nil
                }
                if Task.isCancelled { break }
                self.mutate { $0.setRecognition(id, blocks: blocks) }
                self.importProgress.recognized += 1
            }
            guard let self = self else { return }
            self.recognitionTask = nil
            if self.phase == .importing, self.importProgress.step < 3 {
                self.importProgress.step = 2
                // Suggestions are produced alongside recognition; give the step a beat on screen.
                try? await Task.sleep(for: .milliseconds(600))
                self.importProgress.step = 3
            }
        }
    }

    private func nextPendingID() -> String? {
        while let id = priorityIDs.first {
            priorityIDs.removeFirst()
            if library.shot(id)?.recognition == .pending { return id }
        }
        return library.pendingRecognitionIDs.first
    }

    var pendingRecognitionCount: Int { library.pendingRecognitionIDs.count }

    // MARK: - Mutations

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
