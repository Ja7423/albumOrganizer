import CloudKit
import Foundation
import ScreenshotKit

/// One uploaded snapshot as the remote stores it; the remote never looks inside `data`.
nonisolated struct BackupPayload {
    var data: Data
    var createdAt: Date
    var shotCount: Int
}

nonisolated enum BackupAccountState: Equatable {
    case available
    case noAccount
    case restricted
    case unknown
}

/// Where snapshots are kept. Holds at most two, so a bad upload never leaves nothing to restore.
nonisolated protocol BackupRemote: Sendable {
    func accountState() async -> BackupAccountState
    /// Newest first; at most two.
    func fetchSnapshots() async throws -> [BackupPayload]
    /// Replaces the older of the two snapshots.
    func upload(_ payload: BackupPayload) async throws
}

/// Snapshots in the user's private CloudKit database, in two fixed records written in turn,
/// so nothing needs a query index.
nonisolated struct CloudKitBackupRemote: BackupRemote {
    private static let recordType = "LibrarySnapshot"
    private static let slots = ["snapshot-0", "snapshot-1"].map { CKRecord.ID(recordName: $0) }

    private enum Field {
        static let payload = "payload"
        static let createdAt = "createdAt"
        static let schemaVersion = "schemaVersion"
        static let shotCount = "shotCount"
    }

    private let container: CKContainer

    init(container: CKContainer = .default()) {
        self.container = container
    }

    func accountState() async -> BackupAccountState {
        switch try? await container.accountStatus() {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: return .unknown
        }
    }

    func fetchSnapshots() async throws -> [BackupPayload] {
        try await fetchRecords()
            .compactMap(Self.payload)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func upload(_ payload: BackupPayload) async throws {
        let slot = try await slotToReplace()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).backup")
        try payload.data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let record = CKRecord(recordType: Self.recordType, recordID: slot)
        record[Field.payload] = CKAsset(fileURL: fileURL)
        record[Field.createdAt] = payload.createdAt
        record[Field.schemaVersion] = BackupCodec.currentSchemaVersion
        record[Field.shotCount] = payload.shotCount
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    /// An empty slot first, otherwise the one holding the older snapshot.
    private func slotToReplace() async throws -> CKRecord.ID {
        let records = try await fetchRecords()
        if let empty = Self.slots.first(where: { slot in !records.contains { $0.recordID == slot } }) {
            return empty
        }
        let oldest = records.min { ($0[Field.createdAt] as? Date ?? .distantPast) < ($1[Field.createdAt] as? Date ?? .distantPast) }
        return oldest?.recordID ?? Self.slots[0]
    }

    /// Slots never written are missing, not errors.
    private func fetchRecords() async throws -> [CKRecord] {
        let results = try await container.privateCloudDatabase.records(for: Self.slots)
        return try results.values.compactMap { result in
            switch result {
            case let .success(record):
                return record
            case let .failure(error as CKError) where error.code == .unknownItem:
                return nil
            case let .failure(error):
                throw error
            }
        }
    }

    private static func payload(_ record: CKRecord) -> BackupPayload? {
        guard let asset = record[Field.payload] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return BackupPayload(
            data: data,
            createdAt: record[Field.createdAt] as? Date ?? .distantPast,
            shotCount: record[Field.shotCount] as? Int ?? 0
        )
    }
}
