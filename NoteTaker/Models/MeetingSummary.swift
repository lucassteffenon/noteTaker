import Foundation

/// Minutes of a recorded meeting, returned by the AI. Must stay in sync with `MeetingPrompt.schema`.
/// `ActionItem.done` and `reminderID` are local state, not part of the schema.
struct MeetingSummary: Codable, Hashable, Sendable {
    struct Decision: Codable, Hashable, Sendable {
        var text: String
        var startSeconds: Double?
    }

    struct ActionItem: Codable, Hashable, Sendable {
        var task: String
        /// Who took it on; empty when nobody was named.
        var owner: String
        /// "yyyy-MM-dd", or empty when no deadline was mentioned.
        var dueDate: String
        var startSeconds: Double?
        var done = false
        /// Set once the task was added to Lembretes.
        var reminderID: String?

        enum CodingKeys: String, CodingKey {
            case task, owner, dueDate, startSeconds, done, reminderID
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            task = try container.decode(String.self, forKey: .task)
            owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
            startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds)
            done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
            reminderID = try container.decodeIfPresent(String.self, forKey: .reminderID)
        }

        var due: Date? {
            guard !dueDate.isEmpty else { return nil }
            return try? Date(dueDate, strategy: Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        }

        /// "Ana · até 12 de out.", or nil when neither is known.
        var details: String? {
            let parts = [
                owner.isEmpty ? nil : owner,
                due.map { "até \($0.formatted(.dateTime.day().month()))" },
            ].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    var title: String
    var overview: String
    /// The subjects discussed; `important` ones come from moments marked while recording.
    var keyPoints: [LectureSummary.KeyPoint]
    var decisions: [Decision]
    var actionItems: [ActionItem]
    var openQuestions: [String]
}
