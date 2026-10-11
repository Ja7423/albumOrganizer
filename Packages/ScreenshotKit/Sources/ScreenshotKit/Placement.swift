import Foundation

/// Which classifier layer decided a screenshot's folder.
public enum ClassifierSource: String, Codable, Sendable {
    case rule
    case knn
    case llm
}

public struct AutoPlacement: Codable, Hashable, Sendable {
    /// `nil` when no layer was confident enough and the screenshot stayed in 未分類.
    public var source: ClassifierSource?
    public var classifierVersion: Int
    /// The refinement pass (on-device LLM) already looked at this screenshot.
    public var isRefined: Bool

    public init(source: ClassifierSource?, classifierVersion: Int, isRefined: Bool = false) {
        self.source = source
        self.classifierVersion = classifierVersion
        self.isRefined = isRefined
    }

    private enum CodingKeys: String, CodingKey {
        case source, classifierVersion, isRefined
    }

    /// Files written before refinement existed have no `isRefined`; those screenshots still need the pass.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            source: c.decodeIfPresent(ClassifierSource.self, forKey: .source),
            classifierVersion: c.decode(Int.self, forKey: .classifierVersion),
            isRefined: c.decodeIfPresent(Bool.self, forKey: .isRefined) ?? false
        )
    }
}

/// How a screenshot got into its folder.
public enum Placement: Codable, Hashable, Sendable {
    /// Waiting for recognition or classification; shown under 處理中.
    case pending
    case auto(AutoPlacement)
    /// Moved by the user. Never reclassified; a training sample for learning layers.
    case user
}
