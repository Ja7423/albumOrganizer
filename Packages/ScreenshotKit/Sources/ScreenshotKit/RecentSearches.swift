import Foundation

/// The most recent search queries, newest first, without duplicates.
public struct RecentSearches: Equatable, Sendable {
    public static let limit = 5

    public private(set) var queries: [String]

    public init(_ queries: [String] = []) {
        self.queries = Array(queries.prefix(Self.limit))
    }

    /// Moves `query` (trimmed) to the front, dropping an earlier identical entry and anything past `limit`.
    public func recording(_ query: String) -> RecentSearches {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return self }
        return RecentSearches([q] + queries.filter { $0 != q })
    }
}
