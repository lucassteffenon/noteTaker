import Foundation

/// What a recording is: a class or a meeting. It picks the summary (study material or meeting
/// minutes) and the wording around it. Set per folder, with a default in Ajustes.
enum RecordingKind: String, CaseIterable, Identifiable, Codable {
    case lecture
    case meeting

    static let defaultsKey = "recordingKind"

    /// The default from Ajustes, for unfiled recordings and folders without their own kind.
    static var standard: RecordingKind {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(RecordingKind.init) ?? .lecture
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lecture: "Aula"
        case .meeting: "Reunião"
        }
    }

    /// Lowercase, for use mid-sentence: "Gravar \(noun)".
    var noun: String {
        displayName.lowercased()
    }

    var systemImage: String {
        switch self {
        case .lecture: "graduationcap"
        case .meeting: "person.2"
        }
    }
}
