import Foundation

/// The uploaded form of a `BackupSnapshot`. Like `LibraryCodec`, older snapshots load with defaults
/// and snapshots from a newer schema are refused, so an older app never restores data it cannot read.
public enum BackupCodec {
    /// Bump when the JSON shape changes in a way defaults cannot cover, and convert older snapshots in `decode`.
    public static let currentSchemaVersion = 1

    public enum DecodeError: Error, Equatable {
        case unreadable(String)
        /// Written by a newer app version.
        case newerSchema(Int)
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    public static func decode(_ data: Data) throws -> BackupSnapshot {
        let decoder = JSONDecoder()
        do {
            let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 0
            guard version <= currentSchemaVersion else { throw DecodeError.newerSchema(version) }
            return try decoder.decode(BackupSnapshot.self, from: data)
        } catch let error as DecodeError {
            throw error
        } catch {
            throw DecodeError.unreadable(String(describing: error))
        }
    }

    public static func encode(_ snapshot: BackupSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }
}
