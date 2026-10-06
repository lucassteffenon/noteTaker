import Foundation

/// Shape of the JSON returned by the AI. Must stay in sync with `SummaryPrompt.schema`.
struct LectureSummary: Codable, Hashable, Sendable {
    struct KeyPoint: Codable, Hashable, Sendable {
        var text: String
        /// Seconds into the recording where the point is explained; -1 or nil when unknown.
        var startSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case text, startSeconds
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
        }
    }

    struct Concept: Codable, Hashable, Sendable {
        var term: String
        var explanation: String
        var startSeconds: Double?
    }

    var title: String
    var overview: String
    var keyPoints: [KeyPoint]
    var concepts: [Concept]
    var assignments: [String]
    var reviewQuestions: [String]
}

extension Optional<Double> {
    /// A usable position in the recording, or nil for the "-1 = unknown" convention.
    var playbackTime: TimeInterval? {
        flatMap { $0 >= 0 ? $0 : nil }
    }
}
