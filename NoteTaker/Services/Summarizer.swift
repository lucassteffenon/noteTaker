import Foundation

/// Turns a lecture transcript into a `LectureSummary`. One implementation per `SummaryProvider`;
/// each calls its provider's HTTP API directly and asks for JSON matching `SummaryPrompt.schema`.
protocol Summarizer {
    func summarize(transcript: String, language: AppLanguage) async throws -> LectureSummary
}

enum SummarizerError: LocalizedError {
    case missingAPIKey(SummaryProvider)
    case api(SummaryProvider, status: Int, message: String)
    case refused(SummaryProvider)
    case truncated
    case invalidResponse(SummaryProvider)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "Configure sua chave da API do \(provider.displayName) nos Ajustes do app."
        case .api(let provider, let status, let message):
            "Erro da API do \(provider.displayName) (\(status)): \(message)"
        case .refused(let provider):
            "O \(provider.displayName) recusou gerar o resumo desta aula."
        case .truncated:
            "O resumo ficou longo demais e foi cortado. Tente novamente."
        case .invalidResponse(let provider):
            "Resposta inesperada da API do \(provider.displayName)."
        }
    }
}

/// Instructions and output schema shared by every provider.
enum SummaryPrompt {
    /// `language` is the language the summary is written in, which may differ from the lecture's.
    static func system(for language: AppLanguage) -> String {
        """
        Você ajuda um estudante universitário a revisar as aulas que ele gravou. \
        Você recebe a transcrição automática de uma aula, que pode conter erros de \
        reconhecimento de fala: corrija termos técnicos e nomes pelo contexto, sem inventar \
        conteúdo que o professor não disse.

        Escreva todo o conteúdo em \(language.promptName). Se a aula estiver em outro idioma, \
        mantenha os termos técnicos importantes também no idioma original, entre parênteses.

        A transcrição vem em trechos que começam com uma marcação como [754s], o segundo da \
        gravação em que o trecho começa.

        Preencha:
        - title: um título curto para a aula, com o tema principal.
        - overview: um resumo de 2 a 4 parágrafos do que foi ensinado, na ordem da aula.
        - keyPoints: os pontos mais importantes, cada um autossuficiente para revisão.
        - concepts: termos, definições, fórmulas ou teorias apresentados, com uma explicação clara.
        - assignments: provas, trabalhos, leituras, prazos e avisos mencionados. Lista vazia se não houver.
        - reviewQuestions: perguntas para o estudante testar se entendeu a matéria, cada uma \
        com uma resposta curta e correta segundo a aula (serão usadas como flashcards).

        Em keyPoints e concepts, startSeconds é o segundo da marcação do trecho em que aquele \
        assunto começa a ser explicado. Use -1 se a transcrição não tiver marcações.

        Trechos com ⭐ depois da marcação foram marcados pelo estudante durante a aula como \
        importantes (por exemplo, quando o professor disse que o assunto cai na prova). Garanta \
        que o conteúdo deles apareça em keyPoints, de preferência no início, com important = true. \
        Nos demais pontos, important = false.
        """
    }

    /// JSON Schema for `LectureSummary`; keep the two in sync.
    static let schema: [String: Any] = {
        let strings: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let keyPoint: [String: Any] = [
            "type": "object",
            "properties": [
                "text": ["type": "string"],
                "startSeconds": ["type": "number"],
                "important": ["type": "boolean"],
            ],
            "required": ["text", "startSeconds", "important"],
            "additionalProperties": false,
        ]
        let concept: [String: Any] = [
            "type": "object",
            "properties": [
                "term": ["type": "string"],
                "explanation": ["type": "string"],
                "startSeconds": ["type": "number"],
            ],
            "required": ["term", "explanation", "startSeconds"],
            "additionalProperties": false,
        ]
        let question: [String: Any] = [
            "type": "object",
            "properties": ["question": ["type": "string"], "answer": ["type": "string"]],
            "required": ["question", "answer"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "overview": ["type": "string"],
                "keyPoints": ["type": "array", "items": keyPoint],
                "concepts": ["type": "array", "items": concept],
                "assignments": strings,
                "reviewQuestions": ["type": "array", "items": question],
            ],
            "required": ["title", "overview", "keyPoints", "concepts", "assignments", "reviewQuestions"],
            "additionalProperties": false,
        ]
    }()

    static func userMessage(for transcript: String) -> String {
        "<transcricao>\n\(transcript)\n</transcricao>"
    }

    /// The transcript as sent to the AI: phrases merged into ~30 s blocks, each prefixed with
    /// its start second so the summary can point back into the recording, and with ⭐ when it
    /// contains a phrase the student marked. Falls back to the plain text for lectures
    /// transcribed before segments were stored.
    static func timestampedTranscript(
        _ segments: [TranscriptSegment], highlights: [TimeInterval] = [], fallback: String
    ) -> String {
        guard !segments.isEmpty else { return fallback }
        var blocks: [String] = []
        var blockStart: TimeInterval = 0
        var blockText = ""
        var blockMarked = false
        func closeBlock() {
            blocks.append("[\(Int(blockStart))s]\(blockMarked ? " ⭐" : "") \(blockText)")
            blockText = ""
            blockMarked = false
        }
        for segment in segments {
            if blockText.isEmpty { blockStart = segment.start }
            blockText += blockText.isEmpty ? segment.text : " " + segment.text
            blockMarked = blockMarked || segment.isHighlighted(by: highlights)
            if segment.end - blockStart >= 30 { closeBlock() }
        }
        if !blockText.isEmpty { closeBlock() }
        return blocks.joined(separator: "\n")
    }

    static func decode(_ json: String, from provider: SummaryProvider) throws -> LectureSummary {
        do {
            return try JSONDecoder().decode(LectureSummary.self, from: Data(json.utf8))
        } catch {
            throw SummarizerError.invalidResponse(provider)
        }
    }
}

/// HTTP plumbing shared by the summarizers.
enum SummaryHTTP {
    static func post(
        _ url: URL, headers: [String: String], body: [String: Any], provider: SummaryProvider
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SummarizerError.invalidResponse(provider) }
        guard http.statusCode == 200 else {
            // Anthropic, OpenAI and Gemini all report errors as {"error": {"message": ...}}.
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SummarizerError.api(provider, status: http.statusCode, message: message)
        }
        return data
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }
}
