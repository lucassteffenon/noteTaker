import Foundation

/// Claude Messages API with structured outputs. There is no official Swift SDK.
struct ClaudeSummarizer: Summarizer {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Haiku 4.5 rejects `effort` and server-side fallbacks; Opus 5.5 and Sonnet 5.5 accept both.
    private var supportsEffortAndFallbacks: Bool { model != "claude-haiku-4-5" }

    func summarize(transcript: String, language: AppLanguage) async throws -> LectureSummary {
        var outputConfig: [String: Any] = [
            "format": ["type": "json_schema", "schema": SummaryPrompt.schema],
        ]
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": SummaryPrompt.system(for: language),
            "messages": [
                ["role": "user", "content": SummaryPrompt.userMessage(for: transcript)],
            ],
        ]
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        ]
        if supportsEffortAndFallbacks {
            outputConfig["effort"] = "medium"
            // Re-runs the request on Anthropic's recommended model if this one declines.
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }
        body["output_config"] = outputConfig
        let data = try await SummaryHTTP.post(Self.endpoint, headers: headers, body: body, provider: .claude)

        let message = try JSONDecoder().decode(MessageBody.self, from: data)
        switch message.stopReason {
        case "refusal": throw SummarizerError.refused(.claude)
        case "max_tokens": throw SummarizerError.truncated
        default: break
        }

        // Structured outputs put the JSON in the text block; thinking blocks are skipped.
        guard let json = message.content.first(where: { $0.type == "text" })?.text else {
            throw SummarizerError.invalidResponse(.claude)
        }
        return try SummaryPrompt.decode(json, from: .claude)
    }
}

private struct MessageBody: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    let content: [Block]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
