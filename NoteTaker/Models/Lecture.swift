import Foundation
import SwiftData

@Model
final class Lecture {
    enum Status: String {
        case recorded, transcribing, transcribed, summarizing, done, failed
    }

    var id: UUID
    /// Empty until the user or the summary provides one; see `displayTitle`.
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    /// File name inside `Storage.recordingsDirectory`. Stored as a name, not a URL,
    /// because the app container path changes between installs.
    var audioFileName: String
    var transcript: String?
    var summaryData: Data?
    var statusRaw: String
    var errorMessage: String?
    /// Spoken language, captured when recording so retries ignore later changes in Ajustes.
    /// The default value lets SwiftData migrate lectures saved before this field existed.
    var languageRaw: String = AppLanguage.portuguese.rawValue
    /// nil means the lecture is unfiled ("Sem pasta").
    var folder: Folder?
    /// JSON-encoded `[TranscriptSegment]`. nil for lectures transcribed before timing was stored.
    var segmentsData: Data?
    /// Seconds into the recording the student marked as important while recording.
    var highlights: [TimeInterval] = []
    /// JSON-encoded `[ChatMessage]`: questions asked about this lecture and their answers.
    var chatData: Data?
    /// Class or meeting, captured when recording like the language.
    var kindRaw: String = RecordingKind.lecture.rawValue
    /// JSON-encoded `MeetingSummary`, the summary of a meeting (`summaryData` is for classes).
    var meetingData: Data?

    init(
        audioFileName: String, duration: TimeInterval, language: AppLanguage, kind: RecordingKind = .lecture,
        folder: Folder? = nil, highlights: [TimeInterval] = [], createdAt: Date = .now
    ) {
        self.id = UUID()
        self.folder = folder
        self.title = ""
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.statusRaw = Status.recorded.rawValue
        self.languageRaw = language.rawValue
        self.kindRaw = kind.rawValue
        self.highlights = highlights
    }

    var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .portuguese
    }

    /// Changing it after the fact keeps both summaries; the status follows the one for the new kind.
    var kind: RecordingKind {
        get { RecordingKind(rawValue: kindRaw) ?? .lecture }
        set {
            kindRaw = newValue.rawValue
            if status == .done || status == .transcribed, transcript != nil {
                status = hasSummary ? .done : .transcribed
            }
        }
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var summary: LectureSummary? {
        get { summaryData.flatMap { try? JSONDecoder().decode(LectureSummary.self, from: $0) } }
        set { summaryData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var meeting: MeetingSummary? {
        get { meetingData.flatMap { try? JSONDecoder().decode(MeetingSummary.self, from: $0) } }
        set { meetingData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Whether the summary for the current kind exists (class summary or meeting minutes).
    var hasSummary: Bool {
        kind == .meeting ? meetingData != nil : summaryData != nil
    }

    var segments: [TranscriptSegment] {
        get { segmentsData.flatMap { try? JSONDecoder().decode([TranscriptSegment].self, from: $0) } ?? [] }
        set { segmentsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var chat: [ChatMessage] {
        get { chatData.flatMap { try? JSONDecoder().decode([ChatMessage].self, from: $0) } ?? [] }
        set { chatData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var audioURL: URL {
        Storage.recordingsDirectory.appending(path: audioFileName)
    }

    var displayTitle: String {
        title.isEmpty ? "\(kind.displayName) de \(createdAt.formatted(date: .abbreviated, time: .shortened))" : title
    }
}

enum Storage {
    static var recordingsDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// ADTS AAC: survives the app being killed mid-recording. Older lectures use .m4a.
    static func newRecordingURL() -> URL {
        recordingsDirectory.appending(path: "\(UUID().uuidString).aac")
    }
}
