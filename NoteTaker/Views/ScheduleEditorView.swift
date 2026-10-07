import SwiftData
import SwiftUI

/// The weekly class times of a folder. During one of them (or up to 15 minutes before),
/// "Gravar aula" on the home screen, Siri and the Control Center control record into this folder.
struct ScheduleEditorView: View {
    let folder: Folder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var folders: [Folder]
    @State private var weekday = Calendar.current.component(.weekday, from: .now)
    @State private var start = Self.time(hour: 8)
    @State private var end = Self.time(hour: 9, minute: 40)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if folder.schedule.isEmpty {
                        Text("Nenhum horário cadastrado.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedSchedule) { slot in
                        Text(slot.label)
                    }
                    .onDelete { offsets in
                        let removed = Set(offsets.map { sortedSchedule[$0].id })
                        folder.schedule.removeAll { removed.contains($0.id) }
                        try? context.save()
                    }
                } footer: {
                    Text("No horário da aula, ou até \(ClassTime.earlyMargin) minutos antes, o botão Gravar aula da tela inicial, a Siri e a Central de Controle já gravam nesta pasta.")
                }

                Section("Adicionar horário") {
                    Picker("Dia", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(ClassTime.dayName(day)).tag(day)
                        }
                    }
                    DatePicker("Início", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Fim", selection: $end, displayedComponents: .hourAndMinute)
                    if let conflict {
                        Label("Conflita com \(conflict.name).", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Button("Adicionar", systemImage: "plus", action: add)
                        .disabled(minutes(end) <= minutes(start))
                }
            }
            .navigationTitle("Horários de \(folder.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private var sortedSchedule: [ClassTime] {
        folder.schedule.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }
    }

    private var newSlot: ClassTime {
        ClassTime(weekday: weekday, start: minutes(start), end: minutes(end))
    }

    /// Another folder whose class overlaps the one being added; the first match would win.
    private var conflict: Folder? {
        let slot = newSlot
        return folders.first { other in
            other.id != folder.id && other.schedule.contains {
                $0.weekday == slot.weekday && $0.start < slot.end && slot.start < $0.end
            }
        }
    }

    private func add() {
        folder.schedule.append(newSlot)
        try? context.save()
    }

    private func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func time(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
