import SwiftData
import SwiftUI

struct RecordingView: View {
    /// Folder the new lecture is filed in; nil for "Sem pasta".
    let folder: Folder?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var recorder = AudioRecorder()
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    /// Read once when the screen opens, so the whole recording uses one language.
    private let language = AppLanguage.lecture

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 72))
                .foregroundStyle(recorder.isPaused ? Color.secondary : Color.red)
                .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording && !recorder.isPaused)

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(Duration.seconds(recorder.currentTime), format: .time(pattern: .hourMinuteSecond))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
            }

            VStack(spacing: 8) {
                Text(recorder.isPaused ? "Pausado" : "Gravando… pode bloquear a tela.")
                HStack(spacing: 16) {
                    Label("Aula em \(language.displayName.lowercased())", systemImage: "globe")
                    Label(folder?.name ?? "Sem pasta", systemImage: "folder")
                }
                .font(.footnote)
            }
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                recorder.markMoment()
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
            RecordingCommands.shared.isRecording = true
            RecordingCommands.shared.markMoment = { [recorder] in recorder.markMoment() }
            do {
                try await recorder.start(folderName: folder?.name ?? "Sem pasta")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            RecordingCommands.shared.isRecording = false
            RecordingCommands.shared.markMoment = nil
        }
        .confirmationDialog("Descartar esta gravação?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) {
                recorder.discard()
                dismiss()
            }
        }
        .alert(
            "Não foi possível gravar",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var markCaption: String {
        switch recorder.marks.count {
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
            folder: folder, highlights: marks
        )
        context.insert(lecture)
        try? context.save()
        processor.process(lecture, in: context, summarize: false)
        dismiss()
    }
}
