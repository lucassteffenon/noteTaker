import Foundation

/// Shape of the JSON returned by Claude. Must stay in sync with `Summarizer.schema`.
struct LectureSummary: Codable, Hashable, Sendable {
    struct Concept: Codable, Hashable, Sendable {
        var term: String
        var explanation: String
    }

    var title: String
    var overview: String
    var keyPoints: [String]
    var concepts: [Concept]
    var assignments: [String]
    var reviewQuestions: [String]
}
