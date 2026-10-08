import SwiftData
import SwiftUI

/// Lectures whose title, summary or transcript contain `query` (ignoring case and accents),
/// each with the passage where it was found.
struct LectureSearchResults: View {
    let query: String
    @Query(sort: \Lecture.createdAt, order: .reverse) private var lectures: [Lecture]

    var body: some View {
        let matches = lectures.compactMap { LectureMatch(lecture: $0, query: query) }
        if matches.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(matches, id: \.lecture.id) { match in
                NavigationLink(value: match.lecture) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.lecture.displayTitle)
                            .font(.headline)
                            .lineLimit(2)
                        if let snippet = match.snippet {
                            Text(snippet)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        HStack(spacing: 6) {
                            Label(match.source, systemImage: match.sourceIcon)
                            if let time = match.time {
                                Text("· \(time.clockText)")
                            }
                            Spacer()
                            Text(match.lecture.folder?.path ?? "Sem pasta")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Where a lecture matched the search. Title matches have no snippet.
private struct LectureMatch {
    let lecture: Lecture
    let source: String
    let sourceIcon: String
    let snippet: AttributedString?
    /// Position in the recording, for transcript matches.
    let time: TimeInterval?

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    init?(lecture: Lecture, query: String) {
        self.lecture = lecture
        if let text = Self.summaryTexts(lecture).first(where: { $0.range(of: query, options: Self.options) != nil }) {
            (source, sourceIcon, time) = ("Resumo", "doc.text", nil)
            snippet = Self.snippet(of: text, around: query)
        } else if let segment = lecture.segments.first(where: { $0.text.range(of: query, options: Self.options) != nil }) {
            (source, sourceIcon, time) = ("Transcrição", "text.bubble", segment.start)
            snippet = Self.snippet(of: segment.text, around: query)
        } else if lecture.segments.isEmpty, let transcript = lecture.transcript,
                  transcript.range(of: query, options: Self.options) != nil {
            (source, sourceIcon, time) = ("Transcrição", "text.bubble", nil)
            snippet = Self.snippet(of: transcript, around: query)
        } else if lecture.displayTitle.range(of: query, options: Self.options) != nil {
            (source, sourceIcon, time, snippet) = ("Título", "textformat", nil, nil)
        } else {
            return nil
        }
    }

    /// Texts of the class summary and of the meeting minutes, whichever the lecture has.
    private static func summaryTexts(_ lecture: Lecture) -> [String] {
        var texts: [String] = []
        if let summary = lecture.summary {
            texts += [summary.overview]
                + summary.keyPoints.map(\.text)
                + summary.concepts.map { "\($0.term): \($0.explanation)" }
                + summary.assignments
                + summary.reviewQuestions.map(\.question)
        }
        if let minutes = lecture.meeting {
            texts += [minutes.overview]
                + minutes.decisions.map(\.text)
                + minutes.actionItems.map(\.task)
                + minutes.openQuestions
                + minutes.keyPoints.map(\.text)
        }
        return texts
    }

    /// About a line of text around the first match, with the match in bold.
    private static func snippet(of text: String, around query: String) -> AttributedString? {
        guard let match = text.range(of: query, options: options) else { return nil }
        let start = text.index(match.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        var result = AttributedString(start > text.startIndex ? "…" : "")
        result += AttributedString(text[start..<match.lowerBound])
        var found = AttributedString(text[match])
        found.inlinePresentationIntent = .stronglyEmphasized
        found.foregroundColor = .primary
        result += found
        result += AttributedString(text[match.upperBound..<end])
        if end < text.endIndex { result += AttributedString("…") }
        return result
    }
}
