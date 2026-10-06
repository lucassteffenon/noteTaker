# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal iOS app (SwiftUI, iOS 26+) for recording university lectures and getting a study summary. UI strings are in Brazilian Portuguese; code and comments are in English. Single user, no backend: everything is stored on the device.

## Commands

```bash
# Build for the simulator
xcodebuild -project NoteTaker.xcodeproj -scheme NoteTaker -destination 'generic/platform=iOS Simulator' build
```

The app icon is drawn in code: edit `scripts/generate_icon.swift`, then run `swift scripts/generate_icon.swift NoteTaker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, no alpha channel).

There are no tests yet. The project uses file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new `.swift` files compile without editing `project.pbxproj`:

- `NoteTaker/` → app target.
- `Widgets/` → `NoteTakerWidgets` extension (Live Activity + Control Center control), embedded in the app.
- `Shared/` → both targets: `RecordingActivityAttributes` and the App Intents (`RecordLectureIntent`, `MarkMomentIntent`). The system runs those intents in the app's process; they talk to the UI through `RecordingCommands.shared`.

Build settings and simple Info.plist keys (`INFOPLIST_KEY_*`) live in `project.pbxproj`. Arrays and dictionaries go in `Config/Info.plist` (background modes, BGTask identifiers) and `Config/WidgetsInfo.plist` (`NSExtension`).

## Pipeline

`RecordingView` → `AudioRecorder` (AAC, 16 kHz mono) → a `Lecture` is saved (SwiftData) → `LectureProcessor.process` runs the steps below. After recording it is called with `summarize: false`: the free transcription runs and the lecture stops at `.transcribed`, so the paid summary only runs when the user taps "Gerar resumo" in `LectureDetailView`.

1. **Transcription** – `LectureTranscriber` uses Apple's `SpeechAnalyzer`/`SpeechTranscriber` on-device, in the lecture's language (`AppLanguage`: pt-BR or en-US). The language is chosen in Ajustes, or per folder (`Folder.languageRaw`, nil = follow Ajustes, set from the globe menu in `FolderView`), and copied into `Lecture.languageRaw` when recording starts, so retries keep using it. The summary language is a separate setting, passed to `SummaryPrompt.system(for:)`. The locale must be reserved with `AssetInventory.reserve(locale:)` before the model is installed. **It doesn't work on the Simulator** (`SpeechTranscriber.isAvailable == false`), so test on a real iPhone, or run the same code from a Swift script on macOS 26.
2. **Summary** – the user picks the provider in Ajustes (`SummaryProvider`: Claude, OpenAI or Gemini, stored in `UserDefaults`). Each one implements the `Summarizer` protocol over raw HTTP and asks for JSON output using the same prompt and schema (`SummaryPrompt`, which must stay in sync with `LectureSummary`):
   - `ClaudeSummarizer`: Messages API, `output_config.format`. On Opus 5.5 / Sonnet 5.5 it also sends `effort` and `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`); Haiku 4.5 rejects both.
   - `OpenAISummarizer`: Responses API, `text.format` with a strict `json_schema`.
   - `GeminiSummarizer`: `generateContent`, `responseJsonSchema`. The key goes in the `x-goog-api-key` header, never in the URL.

   All three APIs return errors as `{"error": {"message": ...}}`, which `SummaryHTTP.post` handles in one place. The models offered per provider (cheapest first, which is the default) and their estimated cost per 1h30 lecture live in `SummaryProvider.models`; the user picks one in Ajustes.

Each step is persisted in `Lecture` (`transcript`, `segmentsData`, `summaryData`, `statusRaw`), so "Tentar novamente" (retry) skips the transcription when it already exists. A lecture stuck in `transcribing`/`summarizing` without a running task (the app was closed) is treated as interrupted in the UI and can be retried.

**Background:** `LectureProcessor` runs the pipeline in a normal `Task`, and `ContinuedProcessing` submits an iOS 26 `BGContinuedProcessingTask` (unique id under the `BGTaskSchedulerPermittedIdentifiers` wildcard in `Config/Info.plist`, plus the `processing` background mode) that mirrors its `Progress` and cancels it on expiration. On the Simulator the submit fails with "unavailable" and the work only runs in the foreground; test on a device.

**Marked moments:** while recording, "Importante" (in the app or on the Live Activity) appends the current time to `Lecture.highlights`. A mark covers the preceding `Highlight.lookback` seconds (`TranscriptSegment.isHighlighted`): those transcript blocks go to the AI with ⭐, and it flags the resulting key points with `important`.

**Playback:** the transcriber stores phrase-level `TranscriptSegment`s (start/end seconds). The summary request sends the transcript as ~30 s blocks prefixed with `[123s]`, and the AI returns `startSeconds` for key points and concepts (-1 = unknown). `LectureSummary.KeyPoint` and `ReviewQuestion` also decode older plain-string summaries. `LecturePlayer` + `TranscriptView`/`AudioPlayerBar` (PlaybackViews.swift) play the recording from a tapped phrase or summary item.

## Folders

`Folder` (SwiftData) groups lectures, one level only. `Lecture.folder == nil` means "Sem pasta" (unfiled). The relationship uses `deleteRule: .nullify`, so deleting a folder keeps its lectures. `LibraryView` is the root screen (folders + unfiled lectures); `FolderView` lists one folder; both reuse `LectureRows` (row, long-press "Mover para" menu, delete) and `RecordLectureButton`, which passes the folder to `RecordingView`. New stored properties on the models need a default value (or must be optional) so SwiftData can migrate existing data.

**Study:** the library's search (`LectureSearchResults`) scans titles, summaries and transcript phrases in memory. `FlashcardsView` builds cards from review questions (question → answer) and concepts, for one lecture or a whole folder.

**Shortcuts:** `LectureShortcuts` (AppShortcutsProvider) exposes "Gravar aula" to Siri, Spotlight and the Action button. On the iOS 26.5 simulator with Xcode 27 metadata, running it from Spotlight fails with "couldn't find the AppShortcutsProvider"; the Control Center control (same intent, run directly) works.

## Storage

- Audio: `Documents/Recordings/<uuid>.m4a`. `Lecture` stores only the file name, because the container path changes between installs.
- API keys: one per provider in the Keychain (`KeychainStore`), entered in Ajustes (Settings). Never hardcode them.
