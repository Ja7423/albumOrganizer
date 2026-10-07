import Foundation

/// Which screenshots a grid shows.
public enum Scope: Hashable, Sendable {
    case all
    case processing
    case unsorted
    case tag(String)
    case feature(FeatureTag)
    case folder(UUID)
}

/// Everything the app stores. Pure value type: every rule about folders, tags and
/// classification lives here so it can be tested without Photos or Vision.
public struct Library: Codable, Hashable, Sendable {
    /// Newest first.
    public private(set) var shots: [Shot]
    public private(set) var folders: [Folder]
    public private(set) var tags: [String]
    /// Screenshots the user removed from the app. The photo stays in the album;
    /// syncing must not bring it back.
    public private(set) var hiddenShotIDs: Set<String>
    /// Built-in categories the user deleted. Their folders are not recreated and nothing is classified into them.
    public private(set) var deletedBuiltIns: Set<BuiltInCategory>

    public init(
        shots: [Shot] = [],
        folders: [Folder] = [],
        tags: [String] = [],
        hiddenShotIDs: Set<String> = [],
        deletedBuiltIns: Set<BuiltInCategory> = []
    ) {
        self.shots = shots.sorted { $0.createdAt > $1.createdAt }
        self.folders = folders
        self.tags = tags
        self.hiddenShotIDs = hiddenShotIDs
        self.deletedBuiltIns = deletedBuiltIns
        addMissingBuiltInFolders()
    }

    private enum CodingKeys: String, CodingKey {
        case shots, folders, tags, hiddenShotIDs, deletedBuiltIns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shots: try c.decode([Shot].self, forKey: .shots),
            folders: try c.decode([Folder].self, forKey: .folders),
            tags: try c.decode([String].self, forKey: .tags),
            hiddenShotIDs: try c.decode(Set<String>.self, forKey: .hiddenShotIDs),
            deletedBuiltIns: try c.decode(Set<BuiltInCategory>.self, forKey: .deletedBuiltIns)
        )
    }

    /// Creates a folder for every built-in category that has none and was not deleted.
    private mutating func addMissingBuiltInFolders() {
        let present = Set(folders.compactMap(\.builtIn))
        for category in BuiltInCategory.allCases where !present.contains(category) && !deletedBuiltIns.contains(category) {
            folders.append(Folder(name: category.defaultName, builtIn: category))
        }
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
        case .processing: return shots.filter(\.isProcessing)
        case .unsorted: return shots.filter(\.isUnsorted)
        case .tag(let t): return shots.filter { $0.tags.contains(t) }
        case .feature(let f): return shots.filter { $0.featureTags.contains(f) }
        case .folder(let id): return shots.filter { $0.folderID == id }
        }
    }

    public func count(in scope: Scope) -> Int {
        shots(in: scope).count
    }

    /// Folders in display order: ones holding screenshots first, empty ones last, each group in stored order.
    public var foldersEmptyLast: [Folder] {
        let occupied = Set(shots.compactMap(\.folderID))
        return folders.filter { occupied.contains($0.id) } + folders.filter { !occupied.contains($0.id) }
    }

    public var pendingRecognitionIDs: [String] {
        shots.filter(\.needsRecognition).map(\.id)
    }

    /// Feature tags at least one screenshot carries, in declaration order.
    public var presentFeatureTags: [FeatureTag] {
        let present = shots.reduce(into: Set<FeatureTag>()) { $0.formUnion($1.featureTags) }
        return FeatureTag.allCases.filter(present.contains)
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

    /// Stores recognized text and barcodes; `nil` blocks record a failed attempt. Classification happens separately.
    public mutating func setRecognition(_ id: String, blocks: [TextBlock]?, barcodes: [String] = []) {
        update([id]) { shot in
            guard let blocks else {
                shot.recognition = .failed
                shot.recognitionAttempts += 1
                return
            }
            shot.blocks = blocks
            shot.barcodes = barcodes
            shot.recognition = .done
        }
    }

    // MARK: - Folders

    /// Moves screenshots into a folder (`nil` = 未分類). A screenshot is only ever in one folder.
    /// Any manual move locks the screenshot against automatic classification.
    public mutating func move(_ ids: [String], to folderID: UUID?) {
        update(ids) { shot in
            shot.folderID = folderID
            shot.placement = .user
        }
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

    /// Returns `false` when the name is empty or another folder already uses it.
    @discardableResult
    public mutating func renameFolder(_ id: UUID, to raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folders.contains(where: { $0.name == name && $0.id != id }),
              let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders[index].name = name
        return true
    }

    /// Screenshots the user placed go to 未分類 and stay locked; automatic ones are classified again.
    /// A deleted built-in folder is remembered so it is neither recreated nor classified into.
    public mutating func deleteFolder(_ id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        if let category = folders[index].builtIn { deletedBuiltIns.insert(category) }
        folders.remove(at: index)
        for i in shots.indices where shots[i].folderID == id {
            shots[i].folderID = nil
            if shots[i].placement != .user { shots[i].placement = .pending }
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
        }
    }

    public mutating func removeTag(_ t: String, from id: String) {
        update([id]) { $0.tags.removeAll { $0 == t } }
    }

    /// Removes an automatic tag and remembers not to add it again.
    public mutating func dismissFeatureTag(_ tag: FeatureTag, from id: String) {
        update([id]) { shot in
            shot.featureTags.remove(tag)
            shot.dismissedFeatureTags.insert(tag)
        }
    }

    // MARK: - Removal

    /// Removes screenshots from the app only; the photos stay in the album.
    public mutating func hide(_ ids: [String]) {
        let set = Set(ids)
        shots.removeAll { set.contains($0.id) }
        hiddenShotIDs.formUnion(set)
    }

    // MARK: - Helpers

    mutating func update(_ ids: [String], _ body: (inout Shot) -> Void) {
        let set = Set(ids)
        for i in shots.indices where set.contains(shots[i].id) {
            body(&shots[i])
        }
    }
}
