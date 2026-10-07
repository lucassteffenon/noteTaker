import SwiftData
import SwiftUI

/// Questions about one lecture, answered by the AI from the transcript. The conversation is
/// saved with the lecture; each answer can jump to where the professor explains it.
struct LectureChatView: View {
    let lecture: Lecture
    /// Plays the recording from a second, in the lecture screen behind this sheet.
    let play: (TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var question = ""
    @State private var isAsking = false
    @State private var errorMessage: String?
    @State private var confirmClear = false
    @FocusState private var isFieldFocused: Bool

    private static let suggestions = [
        "Do que tratou esta aula?",
        "O que o professor disse que cai na prova?",
        "Explique de novo a parte mais difícil.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if lecture.chat.isEmpty {
                        intro
                    }
                    ForEach(lecture.chat) { message in
                        bubble(message)
                    }
                    if isAsking {
                        ProgressView()
                            .padding(.vertical, 8)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Perguntar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Limpar conversa", systemImage: "trash") { confirmClear = true }
                        .disabled(lecture.chat.isEmpty || isAsking)
                }
            }
            .confirmationDialog("Apagar esta conversa?", isPresented: $confirmClear) {
                Button("Apagar conversa", role: .destructive) {
                    lecture.chat = []
                    try? context.save()
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pergunte qualquer coisa sobre esta aula. O \(SummaryProvider.selected.displayName) responde com base na transcrição e mostra onde o professor falou disso.")
                .foregroundStyle(.secondary)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button(suggestion) { ask(suggestion) }
                    .buttonStyle(.bordered)
            }
            Text("Cada pergunta envia a transcrição da aula, então tem um custo parecido com o de um resumo pequeno.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 8)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return VStack(alignment: .leading, spacing: 8) {
            Text(message.text)
                .textSelection(.enabled)
            if let start = message.startSeconds {
                Button {
                    play(start)
                    dismiss()
                } label: {
                    Label("Ouvir em \(start.clockText)", systemImage: "play.fill")
                        .font(.caption.monospacedDigit())
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            isUser ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.background.secondary),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 40)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Sua pergunta", text: $question, axis: .vertical)
                .lineLimit(1...5)
                .focused($isFieldFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
            Button("Enviar", systemImage: "arrow.up") { ask(question) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(trimmed(question).isEmpty || isAsking)
        }
        .padding()
        .background(.bar)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ask(_ text: String) {
        let text = trimmed(text)
        guard !text.isEmpty, !isAsking else { return }
        let history = lecture.chat
        lecture.chat = history + [ChatMessage(role: .user, text: text)]
        question = ""
        errorMessage = nil
        isAsking = true
        Task {
            defer { isAsking = false }
            do {
                let request = LectureQuestionPrompt.request(lecture: lecture, history: history, question: text)
                let answer = try await SummaryProvider.selectedClient().respond(to: request, as: LectureAnswer.self)
                lecture.chat.append(ChatMessage(
                    role: .assistant, text: answer.answer, startSeconds: Optional(answer.startSeconds).playbackTime
                ))
            } catch {
                // Drop the unanswered question so the conversation sent next time stays well-formed.
                lecture.chat = history
                question = text
                errorMessage = error.localizedDescription
            }
            try? context.save()
        }
    }
}
