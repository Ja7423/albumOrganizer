import Foundation

/// Backed-up screenshots a restore has not found on this device yet, e.g. while iCloud Photos is still
/// downloading. Matched again whenever Photos changes, and given up on after `lifetime`.
public struct PendingRestore: Codable, Hashable, Sendable {
    public static let lifetime: TimeInterval = 30 * 24 * 60 * 60

    public var restoredAt: Date
    public var snapshot: BackupSnapshot

    public init(restoredAt: Date, snapshot: BackupSnapshot) {
        self.restoredAt = restoredAt
        self.snapshot = snapshot
    }

    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(restoredAt) > Self.lifetime
    }
}
