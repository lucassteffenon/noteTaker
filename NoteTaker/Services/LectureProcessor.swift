import Foundation
import Observation
import SwiftData

/// Runs the pipeline for a recorded lecture: on-device transcription, then the AI summary.
/// Each step is persisted, so a retry after a failed summary skips the transcription.
/// The job keeps running in the background through `ContinuedProcessing`.
@MainActor
@Observable
final class LectureProcessor {
    private(set) var inFlight: Set<UUID> = []
    /// Fraction (0...1) of the recording transcribed so far, per lecture being transcribed.
    private(set) var transcriptionProgress: [UUID: Double] = [:]

    /// Share of the overall progress given to transcription; the summary is the rest.
    nonisolated private static let transcriptionUnits: Int64 = 85

    func isProcessing(_ lecture: Lecture) -> Bool {
        inFlight.contains(lecture.id)
    }

    func process(_ lecture: Lecture, in context: ModelContext) {
        let id = lecture.id
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        let progress = Progress(totalUnitCount: 100)

        let work = Task {
            defer {
                inFlight.remove(id)
                transcriptionProgress[id] = nil
            }
            do {
                if lecture.transcript == nil {
                    lecture.status = .transcribing
                    lecture.errorMessage = nil
                    try? context.save()
                    let segments = try await LectureTranscriber.transcribe(
                        fileURL: lecture.audioURL, language: lecture.language
                    ) { fraction in
                        progress.completedUnitCount = Int64(fraction * Double(Self.transcriptionUnits))
                        Task { @MainActor in self.transcriptionProgress[id] = fraction }
                    }
                    lecture.segments = segments
                    lecture.transcript = segments.map(\.text).joined(separator: " ")
                    try? context.save()
                }
                progress.completedUnitCount = Self.transcriptionUnits

                let provider = SummaryProvider.selected
                guard let apiKey = KeychainStore.apiKey(for: provider) else {
                    throw SummarizerError.missingAPIKey(provider)
                }
                lecture.status = .summarizing
                lecture.errorMessage = nil
                try? context.save()

                let transcript = SummaryPrompt.timestampedTranscript(
                    lecture.segments, fallback: lecture.transcript ?? ""
                )
                let summary = try await provider.makeSummarizer(apiKey: apiKey, model: provider.selectedModel)
                    .summarize(transcript: transcript, language: AppLanguage.summary)
                lecture.summary = summary
                if lecture.title.isEmpty { lecture.title = summary.title }
                lecture.status = .done
                progress.completedUnitCount = 100
            } catch {
                lecture.status = .failed
                lecture.errorMessage = Task.isCancelled
                    ? "O iPhone interrompeu o processamento. Toque em Tentar novamente."
                    : error.localizedDescription
            }
            try? context.save()
        }

        ContinuedProcessing.start(
            title: "Processando aula", subtitle: lecture.displayTitle, progress: progress, work: work
        )
    }
}
