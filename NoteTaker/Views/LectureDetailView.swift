import SwiftData
import SwiftUI

struct LectureDetailView: View {
    let lecture: Lecture
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var tab = Tab.summary
    @State private var player = LecturePlayer()
    @State private var lectureToRename: Lecture?

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
                        if let summary = lecture.summary {
                            SummaryView(summary: summary, player: availablePlayer)
                        }
                    case .transcript:
                        if lecture.segments.isEmpty {
                            // Lectures transcribed before phrase timing was stored.
                            Text(lecture.transcript ?? "")
                                .textSelection(.enabled)
                        } else {
                            TranscriptView(segments: lecture.segments, player: availablePlayer)
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if player.isLoaded { AudioPlayerBar(player: player) }
        }
        .navigationTitle(lecture.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Renomear", systemImage: "pencil") { lectureToRename = lecture }
            }
        }
        .renameLectureAlert($lectureToRename)
        .onAppear { player.load(lecture.audioURL) }
        .onDisappear { player.pause() }
    }

    private var availablePlayer: LecturePlayer? {
        player.isLoaded ? player : nil
    }

    @ViewBuilder
    private var statusSection: some View {
        let isRunning = processor.isProcessing(lecture)
        switch lecture.status {
        case .transcribing where isRunning:
            ProgressView(value: processor.transcriptionProgress[lecture.id] ?? 0) {
                Text("Transcrevendo no aparelho…")
            } currentValueLabel: {
                Text("Pode sair do app: o iPhone continua processando.")
            }
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
