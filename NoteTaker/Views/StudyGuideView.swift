import SwiftData
import SwiftUI

/// Exam study guide for a folder: generated on request from the lectures' summaries, then
/// saved with the folder until the user regenerates it.
struct StudyGuideView: View {
    let folder: Folder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var sources: [Lecture] { StudyGuidePrompt.sources(in: folder) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isGenerating {
                        ProgressView("Montando o guia com o \(SummaryProvider.selected.displayName)…")
                            .frame(maxWidth: .infinity)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let stored = folder.studyGuide {
                        if stored.lectureTitles.count != sources.count, !isGenerating {
                            outdatedNotice(stored)
                        }
                        StudyGuideContent(stored: stored)
                    } else if !isGenerating {
                        intro
                    }
                }
                .padding()
            }
            .navigationTitle("Guia para a prova")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                }
                if let stored = folder.studyGuide {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Mais", systemImage: "ellipsis") {
                            ExportMenu(document: ExportDocument(folderName: folder.name, stored: stored))
                            Button("Gerar de novo", systemImage: "arrow.clockwise", action: generate)
                                .disabled(isGenerating || sources.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Junta os resumos de todas as aulas de \(folder.name) num material só: o que não pode esquecer (incluindo os momentos marcados com ⭐), os temas, os conceitos, as datas de prova e questões para praticar.")
                .foregroundStyle(.secondary)
            if sources.isEmpty {
                Label("Nenhuma aula desta pasta tem resumo ainda. Gere os resumos primeiro.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button("Gerar guia com \(sources.count) \(sources.count == 1 ? "aula" : "aulas")", systemImage: "sparkles", action: generate)
                    .buttonStyle(.borderedProminent)
                let model = SummaryProvider.selected.selectedModel
                Text("\(model.name) · usa só os resumos, então custa menos que o resumo de uma aula.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outdatedNotice(_ stored: StoredStudyGuide) -> some View {
        let count = sources.count
        return VStack(alignment: .leading, spacing: 8) {
            Label(
                "Este guia usa \(stored.lectureCountText); agora há \(count) com resumo.",
                systemImage: "clock.arrow.circlepath"
            )
            Button("Atualizar guia", systemImage: "arrow.clockwise", action: generate)
                .buttonStyle(.bordered)
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func generate() {
        let lectures = sources
        guard !lectures.isEmpty, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        let request = StudyGuidePrompt.request(folderName: folder.name, lectures: lectures)
        let titles = lectures.map(\.displayTitle)
        Task {
            defer { isGenerating = false }
            do {
                let guide = try await SummaryProvider.selectedClient().respond(to: request, as: StudyGuide.self)
                folder.studyGuide = StoredStudyGuide(guide: guide, createdAt: .now, lectureTitles: titles)
                try? context.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StudyGuideContent: View {
    let stored: StoredStudyGuide

    private var guide: StudyGuide { stored.guide }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Gerado em \(stored.createdAt.formatted(date: .abbreviated, time: .shortened)) a partir de \(stored.lectureCountText)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(guide.overview)

            section("Não pode esquecer", systemImage: "star.fill", tint: .yellow) {
                ForEach(guide.mustKnow, id: \.self) { point in
                    item(point.text, lectures: point.lectures)
                }
            }

            section("Temas", systemImage: "square.stack.3d.up") {
                ForEach(guide.topics, id: \.self) { topic in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title).font(.headline)
                        Text(topic.explanation)
                        lectureCaption(topic.lectures)
                    }
                }
            }

            if !guide.concepts.isEmpty {
                section("Conceitos", systemImage: "book") {
                    ForEach(guide.concepts, id: \.self) { concept in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(concept.term).font(.headline)
                            Text(concept.explanation)
                        }
                    }
                }
            }

            if !guide.assignments.isEmpty {
                section("Provas e prazos", systemImage: "calendar") {
                    ForEach(guide.assignments, id: \.self) { Text("• \($0)") }
                }
            }

            section("Questões para praticar", systemImage: "questionmark.bubble") {
                ForEach(guide.practiceQuestions, id: \.self) { question in
                    DisclosureGroup {
                        Text(question.answer ?? "")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(question.question)
                            .multilineTextAlignment(.leading)
                    }
                    .tint(.primary)
                }
            }

            section("Aulas incluídas", systemImage: "list.number") {
                ForEach(Array(stored.lectureTitles.enumerated()), id: \.offset) { index, title in
                    Text("Aula \(index + 1): \(title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func section(
        _ title: String, systemImage: String, tint: Color = .accentColor, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            .font(.title3.bold())
            content()
        }
    }

    private func item(_ text: String, lectures: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("• \(text)")
            lectureCaption(lectures)
        }
    }

    @ViewBuilder
    private func lectureCaption(_ lectures: [Int]) -> some View {
        if let label = stored.lectureLabel(lectures) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
