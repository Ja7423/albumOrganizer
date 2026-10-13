import CloudKit
import CryptoKit
import Foundation
import os
import ScreenshotKit

/// Backs the library up to iCloud and finds backed-up screenshots on this device again. Owns no library
/// state: it is handed a `Library` to back up, and hands back a `BackupRestore` for `LibraryStore` to apply.
///
/// Uploads stay off until it is settled that no backup would be overwritten: the user answered the restore
/// question, iCloud was found to hold no backup, or the app was already set up before backups existed.
@MainActor
@Observable
final class BackupService {
    struct Found: Equatable {
        var createdAt: Date
        var shotCount: Int
    }

    enum Activity: Equatable {
        case idle, checking, backingUp, restoring
    }

    /// `nil` until iCloud was asked.
    private(set) var account: BackupAccountState?
    private(set) var activity: Activity = .idle
    /// Why the last check, backup or restore failed; cleared by the next success.
    private(set) var lastError: String?
    private(set) var lastBackupAt: Date?
    /// A backup in iCloud the user has not restored or skipped yet. Uploads wait for that choice.
    private(set) var undecided: Found?
    private(set) var canUpload: Bool

    var hasPendingRestore: Bool {
        pending != nil
    }

    @ObservationIgnored private let remote: any BackupRemote
    @ObservationIgnored private let photos: PhotoLibraryService
    @ObservationIgnored private let pendingStore: PendingRestoreStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pending: PendingRestore?
    /// The snapshot `undecided` describes, kept so restoring does not download it again.
    @ObservationIgnored private var foundSnapshot: BackupSnapshot?
    /// What was last uploaded in this process, to skip uploading the same thing again.
    @ObservationIgnored private var uploadedFingerprint: String?
    @ObservationIgnored private var isMatchingPending = false

    private static let canUploadKey = "backup.canUpload"
    private static let lastBackupKey = "backup.lastBackupAt"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "albumOrganizer", category: "backup")

    /// - Parameter isOnboarded: set up before this launch, so there is local data and no restore question to wait for.
    init(
        remote: any BackupRemote = CloudKitBackupRemote(),
        photos: PhotoLibraryService = .shared,
        pendingStore: PendingRestoreStore = .default,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        isOnboarded: Bool
    ) {
        self.remote = remote
        self.photos = photos
        self.pendingStore = pendingStore
        self.defaults = defaults
        self.now = now
        canUpload = isOnboarded || defaults.bool(forKey: Self.canUploadKey)
        lastBackupAt = defaults.object(forKey: Self.lastBackupKey) as? Date
        pending = pendingStore.load()
    }

    // MARK: - Finding a backup

    /// Looks in iCloud for a backup. Returns `nil` when there is none, iCloud is unavailable, or the answer
    /// takes longer than `timeout`; a late answer still updates `undecided`.
    func checkForBackup(timeout: Duration = .seconds(5)) async -> Found? {
        await Self.firstResult(within: timeout) { [self] in await lookUp() }
    }

    private func lookUp() async -> Found? {
        activity = .checking
        defer { activity = .idle }
        account = await remote.accountState()
        guard account == .available else { return nil }
        do {
            let (snapshot, skipped) = try await latestReadableSnapshot()
            lastError = skipped.map { Self.message(for: $0) }
            guard let snapshot else {
                allowUploads()
                return nil
            }
            foundSnapshot = snapshot
            undecided = Found(createdAt: snapshot.createdAt, shotCount: snapshot.shots.count)
            return undecided
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    /// The newest snapshot this version can read, and why a newer one was skipped.
    private func latestReadableSnapshot() async throws -> (BackupSnapshot?, Error?) {
        var skipped: Error?
        for payload in try await remote.fetchSnapshots() {
            do {
                return try (BackupCodec.decode(payload.data), skipped)
            } catch {
                Self.log.error("Skipped an unreadable backup: \(String(describing: error), privacy: .public)")
                skipped = skipped ?? error
            }
        }
        return (nil, skipped)
    }

    // MARK: - Restoring

    /// Finds the backup's screenshots among `assets`. The ones not found yet are kept and matched again
    /// as Photos changes. `nil` when there is no backup or it could not be read.
    func restore(assets: [AssetInfo]) async -> BackupRestore? {
        activity = .restoring
        defer { activity = .idle }
        do {
            var snapshot = foundSnapshot
            if snapshot == nil { snapshot = try await latestReadableSnapshot().0 }
            guard let snapshot else { return nil }
            let result = await match(snapshot, assets: assets)
            savePending(PendingRestore(restoredAt: now(), snapshot: result.leftover))
            foundSnapshot = nil
            undecided = nil
            lastError = nil
            allowUploads()
            return result.restore
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    /// The user chose to start over: the next upload may replace what is in iCloud.
    func skipRestore() {
        foundSnapshot = nil
        undecided = nil
        allowUploads()
    }

    /// Screenshots from the last restore that `assets` now includes, e.g. after iCloud Photos downloaded them.
    func matchPending(assets: [AssetInfo]) async -> BackupRestore? {
        guard let pending, !isMatchingPending else { return nil }
        guard !pending.isExpired(now: now()) else {
            savePending(nil)
            return nil
        }
        isMatchingPending = true
        defer { isMatchingPending = false }
        let result = await match(pending.snapshot, assets: assets)
        guard !result.restore.isEmpty else { return nil }
        savePending(PendingRestore(restoredAt: pending.restoredAt, snapshot: result.leftover))
        return result.restore
    }

    private func match(_ snapshot: BackupSnapshot, assets: [AssetInfo]) async -> BackupMatcher.Result {
        let photos = photos
        return await Task.detached(priority: .userInitiated) {
            let cloudIDs = (snapshot.shots.map(\.key) + snapshot.hiddenShots).compactMap(\.cloudID)
            let localIDs = photos.localIdentifiers(forCloud: cloudIDs)
            return BackupMatcher.match(snapshot, assets: assets, localIDsByCloudID: localIDs)
        }.value
    }

    private func savePending(_ pending: PendingRestore?) {
        let kept = pending.flatMap { $0.snapshot.hasNoScreenshots ? nil : $0 }
        self.pending = kept
        do {
            try pendingStore.save(kept)
        } catch {
            Self.log.error("Could not save the pending restore: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Backing up

    /// Uploads `library` unless uploads are still off or it matches the last upload.
    func backUp(_ library: Library) async {
        guard activity == .idle else { return }
        if !canUpload { _ = await checkForBackup() }
        guard canUpload else { return }
        activity = .backingUp
        defer { activity = .idle }
        account = await remote.accountState()
        guard account == .available else { return }

        let createdAt = now()
        let snapshot = await makeSnapshot(of: library, createdAt: createdAt)
        do {
            let fingerprint = try Self.fingerprint(of: snapshot)
            guard fingerprint != uploadedFingerprint else { return }
            let data = try BackupCodec.encode(snapshot)
            try await remote.upload(BackupPayload(data: data, createdAt: createdAt, shotCount: snapshot.shots.count))
            uploadedFingerprint = fingerprint
            lastBackupAt = createdAt
            defaults.set(createdAt, forKey: Self.lastBackupKey)
            lastError = nil
        } catch {
            Self.log.error("Backup failed: \(String(describing: error), privacy: .public)")
            lastError = Self.message(for: error)
        }
    }

    /// Resolving cloud identifiers is slow for large libraries, so the snapshot is made off the main thread.
    private func makeSnapshot(of library: Library, createdAt: Date) async -> BackupSnapshot {
        let photos = photos
        let pending = pending?.snapshot
        return await Task.detached(priority: .utility) {
            let hiddenIDs = Array(library.hiddenShotIDs)
            let cloudIDs = photos.cloudIdentifiers(for: library.shots.map(\.id) + hiddenIDs)
            return library.backupSnapshot(
                createdAt: createdAt,
                cloudIDsByLocalID: cloudIDs,
                hiddenAssets: photos.assetInfos(for: hiddenIDs),
                pending: pending
            )
        }.value
    }

    private func allowUploads() {
        canUpload = true
        defaults.set(true, forKey: Self.canUploadKey)
    }

    // MARK: - Helpers

    /// Ignores `createdAt`. Sets encode in a per-process order, so this only spots repeats within one run.
    private nonisolated static func fingerprint(of snapshot: BackupSnapshot) throws -> String {
        var undated = snapshot
        undated.createdAt = .distantPast
        let digest = try SHA256.hash(data: BackupCodec.encode(undated))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func message(for error: Error) -> String {
        if case let .newerSchema(version)? = error as? BackupCodec.DecodeError {
            return "iCloud 裡的備份來自較新版本的 App（格式 \(version)），請先更新"
        }
        switch (error as? CKError)?.code {
        case .quotaExceeded: return "iCloud 空間不足"
        case .networkUnavailable, .networkFailure: return "沒有網路連線"
        case .notAuthenticated: return "未登入 iCloud"
        default: return "備份讀寫失敗，稍後會再試一次"
        }
    }

    /// Whichever comes first: `operation`'s result, or `nil` after `timeout`. The operation keeps running.
    private static func firstResult<T: Sendable>(
        within timeout: Duration,
        _ operation: @escaping @MainActor () async -> T?
    ) async -> T? {
        let gate = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            let claim = { @Sendable (value: T?) in
                let isFirst = gate.withLock { resumed in
                    defer { resumed = true }
                    return !resumed
                }
                if isFirst { continuation.resume(returning: value) }
            }
            Task { @MainActor in claim(await operation()) }
            Task {
                try? await Task.sleep(for: timeout)
                claim(nil)
            }
        }
    }
}
