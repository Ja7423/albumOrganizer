import Foundation
import os
import ScreenshotKit

nonisolated enum LibraryLoadResult {
    case loaded(Library)
    /// Nothing stored yet.
    case empty
    /// The stored data could not be read. It was moved aside to `backupURL` and is never overwritten.
    case unreadable(backupURL: URL, reason: String)
}

/// Where the `Library` lives between launches. Called off the main actor.
nonisolated protocol LibraryPersisting: Sendable {
    /// Throws when the store exists but cannot be read right now (e.g. the device is still locked);
    /// the caller must then not save, or it would replace data it never saw.
    func load() throws -> LibraryLoadResult
    /// `changes` lets incremental stores skip unchanged rows; whole-file stores ignore it.
    func save(_ library: Library, changes: LibraryChanges) throws
}

nonisolated extension Logger {
    static let persistence = Logger(subsystem: Bundle.main.bundleIdentifier ?? "albumOrganizer", category: "persistence")
}
