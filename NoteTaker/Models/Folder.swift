import Foundation
import SwiftData

/// A user-created group of lectures, typically one per course.
@Model
final class Folder {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Deleting a folder keeps its lectures; they become unfiled.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.folder)
    var lectures: [Lecture] = []

    init(name: String, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
    }
}
