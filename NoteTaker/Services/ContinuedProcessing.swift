import BackgroundTasks
import Foundation
import OSLog

private let log = Logger(subsystem: "com.lucassteffenon.NoteTaker", category: "ContinuedProcessing")

/// Keeps a user-started job alive after the app leaves the foreground, using iOS 26's
/// `BGContinuedProcessingTask`. The system shows the job's title and `progress` while it runs.
///
/// The work itself runs in a regular `Task` started by the caller; the background task only
/// mirrors its progress and cancels it if the system expires the task. If the system refuses
/// the request (Simulator, Background App Refresh off, too many tasks), the work still runs
/// while the app stays open.
enum ContinuedProcessing {
    /// Must match the wildcard in `BGTaskSchedulerPermittedIdentifiers` (Config/Info.plist).
    private static let identifierPrefix = "com.lucassteffenon.NoteTaker.processing"

    static func start(title: String, subtitle: String, progress: Progress, work: Task<Void, Never>) {
        // Each job gets a unique identifier, registered just before it is submitted.
        let identifier = "\(identifierPrefix).\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            task.progress.totalUnitCount = 100
            task.progress.addChild(progress, withPendingUnitCount: 100)
            task.expirationHandler = { work.cancel() }
            Task {
                await work.value
                task.setTaskCompleted(success: !work.isCancelled)
            }
        }
        guard registered else {
            log.error("Could not register \(identifier, privacy: .public)")
            return
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.info("Continuing in the foreground only: \(error.localizedDescription, privacy: .public)")
        }
    }
}
