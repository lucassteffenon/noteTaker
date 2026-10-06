import Foundation
import Observation
import SwiftData

/// Runs the pipeline for a recorded lecture: on-device transcription, then the Claude summary.
/// Each step is persisted, so a retry after a failed summary skips the transcription.
@MainActor
@Observable
final class LectureProcessor {
    private(set) var inFlight: Set<UUID> = []

    func isProcessing(_ lecture: Lecture) -> Bool {
        inFlight.contains(lecture.id)
    }

    func process(_ lecture: Lecture, in context: ModelContext) {
        guard !inFlight.contains(lecture.id) else { return }
        inFlight.insert(lecture.id)

        Task {
            defer { inFlight.remove(lecture.id) }
            do {
                if lecture.transcript == nil {
                    lecture.status = .transcribing
                    lecture.errorMessage = nil
                    try? context.save()
                    lecture.transcript = try await LectureTranscriber.transcribe(
                        fileURL: lecture.audioURL, language: lecture.language
                    )
                    try? context.save()
                }

                let provider = SummaryProvider.selected
                guard let apiKey = KeychainStore.apiKey(for: provider) else {
                    throw SummarizerError.missingAPIKey(provider)
                }
                lecture.status = .summarizing
                lecture.errorMessage = nil
                try? context.save()

                let summary = try await provider.makeSummarizer(apiKey: apiKey, model: provider.selectedModel)
                    .summarize(transcript: lecture.transcript ?? "", language: AppLanguage.summary)
                lecture.summary = summary
                if lecture.title.isEmpty { lecture.title = summary.title }
                lecture.status = .done
            } catch {
                lecture.status = .failed
                lecture.errorMessage = error.localizedDescription
            }
            try? context.save()
        }
    }
}
