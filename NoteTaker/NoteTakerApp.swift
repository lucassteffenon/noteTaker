import SwiftData
import SwiftUI

@main
struct NoteTakerApp: App {
    @State private var processor = LectureProcessor()

    var body: some Scene {
        WindowGroup {
            LectureListView()
                .environment(processor)
        }
        .modelContainer(for: Lecture.self)
    }
}
