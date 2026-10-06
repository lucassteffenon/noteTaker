import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and in the Dynamic Island while a lecture is recorded.
/// Compiled into both the app (which starts it) and the widget extension (which draws it).
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Moment the timer counts from: now minus the time already recorded. Shifted on resume
        /// so the time spent paused isn't counted.
        var timerStart: Date
        /// Recorded time while paused; nil while recording.
        var pausedElapsed: TimeInterval?
        var markCount: Int
    }

    /// Folder name, or "Sem pasta".
    var folderName: String
}
