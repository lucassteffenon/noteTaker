import AVFoundation
import OSLog
import Speech

private let log = Logger(subsystem: "com.lucassteffenon.NoteTaker", category: "Transcriber")

enum TranscriptionError: LocalizedError {
    case unavailable
    case localeNotSupported(AppLanguage)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "A transcrição no aparelho não está disponível aqui. Use um iPhone real com iOS 26."
        case .localeNotSupported(let language):
            "Este aparelho não suporta transcrição em \(language.displayName.lowercased())."
        case .emptyTranscript:
            "Nenhuma fala foi reconhecida na gravação."
        }
    }
}

/// On-device transcription with Apple's SpeechAnalyzer (iOS 26+).
enum LectureTranscriber {
    /// Returns the recognized phrases with their time ranges.
    /// `onProgress` receives the fraction of the recording processed so far (0...1).
    static func transcribe(
        fileURL: URL, language: AppLanguage, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        // False on the Simulator and on devices without on-device speech models.
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.unavailable }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            throw TranscriptionError.localeNotSupported(language)
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

        let file = try AVAudioFile(forReading: fileURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate

        async let segments = transcriber.results.reduce(into: [TranscriptSegment]()) { segments, result in
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            segments.append(TranscriptSegment(
                start: result.range.start.seconds, end: result.range.end.seconds, text: text
            ))
            if duration > 0 { onProgress(min(result.range.end.seconds / duration, 1)) }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let result = try await segments
        guard !result.isEmpty else { throw TranscriptionError.emptyTranscript }
        return result
    }
}
