import Foundation

/// One recognized phrase with its position in the recording, used to jump the audio to it.
struct TranscriptSegment: Codable, Hashable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

extension TimeInterval {
    /// "12:34", or "1:02:03" past the first hour.
    var clockText: String {
        // Rounded down, so the label never shows a time later than where playback starts.
        Duration.seconds(rounded(.down)).formatted(.time(pattern: self >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
