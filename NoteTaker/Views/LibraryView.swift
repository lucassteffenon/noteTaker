import SwiftData
import SwiftUI

/// Home screen: folders first, then lectures that aren't in any folder. Searching replaces the
/// list with matches from every lecture. Also opens the recorder when `RecordLectureIntent` runs.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LectureProcessor.self) private var processor
    @State private var session = RecordingSession.shared
    /// Every folder, including subfolders: the class schedule can point at any of them.
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(
        filter: #Predicate<Lecture> { $0.folder == nil },
        sort: \Lecture.createdAt, order: .reverse
    ) private var unfiledLectures: [Lecture]

    @State private var showSettings = false
    @State private var naming: FolderNaming?
    @State private var lectureToRename: Lecture?
    @State private var searchText = ""
    private let commands = RecordingCommands.shared

    private var topFolders: [Folder] {
        folders.filter { $0.parent == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    LectureSearchResults(query: searchText.trimmingCharacters(in: .whitespaces))
                } else if topFolders.isEmpty && unfiledLectures.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma gravação",
                        systemImage: "mic",
                        description: Text("Crie uma pasta para cada disciplina ou projeto, ou toque em Gravar.")
                    )
                } else {
                    List {
                        if !topFolders.isEmpty {
                            Section("Pastas") {
                                FolderRows(folders: topFolders)
                            }
                        }
                        if !unfiledLectures.isEmpty {
                            Section {
                                LectureRows(lectures: unfiledLectures) { lectureToRename = $0 }
                            } header: {
                                if !topFolders.isEmpty { Text("Sem pasta") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Aulas")
            .searchable(text: $searchText, prompt: "Buscar nas gravações")
            .navigationDestination(for: Folder.self) { FolderView(folder: $0) }
            .navigationDestination(for: Lecture.self) { LectureDetailView(lecture: $0) }
            .navigationDestination(for: FolderOverviewRoute.self) { FolderOverviewView(folder: $0.folder) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nova pasta", systemImage: "folder.badge.plus") { naming = .create(parent: nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajustes", systemImage: "gearshape") { showSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if searchText.isEmpty {
                    // Re-checked every minute so the button follows the class schedule.
                    TimelineView(.everyMinute) { timeline in
                        RecordLectureButton(
                            folder: Folder.inClass(at: timeline.date, among: folders), showsFolderName: true
                        )
                    }
                }
            }
            .onChange(of: commands.startRequested, initial: true) { _, requested in
                // Siri, the Action button or the control: filed by the class schedule.
                guard requested else { return }
                commands.startRequested = false
                session.begin(folder: Folder.inClass(at: .now, among: folders))
            }
            .task { await session.recoverInterruptedRecordings(in: context, processor: processor) }
            .alert(
                "Gravação recuperada",
                isPresented: Binding(get: { session.recoveredCount > 0 }, set: { if !$0 { session.recoveredCount = 0 } })
            ) {
                Button("OK") {}
            } message: {
                Text(session.recoveredCount == 1
                    ? "Uma gravação foi interrompida antes de você tocar em Concluir (o app foi fechado). O áudio foi salvo e está sendo transcrito."
                    : "\(session.recoveredCount) gravações foram interrompidas antes de você tocar em Concluir (o app foi fechado). Os áudios foram salvos e estão sendo transcritos.")
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .renameLectureAlert($lectureToRename)
            .folderNamingAlert($naming)
        }
        // Presented from the root so it covers any screen, and comes back if the system
        // rebuilds the UI while a recording is running in the background.
        .fullScreenCover(item: $session.current) { RecordingView(recording: $0) }
    }
}
