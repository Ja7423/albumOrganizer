import Foundation
import ScreenshotKit

/// The whole `Library` as one JSON file, rewritten on every save.
nonisolated struct JSONLibraryFile: LibraryPersisting {
    let fileURL: URL
    private let now: @Sendable () -> Date

    init(fileURL: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    func load() throws -> LibraryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        do {
            return try .loaded(LibraryCodec.decode(data))
        } catch {
            return try .unreadable(backupURL: moveAside(), reason: String(describing: error))
        }
    }

    func save(_ library: Library, changes _: LibraryChanges) throws {
        try LibraryCodec.encode(library).write(to: fileURL, options: .atomic)
    }

    /// e.g. `library.unreadable-20261011T185900.json` next to the original.
    private func moveAside() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let name = "\(fileURL.deletingPathExtension().lastPathComponent).unreadable-\(formatter.string(from: now())).\(fileURL.pathExtension)"
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: fileURL, to: backup)
        return backup
    }
}
