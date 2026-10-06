import Foundation

/// Shape of the JSON returned by the AI. Must stay in sync with `SummaryPrompt.schema`.
struct LectureSummary: Codable, Hashable, Sendable {
    struct KeyPoint: Codable, Hashable, Sendable {
        var text: String
        /// Seconds into the recording where the point is explained; -1 or nil when unknown.
        var startSeconds: Double?
        /// Comes from a stretch the student marked as important while recording.
        var important = false

        enum CodingKeys: String, CodingKey {
            case text, startSeconds, important
        }

        init(from decoder: any Decoder) throws {
            // Summaries saved before timestamps existed stored key points as plain strings.
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.text = text
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds)
            important = try container.decodeIfPresent(Bool.self, forKey: .important) ?? false
        }
    }

    struct Concept: Codable, Hashable, Sendable {
        var term: String
        var explanation: String
        var startSeconds: Double?
    }

    struct ReviewQuestion: Codable, Hashable, Sendable {
        var question: String
        /// nil for summaries saved before answers were requested.
        var answer: String?

        init(from decoder: any Decoder) throws {
            // Older summaries stored only the question, as a plain string.
            if let question = try? decoder.singleValueContainer().decode(String.self) {
                self.question = question
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            question = try container.decode(String.self, forKey: .question)
            answer = try container.decodeIfPresent(String.self, forKey: .answer)
        }
    }

    var title: String
    var overview: String
    var keyPoints: [KeyPoint]
    var concepts: [Concept]
    var assignments: [String]
    var reviewQuestions: [ReviewQuestion]
}

extension Optional<Double> {
    /// A usable position in the recording, or nil for the "-1 = unknown" convention.
    var playbackTime: TimeInterval? {
        flatMap { $0 >= 0 ? $0 : nil }
    }
}
