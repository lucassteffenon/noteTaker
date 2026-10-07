import SwiftData
import SwiftUI

struct LectureDetailView: View {
    let lecture: Lecture
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var tab = Tab.summary
    @State private var player = LecturePlayer()
    @State private var lectureToRename: Lecture?
    @State private var isReviewing = false
    @State private var isAsking = false

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

                if !lecture.highlights.isEmpty {
                    markedMoments
                }

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
                            TranscriptView(
                                segments: lecture.segments, highlights: lecture.highlights, player: availablePlayer
                            )
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
                Button("Perguntar", systemImage: "bubble.left.and.text.bubble.right") { isAsking = true }
                    .disabled(lecture.transcript == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Revisar", systemImage: "rectangle.on.rectangle.angled") { isReviewing = true }
                    .disabled(flashcards.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Mais", systemImage: "ellipsis") {
                    Button("Renomear", systemImage: "pencil") { lectureToRename = lecture }
                    if let summary = lecture.summary {
                        ExportMenu(
                            document: ExportDocument(lecture: lecture, summary: summary),
                            transcript: lecture.transcript
                        )
                    } else if let transcript = lecture.transcript {
                        ShareLink(item: transcript, subject: Text(lecture.displayTitle)) {
                            Label("Exportar transcrição", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isReviewing) {
            FlashcardsView(title: lecture.displayTitle, cards: flashcards)
        }
        .sheet(isPresented: $isAsking) {
            LectureChatView(lecture: lecture) { start in
                player.play(from: start)
            }
        }
        .renameLectureAlert($lectureToRename)
        .onAppear {
            player.load(lecture.audioURL)
            if lecture.summary == nil { tab = .transcript }
        }
        .onDisappear { player.pause() }
    }

    private var availablePlayer: LecturePlayer? {
        player.isLoaded ? player : nil
    }

    private var flashcards: [Flashcard] {
        Flashcard.cards(from: [lecture])
    }

    /// The moments starred while recording, each playing the stretch it points at.
    private var markedMoments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Momentos marcados")
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.subheadline.bold())
            ScrollView(.horizontal) {
                HStack {
                    ForEach(lecture.highlights, id: \.self) { mark in
                        let start = max(mark - Highlight.lookback, 0)
                        Button {
                            player.play(from: start)
                        } label: {
                            Label(mark.clockText, systemImage: "play.fill")
                                .font(.caption.monospacedDigit())
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(.orange)
                        .disabled(availablePlayer == nil)
                        .accessibilityLabel("Ouvir o momento marcado em \(mark.clockText)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
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
        case .transcribed:
            summaryPrompt
        default:
            // Failed, never started, or interrupted because the app was closed mid-way.
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    lecture.errorMessage ?? "O processamento desta aula foi interrompido.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Button("Tentar novamente", systemImage: "arrow.clockwise") {
                    // Without a transcript the failure was in transcription, which stays free.
                    processor.process(lecture, in: context, summarize: lecture.transcript != nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Shown once the free on-device transcription is done: the paid summary only runs on request.
    private var summaryPrompt: some View {
        let provider = SummaryProvider.selected
        let model = provider.selectedModel
        return VStack(alignment: .leading, spacing: 12) {
            Label("Transcrição pronta. O resumo só é gerado se você pedir.", systemImage: "text.bubble")
                .foregroundStyle(.secondary)
            Button("Gerar resumo", systemImage: "sparkles") {
                tab = .summary
                processor.process(lecture, in: context, summarize: true)
            }
            .buttonStyle(.borderedProminent)
            Text("\(model.name) · \(model.cost) por aula de 1h30")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
