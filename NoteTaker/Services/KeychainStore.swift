import Foundation
import Security

/// Stores one API key per `SummaryProvider` in the device Keychain.
enum KeychainStore {
    private static let service = "NoteTaker"

    private static func account(for provider: SummaryProvider) -> String {
        switch provider {
        case .claude: "anthropic-api-key"
        case .openAI: "openai-api-key"
        case .gemini: "gemini-api-key"
        }
    }

    private static func baseQuery(for provider: SummaryProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
    }

    static func apiKey(for provider: SummaryProvider) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAPIKey(_ value: String?, for provider: SummaryProvider) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard let value, !value.isEmpty else { return }

        var query = baseQuery(for: provider)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}
