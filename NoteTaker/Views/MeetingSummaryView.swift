import SwiftData
import SwiftUI

/// The minutes of a meeting: summary, decisions, action items (checkable, and sent to
/// Lembretes on request), open questions and the subjects discussed.
struct MeetingSummaryView: View {
    let lecture: Lecture
    let minutes: MeetingSummary
    /// nil when the recording can't be played (e.g. the audio file is missing).
    let player: LecturePlayer?
    @Environment(\.modelContext) private var context
    @State private var isAddingReminders = false
    @State private var reminderError: String?

    private var pendingReminders: [Int] {
        minutes.actionItems.indices.filter {
            minutes.actionItems[$0].reminderID == nil && !minutes.actionItems[$0].done
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SummarySection(title: "Resumo", systemImage: "doc.text") {
                Text(minutes.overview)
                    .textSelection(.enabled)
            }

            if !minutes.decisions.isEmpty {
                SummarySection(title: "Decisões", systemImage: "checkmark.seal") {
                    ForEach(minutes.decisions, id: \.self) { decision in
                        row(symbol: "•") {
                            Text(decision.text)
                            PlayFromButton(time: decision.startSeconds.playbackTime, player: player)
                        }
                    }
                }
            }

            SummarySection(title: "Tarefas", systemImage: "checklist") {
                if minutes.actionItems.isEmpty {
                    Text("Nenhuma tarefa foi combinada.")
                        .foregroundStyle(.secondary)
                }
                ForEach(minutes.actionItems.indices, id: \.self) { index in
                    actionItem(at: index)
                }
                if !pendingReminders.isEmpty {
                    let count = pendingReminders.count
                    Button(
                        count == 1 ? "Adicionar aos Lembretes" : "Adicionar as \(count) aos Lembretes",
                        systemImage: "bell.badge"
                    ) {
                        addReminders(pendingReminders)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAddingReminders)
                }
                if let reminderError {
                    Label(reminderError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !minutes.openQuestions.isEmpty {
                SummarySection(title: "Em aberto", systemImage: "questionmark.circle") {
                    ForEach(minutes.openQuestions, id: \.self) { question in
                        row(symbol: "•") { Text(question) }
                    }
                }
            }

            if !minutes.keyPoints.isEmpty {
                SummarySection(title: "Assuntos discutidos", systemImage: "text.bubble") {
                    ForEach(minutes.keyPoints, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if point.important {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .accessibilityLabel("Marcado como importante")
                            } else {
                                Text("•")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(point.text)
                                PlayFromButton(time: point.startSeconds.playbackTime, player: player)
                            }
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func row(symbol: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(symbol)
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }

    private func actionItem(at index: Int) -> some View {
        let item = minutes.actionItems[index]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                update { $0.actionItems[index].done.toggle() }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? Color.green : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Marcar como não feita" : "Marcar como feita")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.task)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let details = item.details {
                        Text(details)
                    }
                    if item.reminderID != nil {
                        Label("Nos Lembretes", systemImage: "bell.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                PlayFromButton(time: item.startSeconds.playbackTime, player: player)
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if item.reminderID == nil {
                Button("Adicionar aos Lembretes", systemImage: "bell.badge") { addReminders([index]) }
            }
        }
    }

    private func update(_ change: (inout MeetingSummary) -> Void) {
        guard var current = lecture.meeting else { return }
        change(&current)
        lecture.meeting = current
        try? context.save()
    }

    private func addReminders(_ indices: [Int]) {
        isAddingReminders = true
        reminderError = nil
        Task {
            defer { isAddingReminders = false }
            do {
                let ids = try await RemindersExport.add(indices.map { minutes.actionItems[$0] }, from: lecture)
                update { minutes in
                    for (index, id) in zip(indices, ids) { minutes.actionItems[index].reminderID = id }
                }
            } catch {
                reminderError = error.localizedDescription
            }
        }
    }
}
