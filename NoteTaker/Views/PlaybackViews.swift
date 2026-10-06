import SwiftUI

/// Transcript as a list of phrases; tapping one plays the recording from that moment.
/// The phrase being played is highlighted.
struct TranscriptView: View {
    let segments: [TranscriptSegment]
    /// Moments marked while recording; the phrases they point at get a star.
    var highlights: [TimeInterval] = []
    let player: LecturePlayer?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let now = player?.currentTime ?? 0
            let isPlaying = player?.isPlaying ?? false
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let isCurrent = isPlaying && segment.start <= now && now < segment.end
                    let isHighlighted = segment.isHighlighted(by: highlights)
                    Button {
                        player?.play(from: segment.start)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(segment.start.clockText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                            Text(segment.text)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if isHighlighted {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            isCurrent ? Color.accentColor.opacity(0.15)
                                : isHighlighted ? Color.yellow.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(player == nil)
                }
            }
        }
    }
}

/// Play/pause, position and scrubber for the lecture recording, pinned to the bottom.
struct AudioPlayerBar: View {
    let player: LecturePlayer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 12) {
                Button(player.isPlaying ? "Pausar" : "Ouvir", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.togglePlayback()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 44, height: 44)

                Text(player.currentTime.clockText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 1)
                )
                .accessibilityLabel("Posição na gravação")

                Text(player.duration.clockText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}
