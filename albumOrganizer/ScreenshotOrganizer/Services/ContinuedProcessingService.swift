import BackgroundTasks
import Foundation
import os
import ScreenshotKit

/// Keeps a processing run going after the app leaves the screen, through a `BGContinuedProcessingTask` whose
/// progress the system shows. Only manages the task's lifetime; the store decides when to ask and what to show.
@MainActor
final class ContinuedProcessingService {
    /// The system is ending the task (it expired, or the person stopped it). Runs before the task completes,
    /// so the store can pause processing and save what's done.
    var onExpired: () async -> Void = {}

    private let scheduler: BGTaskScheduler
    private var task: BGContinuedProcessingTask?
    /// From submitting until `finish()`: a task that starts after that has nothing left to do.
    private var isRequested = false
    private var status = ContinuedProcessingStatus.preparing

    /// Each submission gets a new identifier under the one Info.plist permits, since registering an
    /// identifier twice ends the app.
    private static let identifierPrefix = "\(Bundle.main.bundleIdentifier ?? "com.chiawei.albumOrganizer").processing"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "albumOrganizer", category: "processing")

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    /// Asks the system to keep the run going in the background. Must come from something the person did while
    /// the app is on screen; does nothing while a task is already requested.
    func submit(_ status: ContinuedProcessingStatus) {
        guard !isRequested else { return }
        self.status = status
        let identifier = "\(Self.identifierPrefix).\(UUID().uuidString)"
        let isRegistered = scheduler.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated { self?.begin(task) }
        }
        guard isRegistered else {
            return Self.log.error("Continued processing identifier not permitted: \(identifier, privacy: .public)")
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: status.title, subtitle: status.subtitle)
        do {
            try scheduler.submit(request)
            isRequested = true
        } catch {
            Self.log.error("Continued processing not submitted: \(error, privacy: .public)")
        }
    }

    /// Shows the run's latest counts in the system's progress UI.
    func report(_ status: ContinuedProcessingStatus) {
        self.status = status
        if let task { show(status, on: task) }
    }

    /// The run has no recognition or classification work left.
    func finish() {
        isRequested = false
        complete(success: true)
    }

    private func begin(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask else { return task.setTaskCompleted(success: false) }
        guard isRequested else { return task.setTaskCompleted(success: true) }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in await self?.expire() }
        }
        self.task = task
        show(status, on: task)
    }

    /// Lets go of the task first, so one submitted while the store saves is not the one completed here.
    private func expire() async {
        guard let expiring = task else { return }
        Self.log.info("Continued processing expired at \(self.status.completed) / \(self.status.total)")
        task = nil
        isRequested = false
        await onExpired()
        expiring.setTaskCompleted(success: false)
    }

    private func complete(success: Bool) {
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private func show(_ status: ContinuedProcessingStatus, on task: BGContinuedProcessingTask) {
        task.progress.totalUnitCount = status.total
        task.progress.completedUnitCount = status.completed
        task.updateTitle(status.title, subtitle: status.subtitle)
    }
}
