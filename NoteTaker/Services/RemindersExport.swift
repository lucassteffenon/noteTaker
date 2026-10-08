import EventKit
import Foundation

/// Adds a meeting's action items to the Reminders app, in the default list.
@MainActor
enum RemindersExport {
    enum ExportError: LocalizedError {
        case accessDenied
        case noDefaultList

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Sem acesso aos Lembretes. Permita em Ajustes > Apps > Anota > Lembretes."
            case .noDefaultList:
                "Não há uma lista padrão no app Lembretes."
            }
        }
    }

    private static let store = EKEventStore()

    /// Creates one reminder per item and returns their identifiers, in the same order.
    static func add(_ items: [MeetingSummary.ActionItem], from lecture: Lecture) async throws -> [String] {
        guard try await store.requestFullAccessToReminders() else { throw ExportError.accessDenied }
        guard let list = store.defaultCalendarForNewReminders() else { throw ExportError.noDefaultList }
        let source = "\(lecture.displayTitle), \(lecture.createdAt.formatted(date: .abbreviated, time: .omitted))"
        var ids: [String] = []
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = item.task
            reminder.notes = [item.owner.isEmpty ? nil : "Responsável: \(item.owner)", "Reunião: \(source)"]
                .compactMap(\.self).joined(separator: "\n")
            if let due = item.due {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
            }
            try store.save(reminder, commit: false)
            ids.append(reminder.calendarItemIdentifier)
        }
        try store.commit()
        return ids
    }
}
