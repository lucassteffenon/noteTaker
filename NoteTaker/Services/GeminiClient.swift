import Foundation

/// Gemini `generateContent` with JSON output (`responseJsonSchema`).
struct GeminiClient: AIClient {
    let apiKey: String
    let model: String
    var provider: SummaryProvider { .gemini }

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    func respond(to request: AIRequest) async throws -> String {
        let instructions = [request.system, request.context].compactMap(\.self)
        let body: [String: Any] = [
            "systemInstruction": ["parts": instructions.map { ["text": $0] }],
            "contents": request.turns.map {
                ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]]
            },
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseJsonSchema": request.schema,
            ],
        ]
        // Sent as a header rather than the `?key=` query parameter so it stays out of URLs and logs.
        let headers = ["x-goog-api-key": apiKey]
        let data = try await AIHTTP.post(endpoint, headers: headers, body: body, provider: .gemini)

        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let candidate = response.candidates?.first else {
            // No candidates means the prompt itself was blocked (`promptFeedback.blockReason`).
            throw AIError.refused(.gemini)
        }
        switch candidate.finishReason {
        case nil, "STOP": break
        case "MAX_TOKENS": throw AIError.truncated
        default: throw AIError.refused(.gemini) // SAFETY, RECITATION, PROHIBITED_CONTENT…
        }

        // Thinking models can return thought parts before the answer; skip them.
        let json = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        guard !json.isEmpty else { throw AIError.invalidResponse(.gemini) }
        return json
    }
}

private struct ResponseBody: Decodable {
    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
        let thought: Bool?
    }

    let candidates: [Candidate]?
}
