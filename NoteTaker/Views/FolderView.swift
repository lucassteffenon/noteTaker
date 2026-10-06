import SwiftUI

/// Lectures inside one folder. Recording from here files the new lecture in this folder.
struct FolderView: View {
    let folder: Folder
    @State private var lectureToRename: Lecture?
    @State private var isReviewing = false

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
                Menu("Idioma das aulas", systemImage: "globe") {
                    Picker("Idioma das aulas", selection: languageBinding) {
                        Text("Igual aos Ajustes (\(AppLanguage.lecture.displayName))")
                            .tag(AppLanguage?.none)
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(Optional(language))
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Revisar disciplina", systemImage: "rectangle.on.rectangle.angled") { isReviewing = true }
                    .disabled(Flashcard.cards(from: folder.lectures).isEmpty)
            }
        }
        .sheet(isPresented: $isReviewing) {
            FlashcardsView(title: folder.name, cards: Flashcard.cards(from: lectures), showsLecture: true)
        }
        .safeAreaInset(edge: .bottom) { RecordLectureButton(folder: folder) }
        .renameLectureAlert($lectureToRename)
    }
}
