import SwiftData
import SwiftUI

struct LectureListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Lecture.createdAt, order: .reverse) private var lectures: [Lecture]
    @State private var isRecording = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if lectures.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma aula gravada",
                        systemImage: "mic",
                        description: Text("Toque em Gravar aula para começar.")
                    )
                } else {
                    List {
                        ForEach(lectures) { lecture in
                            NavigationLink(value: lecture) {
                                LectureRow(lecture: lecture)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Aulas")
            .navigationDestination(for: Lecture.self) { LectureDetailView(lecture: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajustes", systemImage: "gearshape") { showSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isRecording = true
                } label: {
                    Label("Gravar aula", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .fullScreenCover(isPresented: $isRecording) { RecordingView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let lecture = lectures[index]
            try? FileManager.default.removeItem(at: lecture.audioURL)
            context.delete(lecture)
        }
        try? context.save()
    }
}

private struct LectureRow: View {
    let lecture: Lecture

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lecture.displayTitle)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(lecture.createdAt, format: .dateTime.day().month().hour().minute())
                Text("·")
                Text(Duration.seconds(lecture.duration), format: .time(pattern: .hourMinuteSecond))
                Spacer()
                LectureStatusBadge(status: lecture.status)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct LectureStatusBadge: View {
    let status: Lecture.Status

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch status {
        case .recorded: ("Gravada", "waveform", .secondary)
        case .transcribing: ("Transcrevendo", "text.bubble", .secondary)
        case .summarizing: ("Resumindo", "sparkles", .secondary)
        case .done: ("Pronta", "checkmark.circle.fill", .green)
        case .failed: ("Erro", "exclamationmark.triangle.fill", .orange)
        }
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .foregroundStyle(color)
    }
}
