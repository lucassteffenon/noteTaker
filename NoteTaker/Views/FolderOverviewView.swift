import SwiftData
import SwiftUI

/// Navigation value for a folder's overview; `Folder` itself already opens `FolderView`.
struct FolderOverviewRoute: Hashable {
    let folder: Folder
}

/// "Panorama" of a folder and its subfolders, built on the device from the summaries and minutes
/// already saved (no AI call): pending tasks, decisions and open questions from meetings, exams
/// and deadlines from classes, the moments marked with ⭐ and a timeline of every recording.
struct FolderOverviewView: View {
    let folder: Folder
    @Environment(\.modelContext) private var context
    /// Tasks ticked on this screen stay listed (struck through) so a mistaken tap can be undone.
    @State private var tickedHere: Set<String> = []

    private var recordings: [Lecture] {
        folder.allLectures.sorted { $0.createdAt > $1.createdAt }
    }

    private var meetings: [Lecture] {
        recordings.filter { $0.kind == .meeting && $0.meeting != nil }
    }

    private var classes: [Lecture] {
        recordings.filter { $0.kind == .lecture && $0.summary != nil }
    }

    var body: some View {
        List {
            Section {
                stats
            }
            if !meetings.isEmpty {
                tasksSection
                itemsSection("Decisões", systemImage: "checkmark.seal", items: meetings.flatMap { lecture in
                    lecture.meeting!.decisions.map { (lecture, $0.text) }
                })
                itemsSection("Em aberto", systemImage: "questionmark.circle", items: meetings.flatMap { lecture in
                    lecture.meeting!.openQuestions.map { (lecture, $0) }
                })
            }
            if !classes.isEmpty {
                itemsSection("Provas e prazos", systemImage: "calendar", items: classes.flatMap { lecture in
                    lecture.summary!.assignments.map { (lecture, $0) }
                })
            }
            itemsSection("Momentos marcados", systemImage: "star.fill", items: recordings.flatMap { lecture in
                importantPoints(of: lecture).map { (lecture, $0) }
            })
            timeline
        }
        .navigationTitle("Panorama")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Numbers

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(folder.path)
                .font(.headline)
            Text(countText)
            if let period = periodText {
                Text(period).foregroundStyle(.secondary)
            }
            let missing = recordings.filter { !$0.hasSummary }.count
            if missing > 0 {
                Label(
                    missing == 1 ? "1 gravação ainda sem resumo ou ata fica de fora." :
                        "\(missing) gravações ainda sem resumo ou ata ficam de fora.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var countText: String {
        let meetings = recordings.filter { $0.kind == .meeting }.count
        let classes = recordings.count - meetings
        let parts = [
            classes == 0 ? nil : classes == 1 ? "1 aula" : "\(classes) aulas",
            meetings == 0 ? nil : meetings == 1 ? "1 reunião" : "\(meetings) reuniões",
        ].compactMap(\.self)
        let total = Duration.seconds(recordings.reduce(0) { $0 + $1.duration })
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return parts.formatted(.list(type: .and)) + " · \(total) gravados"
    }

    /// "De 3 de set. a 8 de out." between the first and the last recording.
    private var periodText: String? {
        guard let first = recordings.last?.createdAt, let last = recordings.first?.createdAt,
              !Calendar.current.isDate(first, inSameDayAs: last) else { return nil }
        let style = Date.FormatStyle.dateTime.day().month()
        return "De \(first.formatted(style)) a \(last.formatted(style))"
    }

    // MARK: - Tasks

    private struct PendingTask: Identifiable {
        let lecture: Lecture
        let index: Int
        let item: MeetingSummary.ActionItem
        var id: String { "\(lecture.id.uuidString)-\(index)" }
    }

    /// Open tasks from every meeting: overdue and dated ones first, by deadline, then the rest,
    /// newest meeting first.
    private var tasks: [PendingTask] {
        let all = meetings.flatMap { lecture in
            lecture.meeting!.actionItems.enumerated().map { PendingTask(lecture: lecture, index: $0, item: $1) }
        }
        return all
            .filter { !$0.item.done || tickedHere.contains($0.id) }
            .sorted { lhs, rhs in
                switch (lhs.item.due, rhs.item.due) {
                case let (left?, right?): left < right
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.lecture.createdAt > rhs.lecture.createdAt
                }
            }
    }

    private var tasksSection: some View {
        let tasks = tasks
        let doneCount = meetings.reduce(0) { $0 + $1.meeting!.actionItems.filter(\.done).count }
        return Section {
            if tasks.isEmpty {
                Text("Nenhuma tarefa pendente.")
                    .foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                NavigationLink(value: task.lecture) {
                    taskRow(task)
                }
            }
        } header: {
            Label("Tarefas pendentes", systemImage: "checklist")
        } footer: {
            if doneCount > 0 {
                Text(doneCount == 1 ? "1 tarefa já foi feita." : "\(doneCount) tarefas já foram feitas.")
            }
        }
    }

    private func taskRow(_ task: PendingTask) -> some View {
        let item = task.item
        let overdue = !item.done && (item.due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? Color.green : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.done ? "Marcar como não feita" : "Marcar como feita")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.task)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
                if let details = item.details {
                    Text(overdue ? "\(details) · atrasada" : details)
                        .font(.caption)
                        .foregroundStyle(overdue ? .red : .secondary)
                }
                source(task.lecture)
            }
        }
    }

    private func toggle(_ task: PendingTask) {
        tickedHere.insert(task.id)
        task.lecture.updateMeeting { $0.actionItems[task.index].done.toggle() }
        try? context.save()
    }

    // MARK: - Lists

    private func importantPoints(of lecture: Lecture) -> [String] {
        let points = lecture.kind == .meeting ? lecture.meeting?.keyPoints : lecture.summary?.keyPoints
        return (points ?? []).filter(\.important).map(\.text)
    }

    /// One row per item, each saying which recording it came from; hidden when there's nothing.
    @ViewBuilder
    private func itemsSection(_ title: String, systemImage: String, items: [(Lecture, String)]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                    NavigationLink(value: entry.0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.1)
                            source(entry.0)
                        }
                    }
                }
            } header: {
                Label(title, systemImage: systemImage)
            }
        }
    }

    private var timeline: some View {
        Section {
            ForEach(recordings) { lecture in
                NavigationLink(value: lecture) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(lecture.title.isEmpty ? lecture.kind.displayName : lecture.title,
                              systemImage: lecture.kind.systemImage)
                            .font(.headline)
                        Text(lecture.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let overview = overview(of: lecture) {
                            Text(overview)
                                .font(.subheadline)
                                .lineLimit(3)
                        } else {
                            Text(lecture.kind == .meeting ? "Sem ata" : "Sem resumo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Label("Linha do tempo", systemImage: "clock")
        }
    }

    private func overview(of lecture: Lecture) -> String? {
        lecture.kind == .meeting ? lecture.meeting?.overview : lecture.summary?.overview
    }

    /// "Reunião de 2 de out. · Projeto X": where an item came from, with the subfolder when not here.
    private func source(_ lecture: Lecture) -> some View {
        let date = lecture.createdAt.formatted(.dateTime.day().month())
        let title = lecture.title.isEmpty ? "\(lecture.kind.displayName) de \(date)" : "\(lecture.title) · \(date)"
        let place = lecture.folder.flatMap { $0 == folder ? nil : $0.name }
        return Text([title, place].compactMap(\.self).joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
