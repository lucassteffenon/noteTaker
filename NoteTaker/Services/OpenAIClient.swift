import Foundation

/// OpenAI Responses API with structured outputs (`text.format` = strict JSON schema).
struct OpenAIClient: AIClient {
    let apiKey: String
    let model: String
    var provider: SummaryProvider { .openAI }

    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func respond(to request: AIRequest) async throws -> String {
        // OpenAI caches long prompt prefixes on its own, so the context goes right after the
        // instructions and before the conversation.
        let instructions = [request.system, request.context].compactMap(\.self).joined(separator: "\n\n")
        let body: [String: Any] = [
            "model": model,
            "input": [["role": "system", "content": instructions]]
                + request.turns.map { ["role": $0.role.rawValue, "content": $0.text] },
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": request.schemaName,
                    "strict": true,
                    "schema": request.schema,
                ],
            ],
        ]
        let headers = ["authorization": "Bearer \(apiKey)"]
        let data = try await AIHTTP.post(Self.endpoint, headers: headers, body: body, provider: .openAI)

        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        if response.status == "incomplete" {
            throw AIError.truncated
        }

        // Reasoning items can precede the message, so find the message instead of taking output[0].
        let content = response.output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
        if content.contains(where: { $0.type == "refusal" }) {
            throw AIError.refused(.openAI)
        }
        guard let json = content.first(where: { $0.type == "output_text" })?.text else {
            throw AIError.invalidResponse(.openAI)
        }
        return json
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
