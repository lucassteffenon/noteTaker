import Foundation
import SwiftData

@Model
final class Lecture {
    enum Status: String {
        case recorded, transcribing, summarizing, done, failed
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

    init(audioFileName: String, duration: TimeInterval, createdAt: Date = .now) {
        self.id = UUID()
        self.title = ""
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.statusRaw = Status.recorded.rawValue
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var summary: LectureSummary? {
        get { summaryData.flatMap { try? JSONDecoder().decode(LectureSummary.self, from: $0) } }
        set { summaryData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var audioURL: URL {
        Storage.recordingsDirectory.appending(path: audioFileName)
    }

    var displayTitle: String {
        title.isEmpty ? "Aula de \(createdAt.formatted(date: .abbreviated, time: .shortened))" : title
    }
}

enum Storage {
    static var recordingsDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func newRecordingURL() -> URL {
        recordingsDirectory.appending(path: "\(UUID().uuidString).m4a")
    }
}
