import Foundation

/// The on-disk JSON form of a `Library`. Older files load with defaults for anything they lack;
/// files from a newer schema are refused so an older app never overwrites data it cannot read.
public enum LibraryCodec {
    /// Bump when the JSON shape changes in a way defaults cannot cover, and convert older files in `decode`.
    /// Files written before versioning existed have no `schemaVersion` and count as 0.
    public static let currentSchemaVersion = 1

    public enum DecodeError: Error, Equatable {
        case unreadable(String)
        /// Written by a newer app version.
        case newerSchema(Int)
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    public static func decode(_ data: Data) throws -> Library {
        let decoder = JSONDecoder()
        do {
            let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 0
            guard version <= currentSchemaVersion else { throw DecodeError.newerSchema(version) }
            return try decoder.decode(Library.self, from: data)
        } catch let error as DecodeError {
            throw error
        } catch {
            throw DecodeError.unreadable(String(describing: error))
        }
    }

    public static func encode(_ library: Library) throws -> Data {
        try JSONEncoder().encode(library)
    }
}

extension KeyedDecodingContainer {
    /// Raw values this version does not know are dropped, so a value added or removed in another
    /// app version cannot make the whole library unreadable.
    func decodeKnownValues<Value: RawRepresentable & Hashable>(_: Value.Type, forKey key: Key) throws -> Set<Value>
        where Value.RawValue == String
    {
        let raw = try decodeIfPresent([String].self, forKey: key) ?? []
        return Set(raw.compactMap(Value.init(rawValue:)))
    }

    /// `nil` when the key is missing or holds a raw value this version does not know.
    func decodeKnownValue<Value: RawRepresentable>(_: Value.Type, forKey key: Key) throws -> Value?
        where Value.RawValue == String
    {
        try decodeIfPresent(String.self, forKey: key).flatMap(Value.init(rawValue:))
    }
}
