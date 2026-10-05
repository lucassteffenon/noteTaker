import AVFoundation
import Observation

enum RecorderError: LocalizedError {
    case permissionDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Sem acesso ao microfone. Libere em Ajustes > Privacidade > Microfone."
        case .couldNotStart:
            "Não foi possível iniciar a gravação."
        }
    }
}

/// Records the lecture to an AAC file. Keeps recording with the screen locked
/// (UIBackgroundModes = audio) and resumes after interruptions such as calls.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var isPaused = false

    private var recorder: AVAudioRecorder?
    private var interruptionObserver: NSObjectProtocol?

    /// Not observable; read it from a `TimelineView`.
    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        // Mono 16 kHz AAC is plenty for speech: about 30 MB for a two-hour lecture.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: Storage.newRecordingURL(), settings: settings)
        guard recorder.record() else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        isRecording = true
        isPaused = false
        observeInterruptions(session)
    }

    func pause() {
        recorder?.pause()
        isPaused = true
    }

    func resume() {
        recorder?.record()
        isPaused = false
    }

    /// Stops recording and returns the file and its duration.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        tearDown()
        return (recorder.url, duration)
    }

    func discard() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        tearDown()
    }

    private func tearDown() {
        recorder = nil
        isRecording = false
        isPaused = false
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions(_ session: AVAudioSession) {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            MainActor.assumeIsolated {
                guard let self, self.isRecording, !self.isPaused else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                self.recorder?.record()
            }
        }
    }
}
