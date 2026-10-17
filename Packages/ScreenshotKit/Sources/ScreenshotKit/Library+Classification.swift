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

    /// Screenshots the processor still has work for: recognition to do or retry, or a classifier pass.
    /// Larger than the 處理中 count after a restore, whose placements come back without recognized text.
    var processingWorkCount: Int {
        shots.count { $0.needsRecognition || $0.isProcessing }
    }

    var classificationSummary: ClassificationSummary {
        let placed = shots.filter { !$0.isProcessing }
        let unsorted = placed.filter { $0.folderID == nil }.count
        return ClassificationSummary(classified: placed.count - unsorted, unsorted: unsorted)
    }

    /// What the classifier layers see for one screenshot. Deleted built-ins are excluded.
    func classifierInput(for id: String) -> ClassifierInput? {
        guard let shot = shot(id) else { return nil }
        return ClassifierInput(blocks: shot.blocks, barcodes: shot.barcodes, excluded: excludedTargets)
    }

    /// Targets no classifier may answer: the built-in categories the user deleted.
    var excludedTargets: Set<ClassificationTarget> {
        Set(deletedBuiltIns.map(ClassificationTarget.builtIn))
    }

    /// Places a screenshot from a pipeline result. Ignored when the user moved it in the meantime,
    /// so a manual move always wins over a classification that was already running.
    mutating func applyClassification(_ id: String, verdict: ClassifierVerdict?, features: Set<FeatureTag>, version: Int) {
        let (destination, source) = autoDestination(for: verdict)
        update([id]) { $0.applyAutoPlacement(folderID: destination, source: source, features: features, version: version) }
    }

    /// Where a verdict sends a screenshot; a verdict for a missing folder counts as no answer.
    internal func autoDestination(for verdict: ClassifierVerdict?) -> (folderID: UUID?, source: ClassifierSource?) {
        let destination = verdict.flatMap { self.folderID(for: $0.target) }
        return (destination, destination == nil ? nil : verdict?.source)
    }

    /// Automatic screenshots still in 未分類 that have text and no refinement pass yet.
    var pendingRefinementIDs: [String] {
        shots.filter(\.awaitsRefinement).map(\.id)
    }

    var pendingRefinementCount: Int {
        shots.count { $0.awaitsRefinement }
    }

    /// Those of `ids` waiting for the refinement pass; one pass over the screenshots.
    func awaitingRefinement(among ids: Set<String>) -> Set<String> {
        Set(shots.lazy.filter { ids.contains($0.id) && $0.awaitsRefinement }.map(\.id))
    }

    /// Records a refinement result and returns whether it moved the screenshot into a folder. Ignored unless
    /// the screenshot is still automatic and in 未分類, so a manual move made meanwhile always wins. A verdict
    /// for a deleted built-in counts as no answer.
    @discardableResult
    mutating func applyRefinement(_ id: String, verdict: ClassifierVerdict?) -> Bool {
        let destination = verdict.flatMap { self.folderID(for: $0.target) }
        var isMoved = false
        update([id]) { shot in
            guard var auto = shot.autoPlacement, shot.folderID == nil else { return }
            auto.isRefined = true
            if let destination, let verdict {
                shot.folderID = destination
                auto.source = verdict.source
                isMoved = true
            }
            shot.placement = .auto(auto)
        }
        return isMoved
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

public extension ClassifierInput {
    /// Input built from recognition output, e.g. fresh results not yet written back to the library.
    init(blocks: [TextBlock], barcodes: [String], excluded: Set<ClassificationTarget>) {
        self.init(
            text: Shot.joinedText(blocks),
            signals: SignalExtractor.extract(blocks: blocks, barcodes: barcodes),
            excluded: excluded
        )
    }
}
