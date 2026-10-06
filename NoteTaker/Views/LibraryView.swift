import SwiftData
import SwiftUI

/// Home screen: folders first, then lectures that aren't in any folder. Searching replaces the
/// list with matches from every lecture. Also opens the recorder when `RecordLectureIntent` runs.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(
        filter: #Predicate<Lecture> { $0.folder == nil },
        sort: \Lecture.createdAt, order: .reverse
    ) private var unfiledLectures: [Lecture]

    @State private var showSettings = false
    @State private var isNamingFolder = false
    @State private var folderName = ""
    /// nil while creating a new folder; set while renaming.
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    @State private var lectureToRename: Lecture?
    @State private var searchText = ""
    /// Recording started from Siri, the Action button or the control, outside any folder.
    @State private var isRecordingFromShortcut = false
    private let commands = RecordingCommands.shared

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    LectureSearchResults(query: searchText.trimmingCharacters(in: .whitespaces))
                } else if folders.isEmpty && unfiledLectures.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma aula gravada",
                        systemImage: "mic",
                        description: Text("Crie uma pasta para cada disciplina ou toque em Gravar aula.")
                    )
                } else {
                    List {
                        if !folders.isEmpty {
                            Section("Pastas") {
                                ForEach(folders) { folder in
                                    folderRow(folder)
                                }
                            }
                        }
                        if !unfiledLectures.isEmpty {
                            Section {
                                LectureRows(lectures: unfiledLectures) { lectureToRename = $0 }
                            } header: {
                                if !folders.isEmpty { Text("Sem pasta") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Aulas")
            .searchable(text: $searchText, prompt: "Buscar nas aulas")
            .navigationDestination(for: Folder.self) { FolderView(folder: $0) }
            .navigationDestination(for: Lecture.self) { LectureDetailView(lecture: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nova pasta", systemImage: "folder.badge.plus") { startNaming(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajustes", systemImage: "gearshape") { showSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if searchText.isEmpty { RecordLectureButton(folder: nil) }
            }
            .fullScreenCover(isPresented: $isRecordingFromShortcut) { RecordingView(folder: nil) }
            .onChange(of: commands.startRequested, initial: true) { _, requested in
                guard requested else { return }
                commands.startRequested = false
                if !commands.isRecording { isRecordingFromShortcut = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .renameLectureAlert($lectureToRename)
            .alert(folderToRename == nil ? "Nova pasta" : "Renomear pasta", isPresented: $isNamingFolder) {
                TextField("Nome da disciplina", text: $folderName)
                Button(folderToRename == nil ? "Criar" : "Salvar", action: saveFolderName)
                    .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog(
                "Apagar a pasta “\(folderToDelete?.name ?? "")”?",
                isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Apagar pasta", role: .destructive) {
                    if let folderToDelete { context.delete(folderToDelete) }
                    try? context.save()
                }
            } message: {
                Text("As aulas desta pasta não serão apagadas. Elas vão para Sem pasta.")
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        NavigationLink(value: folder) {
            HStack {
                Label(folder.name, systemImage: "folder.fill")
                Spacer()
                Text("\(folder.lectures.count)")
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Renomear", systemImage: "pencil") { startNaming(folder) }
            Button("Apagar", systemImage: "trash", role: .destructive) { folderToDelete = folder }
        }
        .swipeActions {
            Button("Apagar", systemImage: "trash", role: .destructive) { folderToDelete = folder }
        }
    }

    private func startNaming(_ folder: Folder?) {
        folderToRename = folder
        folderName = folder?.name ?? ""
        isNamingFolder = true
    }

    private func saveFolderName() {
        let name = folderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let folderToRename {
            folderToRename.name = name
        } else {
            context.insert(Folder(name: name))
        }
        try? context.save()
    }
}
