import SwiftData
import SwiftUI

struct LectureDetailView: View {
    let lecture: Lecture
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var tab = Tab.summary

    private enum Tab {
        case summary, transcript
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(lecture.createdAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    Spacer()
                    Text(Duration.seconds(lecture.duration), format: .time(pattern: .hourMinuteSecond))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                statusSection

                if lecture.transcript != nil {
                    Picker("Conteúdo", selection: $tab) {
                        Text("Resumo").tag(Tab.summary)
                        Text("Transcrição").tag(Tab.transcript)
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .summary:
                        if let summary = lecture.summary { SummaryView(summary: summary) }
                    case .transcript:
                        Text(lecture.transcript ?? "")
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(lecture.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var statusSection: some View {
        let isRunning = processor.isProcessing(lecture)
        switch lecture.status {
        case .transcribing where isRunning:
            ProgressView("Transcrevendo no aparelho… mantenha o app aberto.")
                .frame(maxWidth: .infinity)
        case .summarizing where isRunning:
            ProgressView("Gerando resumo com o \(SummaryProvider.selected.displayName)…")
                .frame(maxWidth: .infinity)
        case .done:
            EmptyView()
        default:
            // Failed, never started, or interrupted because the app was closed mid-way.
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    lecture.errorMessage ?? "O processamento desta aula foi interrompido.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Button("Tentar novamente", systemImage: "arrow.clockwise") {
                    processor.process(lecture, in: context)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SummaryView: View {
    let summary: LectureSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Resumo", systemImage: "doc.text") {
                Text(summary.overview)
            }

            section("Pontos importantes", systemImage: "star") {
                bullets(summary.keyPoints)
            }

            if !summary.concepts.isEmpty {
                section("Conceitos", systemImage: "book") {
                    ForEach(summary.concepts, id: \.self) { concept in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(concept.term).bold()
                            Text(concept.explanation).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !summary.assignments.isEmpty {
                section("Provas, trabalhos e avisos", systemImage: "calendar.badge.exclamationmark") {
                    bullets(summary.assignments)
                }
            }

            if !summary.reviewQuestions.isEmpty {
                section("Perguntas para revisar", systemImage: "questionmark.bubble") {
                    bullets(summary.reviewQuestions)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func section(
        _ title: String, systemImage: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
            content()
        }
    }

    private func bullets(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(item)
            }
        }
    }
}
