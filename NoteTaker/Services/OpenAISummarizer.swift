import Foundation

/// OpenAI Responses API with structured outputs (`text.format` = strict JSON schema).
struct OpenAISummarizer: Summarizer {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    let model: String

    func summarize(transcript: String, language: AppLanguage) async throws -> LectureSummary {
        let body: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": SummaryPrompt.system(for: language)],
                ["role": "user", "content": SummaryPrompt.userMessage(for: transcript)],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "lecture_summary",
                    "strict": true,
                    "schema": SummaryPrompt.schema,
                ],
            ],
        ]
        let headers = ["authorization": "Bearer \(apiKey)"]
        let data = try await SummaryHTTP.post(Self.endpoint, headers: headers, body: body, provider: .openAI)

        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        if response.status == "incomplete" {
            throw SummarizerError.truncated
        }

        // Reasoning items can precede the message, so find the message instead of taking output[0].
        let content = response.output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
        if content.contains(where: { $0.type == "refusal" }) {
            throw SummarizerError.refused(.openAI)
        }
        guard let json = content.first(where: { $0.type == "output_text" })?.text else {
            throw SummarizerError.invalidResponse(.openAI)
        }
        return try SummaryPrompt.decode(json, from: .openAI)
    }
}

private struct ResponseBody: Decodable {
    struct Item: Decodable {
        let type: String
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }

    let status: String?
    let output: [Item]
}
