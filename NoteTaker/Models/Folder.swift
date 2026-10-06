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
}
