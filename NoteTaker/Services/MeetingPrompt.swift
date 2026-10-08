import Foundation

/// Instructions and output schema for meeting minutes (`MeetingSummary`), the meeting
/// counterpart of `SummaryPrompt`. Uses the same timestamped transcript.
enum MeetingPrompt {
    static func system(for language: AppLanguage, date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "pt-BR")))
        let isoDay = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return """
        Você escreve a ata de uma reunião que o usuário gravou. Você recebe a transcrição \
        automática, que pode conter erros de reconhecimento de fala: corrija nomes e termos \
        pelo contexto, sem inventar nada que não foi dito. A transcrição não identifica quem \
        está falando; só atribua algo a uma pessoa quando o próprio diálogo deixar isso claro \
        (por exemplo, "João, você fica com isso?").

        A reunião aconteceu em \(day) (\(isoDay)). Escreva todo o conteúdo em \
        \(language.promptName).

        A transcrição vem em trechos que começam com uma marcação como [754s], o segundo da \
        gravação em que o trecho começa.

        Preencha:
        - title: um título curto com o assunto principal da reunião.
        - overview: um resumo de 1 a 3 parágrafos do que foi discutido e do resultado.
        - keyPoints: os assuntos e informações importantes discutidos, cada um autossuficiente.
        - decisions: as decisões tomadas, de forma objetiva. Lista vazia se nada foi decidido.
        - actionItems: as tarefas combinadas. Em task, o que precisa ser feito, começando com \
        um verbo. Em owner, o nome de quem ficou responsável, ou "" se ninguém foi nomeado. Em \
        dueDate, o prazo no formato AAAA-MM-DD, calculado a partir da data da reunião quando \
        disserem algo como "até sexta" ou "semana que vem", ou "" se não houver prazo.
        - openQuestions: o que ficou em aberto, sem resposta ou para decidir depois.

        Em todos os itens com startSeconds, informe o segundo da marcação do trecho em que o \
        assunto aparece. Use -1 se a transcrição não tiver marcações.

        Trechos com ⭐ depois da marcação foram marcados pelo usuário durante a reunião como \
        importantes. Garanta que o conteúdo deles apareça (em keyPoints, decisions ou \
        actionItems, conforme o caso); nos keyPoints que vierem deles, important = true. Nos \
        demais, important = false.
        """
    }

    /// JSON Schema for `MeetingSummary`; keep the two in sync.
    static let schema: [String: Any] = {
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
        let decision: [String: Any] = [
            "type": "object",
            "properties": ["text": ["type": "string"], "startSeconds": ["type": "number"]],
            "required": ["text", "startSeconds"],
            "additionalProperties": false,
        ]
        let actionItem: [String: Any] = [
            "type": "object",
            "properties": [
                "task": ["type": "string"],
                "owner": ["type": "string"],
                "dueDate": ["type": "string"],
                "startSeconds": ["type": "number"],
            ],
            "required": ["task", "owner", "dueDate", "startSeconds"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "overview": ["type": "string"],
                "keyPoints": ["type": "array", "items": keyPoint],
                "decisions": ["type": "array", "items": decision],
                "actionItems": ["type": "array", "items": actionItem],
                "openQuestions": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["title", "overview", "keyPoints", "decisions", "actionItems", "openQuestions"],
            "additionalProperties": false,
        ]
    }()

    static func request(transcript: String, language: AppLanguage, date: Date) -> AIRequest {
        AIRequest(
            system: system(for: language, date: date),
            turns: [AITurn(role: .user, text: "<transcricao>\n\(transcript)\n</transcricao>")],
            schemaName: "meeting_summary",
            schema: schema
        )
    }
}
