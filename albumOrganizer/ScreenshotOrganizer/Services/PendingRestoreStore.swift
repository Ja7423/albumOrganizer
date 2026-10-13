import Foundation
import ScreenshotKit

/// Keeps the screenshots a restore has not found yet in `pending-restore.json`, next to the library.
nonisolated struct PendingRestoreStore {
    let fileURL: URL

    static var `default`: PendingRestoreStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PendingRestoreStore(fileURL: dir.appendingPathComponent("pending-restore.json"))
    }

    /// `nil` when there is nothing pending or the file cannot be read; a lost leftover only means reclassifying.
    func load() -> PendingRestore? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PendingRestore.self, from: data)
    }

    /// `nil`, or nothing left to find, deletes the file.
    func save(_ pending: PendingRestore?) throws {
        guard let pending, !pending.snapshot.hasNoScreenshots else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try JSONEncoder().encode(pending).write(to: fileURL, options: .atomic)
    }
}
