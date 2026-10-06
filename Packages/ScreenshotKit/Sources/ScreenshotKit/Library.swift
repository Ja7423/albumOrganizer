import Foundation

/// Which screenshots a grid shows.
public enum Scope: Hashable, Sendable {
    case all
    case unsorted
    case suggested
    case tag(String)
    case folder(UUID)
}

/// Everything the app stores. Pure value type: every rule about folders, tags and
/// suggestions lives here so it can be tested without Photos or Vision.
public struct Library: Codable, Hashable, Sendable {
    /// Newest first.
    public private(set) var shots: [Shot]
    public private(set) var folders: [Folder]
    public private(set) var tags: [String]
    /// Screenshots the user removed from the app. The photo stays in the album;
    /// syncing must not bring it back.
    public private(set) var hiddenShotIDs: Set<String>

    public init(shots: [Shot] = [], folders: [Folder] = [], tags: [String] = [], hiddenShotIDs: Set<String> = []) {
        self.shots = shots.sorted { $0.createdAt > $1.createdAt }
        self.folders = folders
        self.tags = tags
        self.hiddenShotIDs = hiddenShotIDs
    }

    // MARK: - Lookup

    public func shot(_ id: String) -> Shot? {
        shots.first { $0.id == id }
    }

    public func folder(_ id: UUID?) -> Folder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    public static let unsortedName = "未分類"

    public func folderName(_ id: UUID?) -> String {
        folder(id)?.name ?? Library.unsortedName
    }

    public func shots(in scope: Scope) -> [Shot] {
        switch scope {
        case .all: return shots
        case .unsorted: return shots.filter { $0.folderID == nil }
        case .suggested: return shots.filter { !$0.suggestions.isEmpty }
        case .tag(let t): return shots.filter { $0.tags.contains(t) }
        case .folder(let id): return shots.filter { $0.folderID == id }
        }
    }

    public func count(in scope: Scope) -> Int {
        shots(in: scope).count
    }

    public var pendingRecognitionIDs: [String] {
        shots.filter { $0.recognition == .pending }.map(\.id)
    }

    /// Distinct suggested tag names across all screenshots, in first-seen order.
    public var suggestedTagNames: [String] {
        var seen = Set<String>()
        return shots.flatMap(\.suggestions).filter { seen.insert($0).inserted }
    }

    // MARK: - Photos sync

    public struct SyncResult: Equatable, Sendable {
        public var added: [String]
        public var removed: Int

        public init(added: [String], removed: Int) {
            self.added = added
            self.removed = removed
        }
    }

    /// Mirrors the Screenshots album: adds new assets as pending, drops ones deleted from Photos.
    @discardableResult
    public mutating func sync(with assets: [AssetInfo]) -> SyncResult {
        let present = Set(assets.map(\.id))
        let before = shots.count
        shots.removeAll { !present.contains($0.id) }
        let removed = before - shots.count
        hiddenShotIDs.formIntersection(present)

        let known = Set(shots.map(\.id))
        let fresh = assets.filter { !known.contains($0.id) && !hiddenShotIDs.contains($0.id) }
        shots += fresh.map { Shot(id: $0.id, createdAt: $0.createdAt, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight) }
        shots.sort { $0.createdAt > $1.createdAt }
        return SyncResult(added: fresh.map(\.id), removed: removed)
    }

    /// Stores recognized text and proposes tags from it.
    public mutating func setRecognition(_ id: String, blocks: [TextBlock]?) {
        update([id]) { shot in
            guard let blocks else {
                shot.recognition = .failed
                return
            }
            shot.blocks = blocks
            shot.recognition = .done
            shot.suggestions = TagSuggester.suggest(for: shot.allText, excluding: shot.tags)
        }
    }

    // MARK: - Folders

    /// Moves screenshots into a folder (`nil` = 未分類). A screenshot is only ever in one folder.
    public mutating func move(_ ids: [String], to folderID: UUID?) {
        update(ids) { $0.folderID = folderID }
    }

    @discardableResult
    public mutating func createFolder(named raw: String) -> Folder? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = folders.first(where: { $0.name == name }) { return existing }
        let folder = Folder(name: name)
        folders.append(folder)
        return folder
    }

    public mutating func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for i in shots.indices where shots[i].folderID == id {
            shots[i].folderID = nil
        }
    }

    // MARK: - Tags

    public static func normalizedTag(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public mutating func createTag(_ raw: String) -> String? {
        let t = Library.normalizedTag(raw)
        guard !t.isEmpty else { return nil }
        if !tags.contains(t) { tags.append(t) }
        return t
    }

    public mutating func deleteTag(_ t: String) {
        tags.removeAll { $0 == t }
        for i in shots.indices {
            shots[i].tags.removeAll { $0 == t }
        }
    }

    /// If every target already has the tag, removes it from all of them; otherwise adds it to all.
    public mutating func toggleTag(_ t: String, on ids: [String]) {
        let targets = ids.compactMap { shot($0) }
        guard !targets.isEmpty else { return }
        if targets.allSatisfy({ $0.tags.contains(t) }) {
            update(ids) { $0.tags.removeAll { $0 == t } }
        } else {
            addTag(t, to: ids)
        }
    }

    public mutating func addTag(_ raw: String, to ids: [String]) {
        guard let t = createTag(raw) else { return }
        update(ids) { shot in
            if !shot.tags.contains(t) { shot.tags.append(t) }
            shot.suggestions.removeAll { $0 == t }
        }
    }

    public mutating func removeTag(_ t: String, from id: String) {
        update([id]) { $0.tags.removeAll { $0 == t } }
    }

    public mutating func acceptSuggestion(_ t: String, for id: String) {
        addTag(t, to: [id])
    }

    /// Applies every pending suggestion. Returns how many screenshots changed.
    @discardableResult
    public mutating func applyAllSuggestions() -> Int {
        var changed = 0
        for i in shots.indices where !shots[i].suggestions.isEmpty {
            for t in shots[i].suggestions {
                if !tags.contains(t) { tags.append(t) }
                if !shots[i].tags.contains(t) { shots[i].tags.append(t) }
            }
            shots[i].suggestions = []
            changed += 1
        }
        return changed
    }

    // MARK: - Removal

    /// Removes screenshots from the app only; the photos stay in the album.
    public mutating func hide(_ ids: [String]) {
        let set = Set(ids)
        shots.removeAll { set.contains($0.id) }
        hiddenShotIDs.formUnion(set)
    }

    // MARK: - Helpers

    private mutating func update(_ ids: [String], _ body: (inout Shot) -> Void) {
        let set = Set(ids)
        for i in shots.indices where set.contains(shots[i].id) {
            body(&shots[i])
        }
    }
}
