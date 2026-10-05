import AVFoundation
import OSLog
import Speech

private let log = Logger(subsystem: "com.lucassteffenon.NoteTaker", category: "Transcriber")

enum TranscriptionError: LocalizedError {
    case unavailable
    case localeNotSupported
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "A transcrição no aparelho não está disponível aqui. Use um iPhone real com iOS 26."
        case .localeNotSupported:
            "Este aparelho não suporta transcrição em português."
        case .emptyTranscript:
            "Nenhuma fala foi reconhecida na gravação."
        }
    }
}

/// On-device transcription with Apple's SpeechAnalyzer (iOS 26+).
enum LectureTranscriber {
    static func transcribe(
        fileURL: URL, locale: Locale = Locale(identifier: "pt-BR")
    ) async throws -> String {
        // False on the Simulator and on devices without on-device speech models.
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.unavailable }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)

        // The app must reserve the locale before its model can be installed or used.
        let reserved = await AssetInventory.reservedLocales
        log.info("Locale \(supportedLocale.identifier, privacy: .public), reserved: \(reserved.map(\.identifier), privacy: .public)")
        if !reserved.contains(supportedLocale) {
            let didReserve = try await AssetInventory.reserve(locale: supportedLocale)
            log.info("Reserved \(supportedLocale.identifier, privacy: .public): \(didReserve)")
        }
        // Downloads the language model the first time it is used.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        async let transcript = transcriber.results.reduce(into: "") { text, result in
            let segment = String(result.text.characters).trimmingCharacters(in: .whitespaces)
            guard !segment.isEmpty else { return }
            text += text.isEmpty ? segment : " " + segment
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: fileURL)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let text = try await transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscript }
        return text
    }
}
