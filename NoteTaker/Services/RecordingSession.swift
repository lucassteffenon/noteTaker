import ActivityKit
import AVFoundation
import Observation
import OSLog
import SwiftData

/// A recording in progress. Owned by `RecordingSession`, not by a view, so it survives the
/// system tearing down the app's UI in the background: when the app comes back, the library
/// presents `RecordingView` again for it.
@MainActor
final class ActiveRecording: Identifiable {
    let id = UUID()
    let folder: Folder?
    /// Fixed when recording starts, so the whole lecture uses one language.
    let language: AppLanguage
    /// Class or meeting, fixed when recording starts.
    let kind: RecordingKind
    let recorder = AudioRecorder()

    init(folder: Folder?) {
        self.folder = folder
        language = folder?.language ?? .lecture
        kind = folder?.recordingKind ?? .standard
    }
}

/// The single recording the app can have at a time, plus recovery of recordings cut short
/// because the app was closed or crashed.
@MainActor
@Observable
final class RecordingSession {
    static let shared = RecordingSession()

    /// Non-nil while recording; the library shows `RecordingView` for it.
    var current: ActiveRecording?
    /// Lectures rebuilt at launch from interrupted recordings, to tell the user.
    var recoveredCount = 0

    @ObservationIgnored private var hasRecovered = false
    private static let logger = Logger(subsystem: "com.lucassteffenon.NoteTaker", category: "RecordingSession")

    func begin(folder: Folder?) {
        guard current == nil else { return }
        current = ActiveRecording(folder: folder)
        RecordingCommands.shared.isRecording = true
        RecordingCommands.shared.markMoment = { [weak self] in self?.markMoment() }
    }

    /// Starts the recorder of the current recording, once.
    func startRecorder() async throws {
        guard let current, !current.recorder.isRecording else { return }
        try await current.recorder.start(folderName: current.folder?.name ?? "Sem pasta")
        saveProgress()
    }

    /// From the recording screen or the Live Activity.
    func markMoment() {
        current?.recorder.markMoment()
        saveProgress()
    }

    func end() {
        current = nil
        RecordingCommands.shared.isRecording = false
        RecordingCommands.shared.markMoment = nil
        UserDefaults.standard.removeObject(forKey: Progress.defaultsKey)
    }

    /// What recovery needs to rebuild the lecture if the app dies mid-recording.
    private struct Progress: Codable {
        static let defaultsKey = "recordingInProgress"
        var fileName: String
        var folderID: UUID?
        var language: AppLanguage
        /// nil for progress saved before recordings had a kind.
        var kind: RecordingKind?
        var marks: [TimeInterval]
    }

    private func saveProgress() {
        guard let current, let fileName = current.recorder.fileName else { return }
        let progress = Progress(
            fileName: fileName, folderID: current.folder?.id, language: current.language, kind: current.kind,
            marks: current.recorder.marks
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(progress), forKey: Progress.defaultsKey)
    }

    private func savedProgress() -> Progress? {
        UserDefaults.standard.data(forKey: Progress.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Progress.self, from: $0) }
    }

    /// Once per launch: turns audio files that no lecture points to into lectures (they come
    /// from recordings interrupted before "Concluir"), and ends Live Activities left behind.
    func recoverInterruptedRecordings(in context: ModelContext, processor: LectureProcessor) async {
        guard !hasRecovered else { return }
        hasRecovered = true

        if current == nil {
            for activity in Activity<RecordingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        let known = Set(((try? context.fetch(FetchDescriptor<Lecture>())) ?? []).map(\.audioFileName))
        let activeFile = current?.recorder.fileName
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Storage.recordingsDirectory, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        for url in files where !known.contains(url.lastPathComponent) && url.lastPathComponent != activeFile {
            // Recordings made before the switch to ADTS (.m4a) are unreadable when cut short;
            // they are left on disk rather than deleted.
            guard let file = try? AVAudioFile(forReading: url) else {
                Self.logger.error("Unreadable interrupted recording: \(url.lastPathComponent)")
                continue
            }
            let duration = Double(file.length) / file.fileFormat.sampleRate
            guard duration >= 1 else { continue }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            let progress = savedProgress().flatMap { $0.fileName == url.lastPathComponent ? $0 : nil }
            let folderID = progress?.folderID
            let folder = folderID.flatMap { id in
                try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })).first
            }
            let lecture = Lecture(
                audioFileName: url.lastPathComponent, duration: duration, language: progress?.language ?? .lecture,
                kind: progress?.kind ?? folder?.recordingKind ?? .standard, folder: folder,
                highlights: progress?.marks ?? [], createdAt: created
            )
            context.insert(lecture)
            try? context.save()
            processor.process(lecture, in: context, summarize: false)
            recoveredCount += 1
        }
        if current == nil {
            UserDefaults.standard.removeObject(forKey: Progress.defaultsKey)
        }
    }
}
