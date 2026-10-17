import Foundation

/// What the system shows for a processing run that carries on after the app leaves the screen:
/// the same counts as the progress bar above the tabs.
public struct ContinuedProcessingStatus: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let completed: Int64
    public let total: Int64

    /// Shown from submitting the task until the run reports its first counts.
    public static let preparing = ContinuedProcessingStatus(title: runningTitle, subtitle: "準備中", completed: 0, total: 0)

    private static let runningTitle = "正在整理截圖"

    public init(progress: ProcessingProgress) {
        switch progress.phase {
        case let .finished(tally):
            self.init(title: "整理完成", subtitle: tally.summary, completed: Int64(progress.total), total: Int64(progress.total))
        case .recognizing, .refining, .idle:
            self.init(
                title: Self.runningTitle,
                subtitle: "已完成 \(progress.completed.formatted()) / \(progress.total.formatted()) 張",
                completed: Int64(progress.completed),
                total: Int64(progress.total)
            )
        }
    }

    private init(title: String, subtitle: String, completed: Int64, total: Int64) {
        self.title = title
        self.subtitle = subtitle
        self.completed = completed
        self.total = total
    }
}
