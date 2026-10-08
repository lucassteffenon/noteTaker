import SwiftUI

/// The AI summary of a lecture. Key points and concepts with a known position in the
/// recording show a "▶ 12:34" button that plays the lecture from there. Key points from moments
/// the student marked get a star; review questions reveal their answer.
struct SummaryView: View {
    let summary: LectureSummary
    /// nil when the recording can't be played (e.g. the audio file is missing).
    let player: LecturePlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Resumo", systemImage: "doc.text") {
                Text(summary.overview)
                    .textSelection(.enabled)
            }

            section("Pontos importantes", systemImage: "star") {
                ForEach(summary.keyPoints, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if point.important {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Marcado como importante")
                        } else {
                            Text("•")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(point.text)
                            playButton(at: point.startSeconds.playbackTime)
                        }
                    }
                }
            }

            if !summary.concepts.isEmpty {
                section("Conceitos", systemImage: "book") {
                    ForEach(summary.concepts, id: \.self) { concept in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(concept.term).bold()
                            Text(concept.explanation).foregroundStyle(.secondary)
                            playButton(at: concept.startSeconds.playbackTime)
                        }
                    }
                }
            }

            if !summary.assignments.isEmpty {
                section("Provas, trabalhos e avisos", systemImage: "calendar.badge.exclamationmark") {
                    bullets(summary.assignments)
                }
            }

            if !summary.reviewQuestions.isEmpty {
                section("Perguntas para revisar", systemImage: "questionmark.bubble") {
                    ForEach(summary.reviewQuestions, id: \.self) { item in
                        if let answer = item.answer {
                            DisclosureGroup {
                                Text(answer)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            } label: {
                                Text(item.question)
                                    .multilineTextAlignment(.leading)
                            }
                            .tint(.primary)
                        } else {
                            bullets([item.question])
                        }
                    }
                }
            }
        }
    }

    private func playButton(at time: TimeInterval?) -> some View {
        PlayFromButton(time: time, player: player)
    }

    private func section(
        _ title: String, systemImage: String, @ViewBuilder content: () -> some View
    ) -> some View {
        SummarySection(title: title, systemImage: systemImage, content: content)
    }

    private func bullets(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(item)
            }
        }
        .textSelection(.enabled)
    }
}

/// "▶ 12:34": plays the recording from `time`. Hidden when the time or the player is missing.
struct PlayFromButton: View {
    let time: TimeInterval?
    let player: LecturePlayer?

    var body: some View {
        if let time, let player {
            Button {
                player.play(from: time)
            } label: {
                Label(time.clockText, systemImage: "play.fill")
                    .font(.caption.monospacedDigit())
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .accessibilityLabel("Ouvir a partir de \(time.clockText)")
        }
    }
}

/// A titled block of a summary or meeting minutes.
struct SummarySection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
            content
        }
    }
}
