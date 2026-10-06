import AppIntents

/// Makes "Gravar aula" available to Siri, Spotlight, the Shortcuts app and the Action button
/// without any setup.
struct LectureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordLectureIntent(),
            phrases: [
                "Gravar aula no \(.applicationName)",
                "Gravar uma aula no \(.applicationName)",
                "Começar a gravar no \(.applicationName)",
            ],
            shortTitle: "Gravar aula",
            systemImageName: "mic.fill"
        )
    }
}
