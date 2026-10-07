import Foundation

/// One request to the AI provider chosen in Ajustes, answered with JSON matching `schema`.
/// Summaries, study guides and questions about a lecture all go through this.
struct AIRequest {
    var system: String
    /// Large text that stays the same across requests (a transcript), sent right after the
    /// instructions so providers can cache it between questions about the same lecture.
    var context: String?
    var turns: [AITurn]
    var schemaName: String
    var schema: [String: Any]
    /// Only Claude requires a limit. OpenAI and Gemini count reasoning tokens against theirs,
    /// so they are left at the model's maximum.
    var maxTokens = 16_000
}

struct AITurn: Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    var role: Role
    var text: String
}

/// Calls one provider's HTTP API directly (there are no official Swift SDKs) and returns the
/// JSON text of its answer.
protocol AIClient {
    var provider: SummaryProvider { get }
    func respond(to request: AIRequest) async throws -> String
}

extension AIClient {
    func respond<T: Decodable>(to request: AIRequest, as type: T.Type) async throws -> T {
        let json = try await respond(to: request)
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw AIError.invalidResponse(provider)
        }
    }
}

extension SummaryProvider {
    func makeClient(apiKey: String, model: SummaryModel) -> any AIClient {
        switch self {
        case .claude: ClaudeClient(apiKey: apiKey, model: model.id)
        case .openAI: OpenAIClient(apiKey: apiKey, model: model.id)
        case .gemini: GeminiClient(apiKey: apiKey, model: model.id)
        }
    }

    /// A client for the provider and model chosen in Ajustes.
    static func selectedClient() throws -> any AIClient {
        let provider = selected
        guard let apiKey = KeychainStore.apiKey(for: provider) else {
            throw AIError.missingAPIKey(provider)
        }
        return provider.makeClient(apiKey: apiKey, model: provider.selectedModel)
    }
}

enum AIError: LocalizedError {
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
            "O \(provider.displayName) recusou o pedido."
        case .truncated:
            "A resposta ficou longa demais e foi cortada. Tente novamente."
        case .invalidResponse(let provider):
            "Resposta inesperada da API do \(provider.displayName)."
        }
    }
}

/// HTTP plumbing shared by the clients.
enum AIHTTP {
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
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse(provider) }
        guard http.statusCode == 200 else {
            // Anthropic, OpenAI and Gemini all report errors as {"error": {"message": ...}}.
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw AIError.api(provider, status: http.statusCode, message: message)
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
