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
                    lecture.transcript = try await LectureTranscriber.transcribe(fileURL: lecture.audioURL)
                    try? context.save()
                }

                guard let apiKey = KeychainStore.apiKey else { throw SummarizerError.missingAPIKey }
                lecture.status = .summarizing
                lecture.errorMessage = nil
                try? context.save()

                let summary = try await Summarizer(apiKey: apiKey).summarize(transcript: lecture.transcript ?? "")
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
