import Foundation
import Observation
import SwiftData

/// Runs the pipeline for a recorded lecture: on-device transcription, then the AI summary.
/// Each step is persisted, so a retry after a failed summary skips the transcription.
/// The summary costs money, so after recording it only runs when the user asks for it.
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

    func process(_ lecture: Lecture, in context: ModelContext, summarize: Bool) {
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
                guard summarize else {
                    lecture.status = .transcribed
                    progress.completedUnitCount = 100
                    try? context.save()
                    return
                }

                let client = try SummaryProvider.selectedClient()
                lecture.status = .summarizing
                lecture.errorMessage = nil
                try? context.save()

                let transcript = SummaryPrompt.timestampedTranscript(
                    lecture.segments, highlights: lecture.highlights, fallback: lecture.transcript ?? ""
                )
                let summary = try await client.respond(
                    to: SummaryPrompt.request(transcript: transcript, language: AppLanguage.summary),
                    as: LectureSummary.self
                )
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
            title: summarize ? "Processando aula" : "Transcrevendo aula", subtitle: lecture.displayTitle, progress: progress, work: work
        )
    }
}
