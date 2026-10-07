import Foundation

/// Languages offered for lectures (transcription) and summaries. Chosen in Ajustes.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case portuguese = "pt-BR"
    case english = "en-US"

    static let lectureDefaultsKey = "lectureLanguage"
    static let summaryDefaultsKey = "summaryLanguage"

    static var lecture: AppLanguage { stored(lectureDefaultsKey) }
    static var summary: AppLanguage { stored(summaryDefaultsKey) }

    private static func stored(_ key: String) -> AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .portuguese
    }

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        switch self {
        case .portuguese: "Português"
        case .english: "Inglês"
        }
    }

    /// How the summary prompt refers to this language.
    var promptName: String {
        switch self {
        case .portuguese: "português do Brasil"
        case .english: "inglês"
        }
    }
}
