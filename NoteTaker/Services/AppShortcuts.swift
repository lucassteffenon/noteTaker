import AppIntents

/// Makes "Gravar" available to Siri, Spotlight, the Shortcuts app and the Action button
/// without any setup.
struct LectureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordLectureIntent(),
            phrases: [
                "Gravar no \(.applicationName)",
                "Começar a gravar no \(.applicationName)",
                "Gravar aula no \(.applicationName)",
                "Gravar uma aula no \(.applicationName)",
                "Gravar reunião no \(.applicationName)",
                "Gravar uma reunião no \(.applicationName)",
            ],
            shortTitle: "Gravar",
            systemImageName: "mic.fill"
        )
    }
}
