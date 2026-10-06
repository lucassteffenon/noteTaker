import SwiftUI

/// A review card built from a summary: a concept (term → explanation) or a review question
/// (question → answer).
struct Flashcard: Identifiable, Hashable {
    let id = UUID()
    let kind: String
    let front: String
    /// nil for review questions saved before the AI was asked for answers.
    let back: String?
    let lectureTitle: String

    /// Questions first, then concepts, from every lecture that has a summary.
    static func cards(from lectures: [Lecture]) -> [Flashcard] {
        lectures.flatMap { lecture -> [Flashcard] in
            guard let summary = lecture.summary else { return [] }
            let title = lecture.displayTitle
            return summary.reviewQuestions.map {
                Flashcard(kind: "Pergunta", front: $0.question, back: $0.answer, lectureTitle: title)
            } + summary.concepts.map {
                Flashcard(kind: "Conceito", front: $0.term, back: $0.explanation, lectureTitle: title)
            }
        }
    }
}

/// Flashcard review: tap the card to see the answer, then "Sei" removes it from the round and
/// "Não sei" sends it to the end of the pile, until every card is known.
struct FlashcardsView: View {
    let title: String
    let cards: [Flashcard]
    /// Shows which lecture each card came from, for reviews across a whole folder.
    var showsLecture = false
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Flashcard] = []
    @State private var missed: Set<Flashcard.ID> = []
    @State private var isShowingAnswer = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let card = queue.first {
                    ProgressView(value: Double(cards.count - queue.count), total: Double(cards.count)) {
                        Text("\(cards.count - queue.count) de \(cards.count) cartões")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    cardView(card)
                    controls
                } else {
                    finished
                }
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Embaralhar", systemImage: "shuffle", action: restart)
                        .disabled(queue.isEmpty)
                }
            }
            .onAppear { if queue.isEmpty { restart() } }
            .sensoryFeedback(.selection, trigger: queue.count)
        }
    }

    private func cardView(_ card: Flashcard) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4)) { isShowingAnswer.toggle() }
        } label: {
            VStack(spacing: 16) {
                Text(isShowingAnswer ? "Resposta" : card.kind)
                    .font(.caption.bold())
                    .textCase(.uppercase)
                    .foregroundStyle(isShowingAnswer ? Color.green : Color.accentColor)
                ScrollView {
                    Text(isShowingAnswer ? card.back ?? "Sem resposta salva. Gere o resumo de novo para ter respostas." : card.front)
                        .font(isShowingAnswer ? .body : .title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center, for: .alignment)
                if showsLecture {
                    Text(card.lectureTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isShowingAnswer {
                    Text("Toque para ver a resposta")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            // Counter-rotates the text against the card flip below, so the back isn't mirrored.
            .rotation3DEffect(.degrees(isShowingAnswer ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .rotation3DEffect(.degrees(isShowingAnswer ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .id(card.id)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                answer(known: false)
            } label: {
                Label("Não sei", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .tint(.orange)

            Button {
                answer(known: true)
            } label: {
                Label("Sei", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var finished: some View {
        let firstTry = cards.count - missed.count
        return ContentUnavailableView {
            Label {
                Text("Revisão concluída")
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        } description: {
            Text("Você sabia \(firstTry) de \(cards.count) na primeira tentativa.")
        } actions: {
            Button("Revisar de novo", systemImage: "arrow.clockwise", action: restart)
                .buttonStyle(.borderedProminent)
            Button("Concluir") { dismiss() }
        }
    }

    private func answer(known: Bool) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        if !known {
            missed.insert(card.id)
            queue.append(card)
        }
        isShowingAnswer = false
    }

    private func restart() {
        queue = cards.shuffled()
        missed = []
        isShowingAnswer = false
    }
}
