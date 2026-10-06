import AppIntents
import Observation

/// Bridge between the intents below and the running app. The intents are compiled into the
/// widget extension too (the control and the Live Activity reference them), but the system runs
/// them in the app's process, where `LibraryView` and `RecordingView` act on this state.
@MainActor
@Observable
final class RecordingCommands {
    static let shared = RecordingCommands()

    /// Set by `RecordLectureIntent`; the library screen opens the recorder and clears it.
    var startRequested = false
    /// Set while the recording screen is open, so a second request doesn't open another one.
    var isRecording = false
    /// Installed by the recording screen; marks the current moment as important.
    @ObservationIgnored var markMoment: (@MainActor () -> Void)?
}

/// "Gravar aula": opens the app straight into a new recording. Used by Siri, the Action button,
/// Spotlight and the Control Center / Lock Screen control.
struct RecordLectureIntent: AppIntent {
    static let title: LocalizedStringResource = "Gravar aula"
    static let description = IntentDescription("Abre o app e começa a gravar uma aula nova.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        if !RecordingCommands.shared.isRecording {
            RecordingCommands.shared.startRequested = true
        }
        return .result()
    }
}

/// The "Importante" button on the recording Live Activity.
struct MarkMomentIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Marcar momento importante"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommands.shared.markMoment?()
        return .result()
    }
}
