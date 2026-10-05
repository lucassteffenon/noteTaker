import Foundation

/// Claude Messages API with structured outputs. There is no official Swift SDK.
struct ClaudeSummarizer: Summarizer {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-5-5"

    func summarize(transcript: String, language: AppLanguage) async throws -> LectureSummary {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16_000,
            // Re-runs the request on Anthropic's recommended model if this one declines.
            "fallbacks": "default",
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": SummaryPrompt.schema],
            ],
            "system": SummaryPrompt.system(for: language),
            "messages": [
                ["role": "user", "content": SummaryPrompt.userMessage(for: transcript)],
            ],
        ]
        let headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "server-side-fallback-2026-07-01",
        ]
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
