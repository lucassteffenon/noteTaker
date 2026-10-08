import AVFoundation
import Observation
import OSLog
import UIKit

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
/// Mirrors its state in the recording Live Activity.
///
/// The recording is written in segments: a new one starts after every pause or interruption,
/// and `stop()` joins them into the first file. Calling `record()` again on an
/// `AVAudioRecorder` that an interruption stopped recreates its file, which erased everything
/// recorded before the interruption.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var isPaused = false
    /// A call or another app's audio took the microphone; recording resumes when it ends.
    private(set) var isInterrupted = false
    /// Seconds into the recording the student marked as important.
    private(set) var marks: [TimeInterval] = []

    /// The segment being recorded, nil while paused or interrupted.
    private var recorder: AVAudioRecorder?
    /// The first segment, which ends up holding the whole recording.
    private var mainURL: URL?
    private var segmentCount = 0
    /// Length of the segments already finished.
    private var recordedBefore: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private let activity = RecordingActivity()
    private static let logger = Logger(subsystem: "com.lucassteffenon.NoteTaker", category: "AudioRecorder")

    /// The recording's file name in `Storage.recordingsDirectory`, once started.
    var fileName: String? { mainURL?.lastPathComponent }

    /// Not observable; read it from a `TimelineView`.
    var currentTime: TimeInterval { recordedBefore + (recorder?.currentTime ?? 0) }

    /// `folderName` is shown on the Live Activity.
    func start(folderName: String) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.permissionDenied
        }
        try Self.activateSession()

        let url = Storage.newRecordingURL()
        try startSegment(at: url)
        mainURL = url
        segmentCount = 1
        recordedBefore = 0
        isRecording = true
        isPaused = false
        isInterrupted = false
        marks = []
        observeSession()
        activity.start(folderName: folderName)
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        finishSegment()
        isPaused = true
        isInterrupted = false
        updateActivity()
    }

    func resume() {
        guard isRecording, isPaused else { return }
        isPaused = false
        resumeIfStopped()
        updateActivity()
    }

    func markMoment() {
        guard isRecording else { return }
        marks.append(currentTime)
        updateActivity()
    }

    /// Stops recording and returns the file and its duration.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let mainURL else { return nil }
        finishSegment()
        Storage.mergeParts(into: mainURL)
        let duration = recordedBefore
        tearDown()
        return (mainURL, duration)
    }

    func discard() {
        guard let mainURL else { return }
        recorder?.stop()
        recorder = nil
        Storage.deleteRecording(mainURL)
        tearDown()
    }

    // MARK: - Segments

    private static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
    }

    private func startSegment(at url: URL) throws {
        // Mono 16 kHz AAC is plenty for speech: about 30 MB for a two-hour lecture. The file is
        // ADTS (.aac, see `Storage.newRecordingURL`): unlike .m4a, which is only readable once
        // `stop()` writes its index, it stays playable if the app is killed mid-recording, and
        // segments can be joined by appending their bytes.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
    }

    /// Stops the current segment for good and adds its length to `recordedBefore`.
    private func finishSegment() {
        guard let recorder else { return }
        let liveTime = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        // An interruption can stop the recorder and reset `currentTime`, so trust the file.
        let fileTime = (try? AVAudioFile(forReading: recorder.url))
            .map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        recordedBefore += max(fileTime, liveTime)
    }

    /// Starts a new segment if the recording should be running but isn't: after an
    /// interruption, a resume, or the system stopping the recorder without telling us.
    private func resumeIfStopped() {
        guard isRecording, !isPaused, let mainURL else { return }
        if let recorder {
            guard !recorder.isRecording else { return }
            finishSegment()
        }
        do {
            try Self.activateSession()
            try startSegment(at: Storage.partURL(of: mainURL, number: segmentCount + 1))
            segmentCount += 1
            isInterrupted = false
        } catch {
            // Typically in the background, where iOS may refuse to restart the microphone;
            // tried again when the app becomes active.
            Self.logger.error("Could not resume recording: \(error.localizedDescription)")
            isInterrupted = true
        }
        updateActivity()
    }

    private func updateActivity() {
        activity.update(elapsed: currentTime, isPaused: isPaused || isInterrupted, markCount: marks.count)
    }

    private func tearDown() {
        activity.end()
        recorder = nil
        mainURL = nil
        segmentCount = 0
        recordedBefore = 0
        isRecording = false
        isPaused = false
        isInterrupted = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw)
                else { return }
                MainActor.assumeIsolated {
                    guard let self, self.isRecording, !self.isPaused else { return }
                    switch type {
                    case .began:
                        // Close the segment now, so what was recorded so far is safe.
                        self.finishSegment()
                        self.isInterrupted = true
                        self.updateActivity()
                    case .ended:
                        self.resumeIfStopped()
                    @unknown default:
                        break
                    }
                }
            },
            // The audio server restarted: the recorder is dead and the session must be set up again.
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording, !self.isPaused else { return }
                    self.finishSegment()
                    self.resumeIfStopped()
                }
            },
            // An interruption that ended while the app was suspended may never report it.
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resumeIfStopped()
                }
            },
        ]
    }
}
