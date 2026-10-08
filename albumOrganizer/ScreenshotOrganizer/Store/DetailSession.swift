import ScreenshotKit

/// The screenshots the detail page can page through, and which one is showing.
/// A snapshot taken when the page opens, so moving the current shot elsewhere doesn't yank it away.
struct DetailSession: Equatable {
    private(set) var ids: [String]
    private(set) var currentID: String

    /// `ids` should contain `currentID`; if it doesn't, the session is just that one shot.
    init(currentID: String, ids: [String]) {
        self.currentID = currentID
        self.ids = ids.contains(currentID) ? ids : [currentID]
    }

    /// The session's screenshots still in the library, in order.
    func visibleShots(in library: Library) -> [Shot] {
        let byID = Dictionary(library.shots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// Same session pointed at `id`; ignores ids that aren't in the session.
    func moving(to id: String) -> DetailSession {
        guard ids.contains(id) else { return self }
        var session = self
        session.currentID = id
        return session
    }

    /// When the current shot is gone from `library`: the session on its next neighbour,
    /// else the previous one, else `nil` (nothing left to show).
    func replacingMissingCurrent(in library: Library) -> DetailSession? {
        let present = Set(library.shots.map(\.id))
        guard !present.contains(currentID) else { return self }
        guard let index = ids.firstIndex(of: currentID) else { return nil }

        let next = ids[(index + 1)...].first(where: present.contains)
        let previous = ids[..<index].last(where: present.contains)
        return (next ?? previous).map(moving(to:))
    }
}
