import ActivityKit
import Foundation
import OSLog

/// Starts, updates and ends the recording Live Activity (timer and "Importante" button on the
/// Lock Screen and in the Dynamic Island). Failures are only logged: recording works without it.
@MainActor
final class RecordingActivity {
    private var activity: Activity<RecordingActivityAttributes>?
    private static let logger = Logger(subsystem: "com.lucassteffenon.NoteTaker", category: "RecordingActivity")

    func start(folderName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RecordingActivityAttributes.ContentState(timerStart: .now, pausedElapsed: nil, markCount: 0)
        do {
            activity = try Activity.request(
                attributes: RecordingActivityAttributes(folderName: folderName),
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            Self.logger.error("Live Activity not started: \(error.localizedDescription)")
        }
    }

    func update(elapsed: TimeInterval, isPaused: Bool, markCount: Int) {
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(
            timerStart: Date.now.addingTimeInterval(-elapsed),
            pausedElapsed: isPaused ? elapsed : nil,
            markCount: markCount
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
