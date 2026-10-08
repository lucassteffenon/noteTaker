import SwiftUI

/// Subfolders, then lectures, of one folder. Recording from here files the new lecture in this
/// folder. Review and the study guide cover the subfolders too.
struct FolderView: View {
    let folder: Folder
    @State private var lectureToRename: Lecture?
    @State private var isReviewing = false
    @State private var isShowingGuide = false
    @State private var isEditingSchedule = false
    @State private var naming: FolderNaming?

    private var lectures: [Lecture] {
        folder.lectures.sorted { $0.createdAt > $1.createdAt }
    }

    private var kind: RecordingKind { folder.recordingKind }

    private var kindBinding: Binding<RecordingKind?> {
        Binding(get: { folder.kind }, set: { folder.kind = $0 })
    }

    private var languageBinding: Binding<AppLanguage?> {
        Binding(get: { folder.language }, set: { folder.language = $0 })
    }

    /// What "Igual a…" means for this folder's kind and language: the parent's, or Ajustes.
    private var inheritedSource: String {
        folder.parent.map { "Igual a \($0.name)" } ?? "Igual aos Ajustes"
    }

    var body: some View {
        Group {
            if folder.lectures.isEmpty && folder.subfolders.isEmpty {
                ContentUnavailableView(
                    "Nenhuma gravação nesta pasta",
                    systemImage: "folder",
                    description: Text("Grave uma \(kind.noun) aqui, ou toque e segure uma gravação existente para movê-la.")
                )
            } else {
                List {
                    if !folder.subfolders.isEmpty {
                        Section("Pastas") {
                            FolderRows(folders: folder.sortedSubfolders)
                        }
                    }
                    if !lectures.isEmpty {
                        Section {
                            LectureRows(lectures: lectures) { lectureToRename = $0 }
                        } header: {
                            if !folder.subfolders.isEmpty { Text("Gravações") }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            if kind == .lecture {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guia para a prova", systemImage: "book.pages") { isShowingGuide = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Revisar disciplina", systemImage: "rectangle.on.rectangle.angled") { isReviewing = true }
                        .disabled(Flashcard.cards(from: folder.allLectures).isEmpty)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Mais", systemImage: "ellipsis") {
                    Button("Nova subpasta", systemImage: "folder.badge.plus") { naming = .create(parent: folder) }
                    Picker(selection: kindBinding) {
                        Text("\(inheritedSource) (\((folder.parent?.recordingKind ?? .standard).displayName))")
                            .tag(RecordingKind?.none)
                        ForEach(RecordingKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(Optional(kind))
                        }
                    } label: {
                        Label("Tipo das gravações", systemImage: kind.systemImage)
                    }
                    .pickerStyle(.menu)
                    Button("Horários", systemImage: "calendar.badge.clock") { isEditingSchedule = true }
                    Picker(selection: languageBinding) {
                        Text("\(inheritedSource) (\((folder.parent?.recordingLanguage ?? .lecture).displayName))")
                            .tag(AppLanguage?.none)
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(Optional(language))
                        }
                    } label: {
                        Label("Idioma falado", systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .sheet(isPresented: $isReviewing) {
            FlashcardsView(
                title: folder.name,
                cards: Flashcard.cards(from: folder.allLectures.sorted { $0.createdAt > $1.createdAt }),
                showsLecture: true
            )
        }
        .sheet(isPresented: $isShowingGuide) { StudyGuideView(folder: folder) }
        .sheet(isPresented: $isEditingSchedule) { ScheduleEditorView(folder: folder) }
        .safeAreaInset(edge: .bottom) { RecordLectureButton(folder: folder) }
        .renameLectureAlert($lectureToRename)
        .folderNamingAlert($naming)
    }
}
