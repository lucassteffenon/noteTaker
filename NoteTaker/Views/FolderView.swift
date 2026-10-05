import SwiftUI

/// Lectures inside one folder. Recording from here files the new lecture in this folder.
struct FolderView: View {
    let folder: Folder

    private var lectures: [Lecture] {
        folder.lectures.sorted { $0.createdAt > $1.createdAt }
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
                    LectureRows(lectures: lectures)
                }
            }
        }
        .navigationTitle(folder.name)
        .safeAreaInset(edge: .bottom) { RecordLectureButton(folder: folder) }
    }
}
