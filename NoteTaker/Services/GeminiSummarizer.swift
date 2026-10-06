import Foundation

/// Gemini `generateContent` with JSON output (`responseJsonSchema`).
struct GeminiSummarizer: Summarizer {
    let apiKey: String
    let model: String

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    func summarize(transcript: String, language: AppLanguage) async throws -> LectureSummary {
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": SummaryPrompt.system(for: language)]]],
            "contents": [
                ["role": "user", "parts": [["text": SummaryPrompt.userMessage(for: transcript)]]],
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseJsonSchema": SummaryPrompt.schema,
            ],
        ]
        // Sent as a header rather than the `?key=` query parameter so it stays out of URLs and logs.
        let headers = ["x-goog-api-key": apiKey]
        let data = try await SummaryHTTP.post(endpoint, headers: headers, body: body, provider: .gemini)

        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let candidate = response.candidates?.first else {
            // No candidates means the prompt itself was blocked (`promptFeedback.blockReason`).
            throw SummarizerError.refused(.gemini)
        }
        switch candidate.finishReason {
        case nil, "STOP": break
        case "MAX_TOKENS": throw SummarizerError.truncated
        default: throw SummarizerError.refused(.gemini) // SAFETY, RECITATION, PROHIBITED_CONTENT…
        }

        // Thinking models can return thought parts before the answer; skip them.
        let json = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        guard !json.isEmpty else { throw SummarizerError.invalidResponse(.gemini) }
        return try SummaryPrompt.decode(json, from: .gemini)
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
