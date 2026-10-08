import Foundation
import SwiftData

/// A user-created group of lectures, typically one per course or project. Folders can be
/// nested; a subfolder inherits its parent's kind and language unless it sets its own.
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
    /// nil for a top-level folder.
    var parent: Folder?
    /// Removing the link only; `dissolve(in:)` moves subfolders up before deleting.
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    var subfolders: [Folder] = []

    init(name: String, parent: Folder? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.parent = parent
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

    /// The kind new recordings in this folder get: its own, else the closest parent's, else Ajustes.
    var recordingKind: RecordingKind {
        kind ?? parent?.recordingKind ?? .standard
    }

    /// The language new recordings in this folder get, inherited like the kind; nil follows Ajustes.
    var recordingLanguage: AppLanguage? {
        language ?? parent?.recordingLanguage
    }

    /// "Faculdade › Cálculo".
    var path: String {
        parent.map { "\($0.path) › \(name)" } ?? name
    }

    /// Lectures in this folder and in every subfolder below it.
    var allLectures: [Lecture] {
        lectures + subfolders.flatMap(\.allLectures)
    }

    var sortedSubfolders: [Folder] {
        subfolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether `folder` is this folder or one below it, where it can't be moved into.
    func contains(_ folder: Folder) -> Bool {
        folder == self || subfolders.contains { $0.contains(folder) }
    }

    /// Deletes the folder, moving its lectures and subfolders up one level so nothing is lost.
    func dissolve(in context: ModelContext) {
        for lecture in lectures { lecture.folder = parent }
        for subfolder in subfolders { subfolder.parent = parent }
        context.delete(self)
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
