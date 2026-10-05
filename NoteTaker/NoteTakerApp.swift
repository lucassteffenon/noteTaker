import SwiftData
import SwiftUI

@main
struct NoteTakerApp: App {
    @State private var processor = LectureProcessor()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(processor)
        }
        .modelContainer(for: [Lecture.self, Folder.self])
    }
}
