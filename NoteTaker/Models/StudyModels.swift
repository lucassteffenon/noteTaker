import Foundation

/// One message in the conversation about a lecture. Stored JSON-encoded in `Lecture.chatData`.
struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var role: AITurn.Role
    var text: String
    /// Where the answer is explained in the recording; nil when unknown or for questions.
    var startSeconds: TimeInterval?
}

/// The AI's answer to a question about a lecture. Must stay in sync with `LectureQuestionPrompt.schema`.
struct LectureAnswer: Decodable {
    var answer: String
    var startSeconds: Double
}

/// Exam study guide built from the summaries of every lecture in a folder.
/// Must stay in sync with `StudyGuidePrompt.schema`.
struct StudyGuide: Codable, Hashable, Sendable {
    struct Point: Codable, Hashable, Sendable {
        var text: String
        /// 1-based positions in `StoredStudyGuide.lectureTitles`.
        var lectures: [Int]
    }

    struct Topic: Codable, Hashable, Sendable {
        var title: String
        var explanation: String
        var lectures: [Int]
    }

    var overview: String
    var mustKnow: [Point]
    var topics: [Topic]
    var concepts: [LectureSummary.Concept]
    var assignments: [String]
    var practiceQuestions: [LectureSummary.ReviewQuestion]
}

/// A generated guide plus what it was generated from. Stored JSON-encoded in `Folder.studyGuideData`.
struct StoredStudyGuide: Codable, Hashable, Sendable {
    var guide: StudyGuide
    var createdAt: Date
    /// Titles of the lectures sent to the AI, in the order it numbered them.
    var lectureTitles: [String]

    /// "1 aula" or "3 aulas".
    var lectureCountText: String {
        lectureTitles.count == 1 ? "1 aula" : "\(lectureTitles.count) aulas"
    }

    /// "Aulas 1 e 3" for the lecture numbers the AI cited.
    func lectureLabel(_ numbers: [Int]) -> String? {
        let valid = numbers.filter { lectureTitles.indices.contains($0 - 1) }.sorted()
        guard !valid.isEmpty else { return nil }
        let list = valid.map(String.init).formatted(.list(type: .and, width: .standard))
        return valid.count == 1 ? "Aula \(list)" : "Aulas \(list)"
    }
}

/// A weekly class time for a folder, used to file new recordings automatically.
struct ClassTime: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// `Calendar` weekday: 1 = Sunday … 7 = Saturday.
    var weekday: Int
    /// Minutes since midnight.
    var start: Int
    var end: Int

    /// Recording can start a little early, when the student arrives before the class.
    static let earlyMargin = 15

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard parts.weekday == weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let minutes = hour * 60 + minute
        return minutes >= start - Self.earlyMargin && minutes <= end
    }

    var label: String {
        "\(Self.dayName(weekday)), \(Self.clock(start))–\(Self.clock(end))"
    }

    /// "Terça-feira": only the first letter capitalized, as Portuguese writes weekdays in a list.
    static func dayName(_ weekday: Int) -> String {
        let name = Calendar.current.weekdaySymbols[weekday - 1]
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
