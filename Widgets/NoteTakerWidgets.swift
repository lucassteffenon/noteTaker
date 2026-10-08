import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct NoteTakerWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
        RecordLectureControl()
    }
}

/// "Gravar aula" button for Control Center, the Lock Screen and the Action button.
struct RecordLectureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lucassteffenon.NoteTaker.record") {
            ControlWidgetButton(action: RecordLectureIntent()) {
                Label("Gravar aula", systemImage: "mic.fill")
            }
        }
        .displayName("Gravar aula")
        .description("Abre o app Aulas já gravando.")
    }
}

/// Timer and "Importante" button while a lecture is being recorded.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(context.isPaused ? "Pausado" : "Gravando", systemImage: "waveform")
                        .font(.subheadline.bold())
                        .foregroundStyle(context.isPaused ? Color.secondary : Color.red)
                    ElapsedText(state: context.state)
                        .font(.title.monospacedDigit().weight(.semibold))
                    Text(context.attributes.folderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MarkButton(count: context.state.markCount)
                    .disabled(context.isPaused)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.folderName, systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(context.isPaused ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MarkButton(count: context.state.markCount)
                        .disabled(context.isPaused)
                }
            } compactLeading: {
                Image(systemName: context.isPaused ? "pause.fill" : "waveform")
                    .foregroundStyle(context.isPaused ? Color.secondary : Color.red)
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            }
        }
    }
}

private extension ActivityViewContext<RecordingActivityAttributes> {
    var isPaused: Bool { state.pausedElapsed != nil }
}

/// Counts up on its own while recording; frozen while paused.
private struct ElapsedText: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        if let elapsed = state.pausedElapsed {
            Text(Duration.seconds(elapsed), format: .time(pattern: .hourMinuteSecond))
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

private struct MarkButton: View {
    let count: Int

    var body: some View {
        Button(intent: MarkMomentIntent()) {
            Label(count == 0 ? "Importante" : "Importante (\(count))", systemImage: "star.fill")
                .font(.subheadline.bold())
        }
        .tint(.yellow)
    }
}
