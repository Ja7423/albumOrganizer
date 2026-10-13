import Foundation

/// The user's own placements as training data for the learned layer: screenshots they moved into a
/// built-in folder (the answer is that category) or out of every folder (the answer is 未分類).
public struct TrainingSet: Equatable, Sendable {
    /// The model's answer for 未分類.
    public static let noneLabel = "none"

    public var samples: [LabeledSample]
    /// Built-ins the user deleted: their seed samples are left out, so the model never answers them.
    public var excluded: Set<BuiltInCategory>

    public init(samples: [LabeledSample], excluded: Set<BuiltInCategory> = []) {
        self.samples = samples
        self.excluded = excluded
    }

    /// Label → texts to train on: the user's samples plus the seed samples of every category still offered.
    public func labeledTexts(seed: [LabeledSample] = LabeledSample.seedSamples) -> [String: [String]] {
        let offeredSeed = seed.filter { $0.expected.map { !excluded.contains($0) } ?? true }
        return Dictionary(grouping: samples + offeredSeed) { $0.expected?.rawValue ?? Self.noneLabel }
            .mapValues { $0.map { Self.modelText($0.text) } }
    }

    /// What the model reads, in training and when classifying: OCR lines joined into one line.
    public static func modelText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    /// Changes whenever a sample is added, removed or relabeled, or a built-in is deleted, so a saved model
    /// can tell it is out of date. A screenshot's text never changes after recognition, so ids are enough.
    public var fingerprint: String {
        let lines = samples.map { "\($0.id ?? "")\t\($0.expected?.rawValue ?? "")" }.sorted()
            + excluded.map { "-\($0.rawValue)" }.sorted()
        // FNV-1a: stable across launches, unlike `Hasher`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in lines.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16) + "-\(samples.count)"
    }
}

public extension Library {
    /// Custom folders are left out (no layer answers them yet), and so are screenshots without text.
    /// Built-ins the user deleted are left out too: the model must never learn to answer them.
    var trainingSet: TrainingSet {
        let samples = shots.compactMap { shot -> LabeledSample? in
            guard shot.placement == .user, shot.hasText else { return nil }
            let expected: BuiltInCategory?
            if let folderID = shot.folderID {
                guard let category = folder(folderID)?.builtIn, !deletedBuiltIns.contains(category) else { return nil }
                expected = category
            } else {
                expected = nil
            }
            return LabeledSample(id: shot.id, expected: expected, text: shot.allText)
        }
        return TrainingSet(samples: samples, excluded: deletedBuiltIns)
    }

    /// After the learned layer changes, automatic screenshots in 未分類 with text get another look. Placed ones stay.
    mutating func requeueUnsortedAutomatic() {
        let unsorted = shots.filter { $0.autoPlacement != nil && $0.folderID == nil && $0.hasText }.map(\.id)
        update(unsorted) { $0.placement = .pending }
    }
}
