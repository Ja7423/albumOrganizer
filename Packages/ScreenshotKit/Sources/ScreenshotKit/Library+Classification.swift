import Foundation

/// Counts shown when the first import finishes.
public struct ClassificationSummary: Equatable, Sendable {
    public var classified: Int
    public var unsorted: Int

    public init(classified: Int, unsorted: Int) {
        self.classified = classified
        self.unsorted = unsorted
    }
}

public extension Library {
    /// Screenshots done with recognition (or out of retries) that still need a classifier pass.
    var pendingClassificationIDs: [String] {
        shots.filter { $0.isProcessing && !$0.needsRecognition }.map(\.id)
    }

    var classificationSummary: ClassificationSummary {
        let placed = shots.filter { !$0.isProcessing }
        let unsorted = placed.filter { $0.folderID == nil }.count
        return ClassificationSummary(classified: placed.count - unsorted, unsorted: unsorted)
    }

    /// What the classifier layers see for one screenshot. Deleted built-ins are excluded.
    func classifierInput(for id: String) -> ClassifierInput? {
        guard let shot = shot(id) else { return nil }
        return ClassifierInput(
            text: shot.allText,
            signals: SignalExtractor.extract(blocks: shot.blocks, barcodes: shot.barcodes),
            excluded: Set(deletedBuiltIns.map(ClassificationTarget.builtIn))
        )
    }

    /// Places a screenshot from a pipeline result. Ignored when the user moved it in the meantime,
    /// so a manual move always wins over a classification that was already running.
    mutating func applyClassification(_ id: String, verdict: ClassifierVerdict?, features: Set<FeatureTag>, version: Int) {
        let destination = verdict.flatMap { self.folderID(for: $0.target) }
        let source = destination == nil ? nil : verdict?.source
        update([id]) { shot in
            guard shot.isProcessing else { return }
            shot.folderID = destination
            shot.placement = .auto(AutoPlacement(source: source, classifierVersion: version))
            shot.featureTags = features.subtracting(shot.dismissedFeatureTags)
        }
    }

    /// Automatic screenshots still in 未分類 that have text and no refinement pass yet.
    var pendingRefinementIDs: [String] {
        shots.filter(\.awaitsRefinement).map(\.id)
    }

    /// Records a refinement result. Ignored unless the screenshot is still automatic and in 未分類,
    /// so a manual move made meanwhile always wins. A verdict for a deleted built-in counts as no answer.
    mutating func applyRefinement(_ id: String, verdict: ClassifierVerdict?) {
        let destination = verdict.flatMap { self.folderID(for: $0.target) }
        update([id]) { shot in
            guard var auto = shot.autoPlacement, shot.folderID == nil else { return }
            auto.isRefined = true
            if let destination, let verdict {
                shot.folderID = destination
                auto.source = verdict.source
            }
            shot.placement = .auto(auto)
        }
    }

    /// Sends automatic placements made by an older classifier back to the queue. User placements stay.
    mutating func requeueOutdated(version: Int) {
        let outdated = shots.filter { ($0.autoPlacement?.classifierVersion ?? version) < version }.map(\.id)
        update(outdated) { $0.placement = .pending }
    }

    private func folderID(for target: ClassificationTarget) -> UUID? {
        switch target {
        case let .builtIn(category):
            guard !deletedBuiltIns.contains(category) else { return nil }
            return folders.first { $0.builtIn == category }?.id
        case let .folder(id):
            return folder(id)?.id
        }
    }
}
