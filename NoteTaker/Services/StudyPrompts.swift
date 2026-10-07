import Foundation

/// Questions about one lecture, answered from its transcript.
enum LectureQuestionPrompt {
    /// Earlier messages sent along with a new question, so follow-ups make sense without
    /// letting a long conversation grow the request forever.
    static let historyLimit = 10

    static func request(lecture: Lecture, history: [ChatMessage], question: String) -> AIRequest {
        let transcript = SummaryPrompt.timestampedTranscript(
            lecture.segments, highlights: lecture.highlights, fallback: lecture.transcript ?? ""
        )
        let turns = history.suffix(historyLimit).map { AITurn(role: $0.role, text: $0.text) }
            + [AITurn(role: .user, text: question)]
        return AIRequest(
            system: system(language: AppLanguage.summary),
            context: "<transcricao>\n\(transcript)\n</transcricao>",
            turns: turns,
            schemaName: "lecture_answer",
            schema: schema,
            maxTokens: 4_000
        )
    }

    private static func system(language: AppLanguage) -> String {
        """
        Você ajuda um estudante universitário a entender uma aula que ele gravou. A transcrição \
        automática da aula vem a seguir; ela pode ter erros de reconhecimento de fala, então \
        interprete termos técnicos pelo contexto.

        Responda às perguntas do estudante em \(language.promptName), com base no que o \
        professor disse na aula. Seja direto e didático. Se a aula não tratar do assunto, diga \
        isso claramente; você pode complementar com conhecimento geral, desde que deixe claro \
        o que não foi dito na aula.

        A transcrição vem em trechos que começam com uma marcação como [754s], o segundo da \
        gravação em que o trecho começa. Trechos com ⭐ foram marcados pelo estudante como \
        importantes. Em startSeconds, informe o segundo da marcação do trecho que melhor \
        responde à pergunta, ou -1 se nenhum trecho for relevante.
        """
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "answer": ["type": "string"],
            "startSeconds": ["type": "number"],
        ],
        "required": ["answer", "startSeconds"],
        "additionalProperties": false,
    ]
}

/// The exam study guide for a folder, built from its lectures' summaries (not the transcripts,
/// which would cost much more and rarely add anything for a guide).
enum StudyGuidePrompt {
    static func request(folderName: String, lectures: [Lecture]) -> AIRequest {
        AIRequest(
            system: system(language: AppLanguage.summary),
            turns: [AITurn(role: .user, text: material(folderName: folderName, lectures: lectures))],
            schemaName: "study_guide",
            schema: schema
        )
    }

    /// Lectures that have a summary, oldest first: the order the guide numbers them in.
    static func sources(in folder: Folder) -> [Lecture] {
        folder.lectures.filter { $0.summary != nil }.sorted { $0.createdAt < $1.createdAt }
    }

    private static func material(folderName: String, lectures: [Lecture]) -> String {
        var text = "<disciplina>\(folderName)</disciplina>\n"
        for (index, lecture) in lectures.enumerated() {
            guard let summary = lecture.summary else { continue }
            let date = lecture.createdAt.formatted(date: .abbreviated, time: .omitted)
            text += "\n<aula numero=\"\(index + 1)\" data=\"\(date)\" titulo=\"\(lecture.displayTitle)\">\n"
            text += "Resumo: \(summary.overview)\n"
            text += "Pontos principais:\n"
            for point in summary.keyPoints {
                text += "- \(point.important ? "⭐ " : "")\(point.text)\n"
            }
            if !summary.concepts.isEmpty {
                text += "Conceitos:\n"
                for concept in summary.concepts {
                    text += "- \(concept.term): \(concept.explanation)\n"
                }
            }
            if !summary.assignments.isEmpty {
                text += "Avisos: \(summary.assignments.joined(separator: "; "))\n"
            }
            text += "</aula>\n"
        }
        return text
    }

    private static func system(language: AppLanguage) -> String {
        """
        Você prepara guias de estudo para provas universitárias. Você recebe os resumos de \
        todas as aulas de uma disciplina, numeradas em ordem cronológica, e monta um guia \
        único para o estudante revisar a matéria inteira. Escreva em \(language.promptName) e \
        não invente conteúdo que não esteja nas aulas.

        Preencha:
        - overview: 1 ou 2 parágrafos sobre o que a disciplina cobriu e como os assuntos se ligam.
        - mustKnow: o que o estudante não pode deixar de saber. Inclua todos os pontos marcados \
        com ⭐ (o estudante os marcou durante a aula, por exemplo quando o professor disse que \
        caem na prova), depois os mais importantes do restante.
        - topics: os grandes temas da disciplina, agrupando aulas relacionadas, cada um com uma \
        explicação que sirva para revisar.
        - concepts: os conceitos, definições e fórmulas essenciais, sem repetições entre aulas.
        - assignments: provas, trabalhos e prazos mencionados, com a data quando houver.
        - practiceQuestions: de 8 a 15 perguntas no estilo de prova, cobrindo a matéria toda, \
        cada uma com uma resposta correta e concisa.

        Em lectures, liste os números das aulas de onde cada item veio.
        """
    }

    static let schema: [String: Any] = {
        let lectures: [String: Any] = ["type": "array", "items": ["type": "integer"]]
        let point: [String: Any] = [
            "type": "object",
            "properties": ["text": ["type": "string"], "lectures": lectures],
            "required": ["text", "lectures"],
            "additionalProperties": false,
        ]
        let topic: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "explanation": ["type": "string"],
                "lectures": lectures,
            ],
            "required": ["title", "explanation", "lectures"],
            "additionalProperties": false,
        ]
        let concept: [String: Any] = [
            "type": "object",
            "properties": ["term": ["type": "string"], "explanation": ["type": "string"]],
            "required": ["term", "explanation"],
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
                "overview": ["type": "string"],
                "mustKnow": ["type": "array", "items": point],
                "topics": ["type": "array", "items": topic],
                "concepts": ["type": "array", "items": concept],
                "assignments": ["type": "array", "items": ["type": "string"]],
                "practiceQuestions": ["type": "array", "items": question],
            ],
            "required": ["overview", "mustKnow", "topics", "concepts", "assignments", "practiceQuestions"],
            "additionalProperties": false,
        ]
    }()
}
