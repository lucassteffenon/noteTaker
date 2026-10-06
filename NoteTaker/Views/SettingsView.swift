import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SummaryProvider.defaultsKey) private var savedProvider = SummaryProvider.claude
    @AppStorage(AppLanguage.lectureDefaultsKey) private var savedLectureLanguage = AppLanguage.portuguese
    @AppStorage(AppLanguage.summaryDefaultsKey) private var savedSummaryLanguage = AppLanguage.portuguese
    @State private var provider = SummaryProvider.selected
    @State private var lectureLanguage = AppLanguage.lecture
    @State private var summaryLanguage = AppLanguage.summary
    @State private var apiKeys = Dictionary(
        uniqueKeysWithValues: SummaryProvider.allCases.map { ($0, KeychainStore.apiKey(for: $0) ?? "") }
    )
    @State private var models = Dictionary(
        uniqueKeysWithValues: SummaryProvider.allCases.map { ($0, $0.selectedModel) }
    )

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Idioma das aulas", selection: $lectureLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Idioma do resumo", selection: $summaryLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Idiomas")
                } footer: {
                    Text("O idioma das aulas vale para as próximas gravações e precisa ser o idioma falado pelo professor.")
                }

                Section {
                    Picker("Serviço", selection: $provider) {
                        ForEach(SummaryProvider.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Modelo", selection: modelBinding(for: provider)) {
                        ForEach(provider.models) { model in
                            Text("\(model.name) · \(model.cost)").tag(model)
                        }
                    }
                } header: {
                    Text("IA que gera os resumos")
                } footer: {
                    Text("Custo estimado por aula de 1h30. A transcrição é sempre feita no aparelho, de graça; só o texto da aula é enviado ao serviço escolhido.")
                }

                Section {
                    SecureField(provider.keyPlaceholder, text: binding(for: provider))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Chave da API do \(provider.displayName)")
                } footer: {
                    Text("Fica salva no Keychain deste aparelho. [Criar uma chave](\(provider.keysURL.absoluteString))")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                }
            }
        }
    }

    private func binding(for provider: SummaryProvider) -> Binding<String> {
        Binding(get: { apiKeys[provider, default: ""] }, set: { apiKeys[provider] = $0 })
    }

    private func modelBinding(for provider: SummaryProvider) -> Binding<SummaryModel> {
        Binding(get: { models[provider] ?? provider.selectedModel }, set: { models[provider] = $0 })
    }

    private func save() {
        for (provider, key) in apiKeys {
            KeychainStore.setAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        }
        for (provider, model) in models {
            UserDefaults.standard.set(model.id, forKey: provider.modelDefaultsKey)
        }
        savedProvider = provider
        savedLectureLanguage = lectureLanguage
        savedSummaryLanguage = summaryLanguage
        dismiss()
    }
}
