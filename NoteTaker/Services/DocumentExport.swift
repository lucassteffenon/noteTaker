import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A summary or study guide laid out once and rendered as Markdown (to share as text, e.g. to
/// Notes) or as a paginated PDF.
struct ExportDocument: Sendable {
    struct Pair: Hashable, Sendable {
        var title: String
        var text: String?
    }

    enum Block: Hashable, Sendable {
        case heading(String)
        case subheading(String)
        case paragraph(String)
        case caption(String)
        case bullets([String])
        /// Term in bold, then its explanation.
        case definitions([Pair])
        /// Question in bold, answer below.
        case questions([Pair])
    }

    var title: String
    var subtitle: String
    var blocks: [Block]

    var fileName: String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        return String(cleaned.prefix(80))
    }

    var markdown: String {
        var lines = ["# \(title)", "_\(subtitle)_"]
        for block in blocks {
            switch block {
            case .heading(let text): lines.append("## \(text)")
            case .subheading(let text): lines.append("### \(text)")
            case .paragraph(let text): lines.append(text)
            case .caption(let text): lines.append("_\(text)_")
            case .bullets(let items): lines.append(items.map { "- \($0)" }.joined(separator: "\n"))
            case .definitions(let pairs):
                lines.append(pairs.map { "- **\($0.title)**: \($0.text ?? "")" }.joined(separator: "\n"))
            case .questions(let pairs):
                lines.append(pairs.enumerated().map { index, pair in
                    "\(index + 1). **\(pair.title)**" + (pair.text.map { "\n   \($0)" } ?? "")
                }.joined(separator: "\n"))
            }
        }
        return lines.joined(separator: "\n\n") + "\n"
    }

    var html: String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
        }
        var body = "<h1>\(escape(title))</h1><p class=\"meta\">\(escape(subtitle))</p>"
        for block in blocks {
            switch block {
            case .heading(let text): body += "<h2>\(escape(text))</h2>"
            case .subheading(let text): body += "<h3>\(escape(text))</h3>"
            case .paragraph(let text): body += "<p>\(escape(text))</p>"
            case .caption(let text): body += "<p class=\"meta\">\(escape(text))</p>"
            case .bullets(let items):
                body += "<ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
            case .definitions(let pairs):
                body += "<ul>" + pairs.map { "<li><b>\(escape($0.title))</b>: \(escape($0.text ?? ""))</li>" }.joined() + "</ul>"
            case .questions(let pairs):
                body += "<ol>" + pairs.map { pair in
                    "<li><b>\(escape(pair.title))</b>" + (pair.text.map { "<br>\(escape($0))" } ?? "") + "</li>"
                }.joined() + "</ol>"
            }
        }
        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica; font-size: 11pt; line-height: 1.45; color: #111; }
        h1 { font-size: 20pt; margin-bottom: 2pt; }
        h2 { font-size: 14pt; margin-top: 18pt; border-bottom: 1px solid #ccc; padding-bottom: 2pt; }
        h3 { font-size: 12pt; margin-bottom: 2pt; }
        .meta { color: #666; font-size: 9.5pt; }
        li { margin-bottom: 5pt; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// A4 pages with margins. UIKit's print formatter lays out the HTML, so this runs on the main actor.
    @MainActor
    func pdfData() -> Data {
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        // UIPrintPageRenderer has no public setters for these; KVC is the documented workaround.
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 48, dy: 54), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, ["Title": title])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
}

/// Shares an `ExportDocument` as a PDF file, rendered only when the user actually shares it.
struct PDFExport: Transferable {
    let document: ExportDocument

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            let url = URL.temporaryDirectory.appending(path: "\(export.document.fileName).pdf")
            let data = await export.document.pdfData()
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// "Exportar" menu: the document as PDF or as Markdown text.
struct ExportMenu: View {
    let document: ExportDocument
    /// Extra plain-text item, e.g. the full transcript.
    var transcript: String?

    var body: some View {
        Menu("Exportar", systemImage: "square.and.arrow.up") {
            ShareLink(
                item: PDFExport(document: document),
                preview: SharePreview(document.title, image: Image(systemName: "doc.richtext"))
            ) {
                Label("PDF", systemImage: "doc.richtext")
            }
            ShareLink(item: document.markdown, subject: Text(document.title), preview: SharePreview(document.title)) {
                Label("Texto (Markdown)", systemImage: "doc.plaintext")
            }
            if let transcript {
                ShareLink(item: transcript, subject: Text(document.title), preview: SharePreview("Transcrição")) {
                    Label("Transcrição", systemImage: "text.bubble")
                }
            }
        }
    }
}

extension ExportDocument {
    private static func subtitle(for lecture: Lecture) -> String {
        [
            lecture.folder?.name,
            lecture.createdAt.formatted(date: .long, time: .shortened),
            Duration.seconds(lecture.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)),
        ].compactMap(\.self).joined(separator: " · ")
    }

    init(lecture: Lecture, summary: LectureSummary) {
        title = lecture.displayTitle
        subtitle = Self.subtitle(for: lecture)
        var blocks: [Block] = [.heading("Resumo")]
        blocks += summary.overview.components(separatedBy: "\n\n").map(Block.paragraph)
        blocks += [.heading("Pontos principais"), .bullets(summary.keyPoints.map { ($0.important ? "⭐ " : "") + $0.text })]
        if !summary.concepts.isEmpty {
            blocks += [.heading("Conceitos"), .definitions(summary.concepts.map { Pair(title: $0.term, text: $0.explanation) })]
        }
        if !summary.assignments.isEmpty {
            blocks += [.heading("Provas, trabalhos e avisos"), .bullets(summary.assignments)]
        }
        if !summary.reviewQuestions.isEmpty {
            blocks += [.heading("Perguntas de revisão"), .questions(summary.reviewQuestions.map { Pair(title: $0.question, text: $0.answer) })]
        }
        self.blocks = blocks
    }

    init(lecture: Lecture, meeting: MeetingSummary) {
        title = lecture.displayTitle
        subtitle = Self.subtitle(for: lecture)
        var blocks: [Block] = [.heading("Resumo")]
        blocks += meeting.overview.components(separatedBy: "\n\n").map(Block.paragraph)
        if !meeting.decisions.isEmpty {
            blocks += [.heading("Decisões"), .bullets(meeting.decisions.map(\.text))]
        }
        if !meeting.actionItems.isEmpty {
            blocks += [.heading("Tarefas"), .bullets(meeting.actionItems.map { item in
                (item.done ? "[feita] " : "") + item.task + (item.details.map { " (\($0))" } ?? "")
            })]
        }
        if !meeting.openQuestions.isEmpty {
            blocks += [.heading("Em aberto"), .bullets(meeting.openQuestions)]
        }
        if !meeting.keyPoints.isEmpty {
            blocks += [
                .heading("Assuntos discutidos"),
                .bullets(meeting.keyPoints.map { ($0.important ? "⭐ " : "") + $0.text }),
            ]
        }
        self.blocks = blocks
    }

    init(folderName: String, stored: StoredStudyGuide) {
        let guide = stored.guide
        title = "Guia para a prova: \(folderName)"
        subtitle = "Gerado em \(stored.createdAt.formatted(date: .long, time: .omitted)) a partir de \(stored.lectureCountText)"
        func withLectures(_ text: String, _ numbers: [Int]) -> String {
            stored.lectureLabel(numbers).map { "\(text) (\($0))" } ?? text
        }
        var blocks: [Block] = [.heading("Visão geral")]
        blocks += guide.overview.components(separatedBy: "\n\n").map(Block.paragraph)
        blocks += [.heading("Não pode esquecer"), .bullets(guide.mustKnow.map { withLectures($0.text, $0.lectures) })]
        blocks.append(.heading("Temas"))
        for topic in guide.topics {
            blocks.append(.subheading(topic.title))
            if let label = stored.lectureLabel(topic.lectures) { blocks.append(.caption(label)) }
            blocks.append(.paragraph(topic.explanation))
        }
        if !guide.concepts.isEmpty {
            blocks += [.heading("Conceitos"), .definitions(guide.concepts.map { Pair(title: $0.term, text: $0.explanation) })]
        }
        if !guide.assignments.isEmpty {
            blocks += [.heading("Provas e prazos"), .bullets(guide.assignments)]
        }
        blocks += [
            .heading("Questões para praticar"),
            .questions(guide.practiceQuestions.map { Pair(title: $0.question, text: $0.answer) }),
            .heading("Aulas incluídas"),
            .bullets(stored.lectureTitles.enumerated().map { "Aula \($0.offset + 1): \($0.element)" }),
        ]
        self.blocks = blocks
    }
}
