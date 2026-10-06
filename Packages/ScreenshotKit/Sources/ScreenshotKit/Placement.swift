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

    public init(source: ClassifierSource?, classifierVersion: Int) {
        self.source = source
        self.classifierVersion = classifierVersion
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
