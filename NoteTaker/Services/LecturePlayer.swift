import AVFoundation
import Observation

/// Plays a lecture's recording so the user can jump to the moment a phrase or summary point
/// was said. `currentTime` and `isPlaying` aren't observable; read them from a `TimelineView`.
@MainActor
@Observable
final class LecturePlayer {
    private var player: AVAudioPlayer?
    private(set) var duration: TimeInterval = 0

    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }
    var isLoaded: Bool { player != nil }

    func load(_ url: URL) {
        guard player == nil, FileManager.default.fileExists(atPath: url.path) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    /// Plays from `time`, or from the current position when nil.
    func play(from time: TimeInterval? = nil) {
        guard let player else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        if let time { player.currentTime = min(max(time, 0), player.duration) }
        player.play()
    }

    func pause() {
        player?.pause()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = min(max(time, 0), duration)
    }
}
