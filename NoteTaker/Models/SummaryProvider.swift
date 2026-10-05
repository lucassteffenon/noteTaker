import Foundation

/// AI service that writes the lecture summary. The user picks one in Ajustes.
enum SummaryProvider: String, CaseIterable, Identifiable {
    case claude, openAI, gemini

    static let defaultsKey = "summaryProvider"

    /// The provider chosen in Ajustes (stored in UserDefaults via `@AppStorage`).
    static var selected: SummaryProvider {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SummaryProvider.init) ?? .claude
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: "sk-ant-…"
        case .openAI: "sk-…"
        case .gemini: "AIza…"
        }
    }

    var keysURL: URL {
        switch self {
        case .claude: URL(string: "https://platform.claude.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    func makeSummarizer(apiKey: String) -> any Summarizer {
        switch self {
        case .claude: ClaudeSummarizer(apiKey: apiKey)
        case .openAI: OpenAISummarizer(apiKey: apiKey)
        case .gemini: GeminiSummarizer(apiKey: apiKey)
        }
    }
}
