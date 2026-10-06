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

    /// Models offered in Ajustes, cheapest first. The first one is the default.
    /// `cost` estimates one 1h30 lecture (~20k input + ~5k output tokens) at list prices.
    var models: [SummaryModel] {
        switch self {
        case .claude: [
            SummaryModel(id: "claude-haiku-4-5", name: "Haiku 4.5", cost: "~US$ 0,05"),
            SummaryModel(id: "claude-sonnet-5-5", name: "Sonnet 5.5", cost: "~US$ 0,09"),
            SummaryModel(id: "claude-opus-5-5", name: "Opus 5.5", cost: "~US$ 0,18"),
        ]
        case .openAI: [
            SummaryModel(id: "gpt-6-luna", name: "GPT-6 Luna", cost: "< US$ 0,01"),
            SummaryModel(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", cost: "~US$ 0,09"),
            SummaryModel(id: "gpt-6-astra", name: "GPT-6 Astra", cost: "~US$ 0,45"),
        ]
        case .gemini: [
            SummaryModel(id: "gemini-3.1-flash-lite", name: "Gemini 3.1 Flash-Lite", cost: "~US$ 0,01"),
            SummaryModel(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", cost: "~US$ 0,03"),
        ]
        }
    }

    var modelDefaultsKey: String { "summaryModel.\(rawValue)" }

    /// The model chosen in Ajustes for this provider, falling back to the cheapest.
    var selectedModel: SummaryModel {
        let id = UserDefaults.standard.string(forKey: modelDefaultsKey)
        return models.first { $0.id == id } ?? models[0]
    }

    func makeSummarizer(apiKey: String, model: SummaryModel) -> any Summarizer {
        switch self {
        case .claude: ClaudeSummarizer(apiKey: apiKey, model: model.id)
        case .openAI: OpenAISummarizer(apiKey: apiKey, model: model.id)
        case .gemini: GeminiSummarizer(apiKey: apiKey, model: model.id)
        }
    }
}

struct SummaryModel: Identifiable, Hashable {
    let id: String
    let name: String
    let cost: String
}
