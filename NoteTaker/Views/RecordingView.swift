import SwiftData
import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var recorder = AudioRecorder()
    @State private var errorMessage: String?
    @State private var confirmDiscard = false

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

            Text(recorder.isPaused ? "Pausado" : "Gravando… pode bloquear a tela.")
                .foregroundStyle(.secondary)

            Spacer()

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
                try await recorder.start()
            } catch {
                errorMessage = error.localizedDescription
            }
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

    private func finish() {
        guard let result = recorder.stop() else { return }
        let lecture = Lecture(audioFileName: result.url.lastPathComponent, duration: result.duration)
        context.insert(lecture)
        try? context.save()
        processor.process(lecture, in: context)
        dismiss()
    }
}
