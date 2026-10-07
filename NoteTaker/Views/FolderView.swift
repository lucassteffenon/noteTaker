import SwiftUI

/// Lectures inside one folder. Recording from here files the new lecture in this folder.
struct FolderView: View {
    let folder: Folder
    @State private var lectureToRename: Lecture?
    @State private var isReviewing = false
    @State private var isShowingGuide = false
    @State private var isEditingSchedule = false

    private var lectures: [Lecture] {
        folder.lectures.sorted { $0.createdAt > $1.createdAt }
    }

    private var languageBinding: Binding<AppLanguage?> {
        Binding(get: { folder.language }, set: { folder.language = $0 })
    }

    var body: some View {
        Group {
            if folder.lectures.isEmpty {
                ContentUnavailableView(
                    "Nenhuma aula nesta pasta",
                    systemImage: "folder",
                    description: Text("Grave uma aula aqui, ou toque e segure uma aula existente para movê-la.")
                )
            } else {
                List {
                    LectureRows(lectures: lectures) { lectureToRename = $0 }
                }
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guia para a prova", systemImage: "book.pages") { isShowingGuide = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Revisar disciplina", systemImage: "rectangle.on.rectangle.angled") { isReviewing = true }
                    .disabled(Flashcard.cards(from: folder.lectures).isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Mais", systemImage: "ellipsis") {
                    Button("Horários das aulas", systemImage: "calendar.badge.clock") { isEditingSchedule = true }
                    Picker(selection: languageBinding) {
                        Text("Igual aos Ajustes (\(AppLanguage.lecture.displayName))")
                            .tag(AppLanguage?.none)
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(Optional(language))
                        }
                    } label: {
                        Label("Idioma das aulas", systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .sheet(isPresented: $isReviewing) {
            FlashcardsView(title: folder.name, cards: Flashcard.cards(from: lectures), showsLecture: true)
        }
        .sheet(isPresented: $isShowingGuide) { StudyGuideView(folder: folder) }
        .sheet(isPresented: $isEditingSchedule) { ScheduleEditorView(folder: folder) }
        .safeAreaInset(edge: .bottom) { RecordLectureButton(folder: folder) }
        .renameLectureAlert($lectureToRename)
    }
}
