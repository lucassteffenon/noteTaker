import Foundation
import SwiftData

/// A user-created group of lectures, typically one per course.
@Model
final class Folder {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Language for lectures recorded in this folder; nil follows the one in Ajustes.
    var languageRaw: String?
    /// Class or meeting for recordings in this folder; nil follows the default in Ajustes.
    var kindRaw: String?
    /// JSON-encoded `[ClassTime]`: when this course meets, so recordings are filed here.
    var scheduleData: Data?
    /// JSON-encoded `StoredStudyGuide`.
    var studyGuideData: Data?
    /// Deleting a folder keeps its lectures; they become unfiled.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.folder)
    var lectures: [Lecture] = []

    init(name: String, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
    }

    var language: AppLanguage? {
        get { languageRaw.flatMap(AppLanguage.init) }
        set { languageRaw = newValue?.rawValue }
    }

    var kind: RecordingKind? {
        get { kindRaw.flatMap(RecordingKind.init) }
        set { kindRaw = newValue?.rawValue }
    }

    /// The kind new recordings in this folder get.
    var recordingKind: RecordingKind {
        kind ?? .standard
    }

    var schedule: [ClassTime] {
        get { scheduleData.flatMap { try? JSONDecoder().decode([ClassTime].self, from: $0) } ?? [] }
        set { scheduleData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var studyGuide: StoredStudyGuide? {
        get { studyGuideData.flatMap { try? JSONDecoder().decode(StoredStudyGuide.self, from: $0) } }
        set { studyGuideData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The folder whose class is happening at `date`, if any.
    static func inClass(at date: Date, among folders: [Folder]) -> Folder? {
        folders.first { $0.schedule.contains { $0.contains(date) } }
    }
}
