import SwiftData
import SwiftUI

/// Lecture rows shared by the library (unfiled lectures) and folder screens.
/// Long-press a row to rename, move it to another folder or delete it.
struct LectureRows: View {
    let lectures: [Lecture]
    /// Called from the context menu; the parent list shows `renameLectureAlert`.
    let onRename: (Lecture) -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]

    var body: some View {
        ForEach(lectures) { lecture in
            NavigationLink(value: lecture) {
                LectureRow(lecture: lecture)
            }
            .contextMenu {
                Button("Renomear", systemImage: "pencil") { onRename(lecture) }
                Menu("Mover para", systemImage: "folder") {
                    Button("Sem pasta", systemImage: "tray") { move(lecture, to: nil) }
                        .disabled(lecture.folder == nil)
                    ForEach(folders) { folder in
                        Button(folder.name) { move(lecture, to: folder) }
                            .disabled(lecture.folder == folder)
                    }
                }
                Button("Apagar", systemImage: "trash", role: .destructive) { delete(lecture) }
            }
        }
        .onDelete { offsets in
            offsets.map { lectures[$0] }.forEach(delete)
        }
    }

    private func move(_ lecture: Lecture, to folder: Folder?) {
        lecture.folder = folder
        try? context.save()
    }

    private func delete(_ lecture: Lecture) {
        try? FileManager.default.removeItem(at: lecture.audioURL)
        context.delete(lecture)
        try? context.save()
    }
}

/// The "Gravar aula" button pinned to the bottom of a list. New lectures go into `folder`.
struct RecordLectureButton: View {
    let folder: Folder?
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording = true
        } label: {
            Label("Gravar aula", systemImage: "mic.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .fullScreenCover(isPresented: $isRecording) { RecordingView(folder: folder) }
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
