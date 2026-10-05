import Foundation

enum SummarizerError: LocalizedError {
    case missingAPIKey
    case api(status: Int, message: String)
    case refused
    case truncated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Configure sua chave da API do Claude nos Ajustes do app."
        case .api(let status, let message):
            "Erro da API do Claude (\(status)): \(message)"
        case .refused:
            "O Claude recusou gerar o resumo desta aula."
        case .truncated:
            "O resumo ficou longo demais e foi cortado. Tente novamente."
        case .invalidResponse:
            "Resposta inesperada da API do Claude."
        }
    }
}

/// Turns a lecture transcript into a `LectureSummary` with the Claude Messages API.
/// There is no official Swift SDK, so this calls the HTTP API directly.
struct Summarizer {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-5-5"

    private static let systemPrompt = """
        Você ajuda um estudante universitário a revisar as aulas que ele gravou. \
        Você recebe a transcrição automática de uma aula, que pode conter erros de \
        reconhecimento de fala: corrija termos técnicos e nomes pelo contexto, sem inventar \
        conteúdo que o professor não disse.

        Escreva tudo em português do Brasil e preencha:
        - title: um título curto para a aula, com o tema principal.
        - overview: um resumo de 2 a 4 parágrafos do que foi ensinado, na ordem da aula.
        - keyPoints: os pontos mais importantes, cada um autossuficiente para revisão.
        - concepts: termos, definições, fórmulas ou teorias apresentados, com uma explicação clara.
        - assignments: provas, trabalhos, leituras, prazos e avisos mencionados. Lista vazia se não houver.
        - reviewQuestions: perguntas para o estudante testar se entendeu a matéria.
        """

    private static let schema: [String: Any] = {
        let strings: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let concept: [String: Any] = [
            "type": "object",
            "properties": ["term": ["type": "string"], "explanation": ["type": "string"]],
            "required": ["term", "explanation"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "overview": ["type": "string"],
                "keyPoints": strings,
                "concepts": ["type": "array", "items": concept],
                "assignments": strings,
                "reviewQuestions": strings,
            ],
            "required": ["title", "overview", "keyPoints", "concepts", "assignments", "reviewQuestions"],
            "additionalProperties": false,
        ]
    }()

    func summarize(transcript: String) async throws -> LectureSummary {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16_000,
            // Re-runs the request on Anthropic's recommended model if this one declines.
            "fallbacks": "default",
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.schema],
            ],
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": "<transcricao>\n\(transcript)\n</transcricao>"],
            ],
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SummarizerError.invalidResponse }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SummarizerError.api(status: http.statusCode, message: message)
        }

        let message = try JSONDecoder().decode(MessageBody.self, from: data)
        switch message.stopReason {
        case "refusal": throw SummarizerError.refused
        case "max_tokens": throw SummarizerError.truncated
        default: break
        }

        // Structured outputs put the JSON in the text block; thinking blocks are skipped.
        guard let json = message.content.first(where: { $0.type == "text" })?.text else {
            throw SummarizerError.invalidResponse
        }
        return try JSONDecoder().decode(LectureSummary.self, from: Data(json.utf8))
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

private struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let message: String
    }

    let error: Detail
}
