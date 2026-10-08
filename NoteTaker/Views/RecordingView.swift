import SwiftData
import SwiftUI

/// The recording screen for `RecordingSession.shared.current`. The recorder lives in the
/// session, so if the system rebuilds the UI this screen reappears and picks it up again.
struct RecordingView: View {
    let recording: ActiveRecording
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var errorMessage: String?
    @State private var confirmDiscard = false

    private var recorder: AudioRecorder { recording.recorder }
    private var folder: Folder? { recording.folder }
    private var language: AppLanguage { recording.language }
    private var session: RecordingSession { .shared }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 72))
                .foregroundStyle(recorder.isPaused || recorder.isInterrupted ? Color.secondary : Color.red)
                .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording && !recorder.isPaused && !recorder.isInterrupted)

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(Duration.seconds(recorder.currentTime), format: .time(pattern: .hourMinuteSecond))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
            }

            VStack(spacing: 8) {
                Text(statusText)
                HStack(spacing: 16) {
                    Label("\(recording.kind.displayName) em \(language.displayName.lowercased())", systemImage: "globe")
                    Label(folder?.name ?? "Sem pasta", systemImage: "folder")
                }
                .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Spacer()

            Button {
                session.markMoment()
            } label: {
                VStack(spacing: 4) {
                    Label("Importante", systemImage: "star.fill")
                        .font(.title3.bold())
                    Text(markCaption)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(!recorder.isRecording || recorder.isPaused)
            .sensoryFeedback(.impact, trigger: recorder.marks.count)

            HStack(spacing: 16) {
                Button("Descartar", systemImage: "trash", role: .destructive) {
                    confirmDiscard = true
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)

                Button(
                    recorder.isPaused ? "Continuar" : "Pausar",
                    systemImage: recorder.isPaused ? "play.fill" : "pause.fill"
                ) {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)

                Button(action: finish) {
                    Label("Concluir", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .controlSize(.extraLarge)
            .disabled(!recorder.isRecording)
        }
        .padding()
        .task {
            do {
                try await session.startRecorder()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Descartar esta gravação?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) {
                recorder.discard()
                session.end()
            }
        }
        .alert(
            "Não foi possível gravar",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { session.end() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var statusText: String {
        if recorder.isPaused { "Pausado" }
        else if recorder.isInterrupted { "Interrompido por uma ligação ou outro app. Volta a gravar quando terminar." }
        else { "Gravando… pode bloquear a tela." }
    }

    private var markCaption: String {
        switch recorder.marks.count {
        case 0 where recording.kind == .meeting: "Toque quando decidirem algo ou passarem uma tarefa"
        case 0: "Toque quando o professor disser algo que cai na prova"
        case 1: "1 momento marcado"
        case let count: "\(count) momentos marcados"
        }
    }

    private func finish() {
        let marks = recorder.marks
        guard let result = recorder.stop() else { return }
        let lecture = Lecture(
            audioFileName: result.url.lastPathComponent, duration: result.duration, language: language,
            kind: recording.kind, folder: folder, highlights: marks
        )
        context.insert(lecture)
        try? context.save()
        processor.process(lecture, in: context, summarize: false)
        session.end()
    }
}
