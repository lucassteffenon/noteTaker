# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal iOS app (SwiftUI, iOS 26+) for recording university lectures and meetings and getting a study summary or meeting minutes. UI strings are in Brazilian Portuguese; code and comments are in English. Single user, no backend: everything is stored on the device.

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

`RecordingSession` → `RecordingView` → `AudioRecorder` (AAC, 16 kHz mono) → a `Lecture` is saved (SwiftData) → `LectureProcessor.process` runs the steps below. After recording it is called with `summarize: false`: the free transcription runs and the lecture stops at `.transcribed`, so the paid summary only runs when the user taps "Gerar resumo" in `LectureDetailView`.

1. **Transcription** – `LectureTranscriber` uses Apple's `SpeechAnalyzer`/`SpeechTranscriber` on-device, in the lecture's language (`AppLanguage`: pt-BR or en-US). The language is chosen in Ajustes, or per folder (`Folder.languageRaw`, nil = follow Ajustes, set from the globe menu in `FolderView`), and copied into `Lecture.languageRaw` when recording starts, so retries keep using it. The summary language is a separate setting, passed to `SummaryPrompt.system(for:)`. The locale must be reserved with `AssetInventory.reserve(locale:)` before the model is installed. **It doesn't work on the Simulator** (`SpeechTranscriber.isAvailable == false`), so test on a real iPhone, or run the same code from a Swift script on macOS 26.
2. **Summary** – the user picks the provider in Ajustes (`SummaryProvider`: Claude, OpenAI or Gemini, stored in `UserDefaults`). Each one implements `AIClient` (AIClient.swift) over raw HTTP: it takes an `AIRequest` (instructions, an optional cacheable `context`, conversation turns, a JSON schema) and returns JSON text. The summary is one such request (`SummaryPrompt`, whose schema must stay in sync with `LectureSummary`); so are the study features below (`StudyPrompts.swift`).
   - `ClaudeClient`: Messages API, `output_config.format`. The `context` goes in a second system block with `cache_control`. On Opus 5.5 / Sonnet 5.5 it also sends `effort` and `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`); Haiku 4.5 rejects both.
   - `OpenAIClient`: Responses API, `text.format` with a strict `json_schema`. Prompt prefixes are cached automatically.
   - `GeminiClient`: `generateContent`, `responseJsonSchema`. The key goes in the `x-goog-api-key` header, never in the URL.

   All three APIs return errors as `{"error": {"message": ...}}`, which `AIHTTP.post` handles in one place. Only Claude gets a `max_tokens`; OpenAI and Gemini count reasoning tokens against their limit, so none is sent. The models offered per provider (cheapest first, which is the default) and their estimated cost per 1h30 lecture live in `SummaryProvider.models`; the user picks one in Ajustes.

**Lectures vs meetings:** every recording has a `RecordingKind` (`Lecture.kindRaw`), copied at recording time from the folder (`Folder.kindRaw`, nil = the default in Ajustes, `RecordingKind.standard`). The `Lecture` model is used for both. A class gets `LectureSummary` (`summaryData`, `SummaryPrompt`); a meeting gets `MeetingSummary` minutes (`meetingData`, `MeetingPrompt`): decisions, action items with owner and due date (the prompt gets the meeting date to resolve "até sexta"), open questions and subjects. `ActionItem.done`/`reminderID` are local state outside the schema; `MeetingSummaryView` toggles them and `RemindersExport` (EventKit, full Reminders access) adds items to Lembretes. Use `lecture.hasSummary` (summary for the current kind). Changing a lecture's kind keeps both summaries. Study features (flashcards, study guide) only show for classes. The transcriber doesn't separate speakers, so the prompts only attribute things to people when the dialogue makes it clear.

Each step is persisted in `Lecture` (`transcript`, `segmentsData`, `summaryData`, `statusRaw`), so "Tentar novamente" (retry) skips the transcription when it already exists. A lecture stuck in `transcribing`/`summarizing` without a running task (the app was closed) is treated as interrupted in the UI and can be retried.

**Background:** `LectureProcessor` runs the pipeline in a normal `Task`, and `ContinuedProcessing` submits an iOS 26 `BGContinuedProcessingTask` (unique id under the `BGTaskSchedulerPermittedIdentifiers` wildcard in `Config/Info.plist`, plus the `processing` background mode) that mirrors its `Progress` and cancels it on expiration. On the Simulator the submit fails with "unavailable" and the work only runs in the foreground; test on a device.

**Marked moments:** while recording, "Importante" (in the app or on the Live Activity) appends the current time to `Lecture.highlights`. A mark covers the preceding `Highlight.lookback` seconds (`TranscriptSegment.isHighlighted`): those transcript blocks go to the AI with ⭐, and it flags the resulting key points with `important`.

**Playback:** the transcriber stores phrase-level `TranscriptSegment`s (start/end seconds). The summary request sends the transcript as ~30 s blocks prefixed with `[123s]`, and the AI returns `startSeconds` for key points and concepts (-1 = unknown). `LectureSummary.KeyPoint` and `ReviewQuestion` also decode older plain-string summaries. `LecturePlayer` + `TranscriptView`/`AudioPlayerBar` (PlaybackViews.swift) play the recording from a tapped phrase or summary item.

## Folders

`Folder` (SwiftData) groups lectures and can be nested (`parent` / `subfolders`). `Lecture.folder == nil` means "Sem pasta" (unfiled). A subfolder inherits kind and language from its parent unless it sets its own (`recordingKind`, `recordingLanguage`); review and the study guide use `allLectures` (subfolders included). Delete folders with `dissolve(in:)`, which moves their lectures and subfolders up one level. `LibraryView` is the root screen (top-level folders + unfiled lectures); `FolderView` lists one folder's subfolders, then its lectures; both reuse `FolderRows` (rename, move into another folder, delete; `FolderNaming` alert for create/rename), `LectureRows` (row, long-press "Mover para" menu showing folder paths, delete) and `RecordLectureButton`. New stored properties on the models need a default value (or must be optional) so SwiftData can migrate existing data.

**Study:** the library's search (`LectureSearchResults`) scans titles, summaries and transcript phrases in memory. `FlashcardsView` builds cards from review questions (question → answer) and concepts, for one lecture or a whole folder. Paid AI calls only run when the user taps a button:
- `LectureChatView` ("Perguntar"): questions about one lecture, answered from its timestamped transcript (sent as the cacheable `context`, with the last messages as history). Saved in `Lecture.chatData`; each answer can play from its `startSeconds`.
- `StudyGuideView` ("Guia para a prova"): one guide per folder built from the lectures' summaries, not transcripts. Saved in `Folder.studyGuideData` with the lecture titles it numbered, so it can say when newer lectures are missing.
- Export (`DocumentExport.swift`): summaries and guides are laid out once as `ExportDocument` blocks and shared as Markdown text or as a PDF rendered from HTML with `UIPrintPageRenderer` (A4, only when actually shared).

**Class schedule:** `Folder.scheduleData` holds weekly `ClassTime`s (`ScheduleEditorView`). During a class, or up to 15 minutes before, the home screen's record button, Siri and the Control Center control record into that folder (`Folder.inClass`). The folder is captured in a `RecordingRequest` when recording starts: use `fullScreenCover(item:)`, because a `@State` set together with an `isPresented` flag reaches the cover stale.

**Shortcuts:** `LectureShortcuts` (AppShortcutsProvider) exposes "Gravar aula" to Siri, Spotlight and the Action button. On the iOS 26.5 simulator with Xcode 27 metadata, running it from Spotlight fails with "couldn't find the AppShortcutsProvider"; the Control Center control (same intent, run directly) works.

## Storage

- Audio: `Documents/Recordings/<uuid>.aac` (ADTS; lectures recorded before were `.m4a`). `Lecture` stores only the file name, because the container path changes between installs. ADTS stays readable if the app is killed mid-recording; an `.m4a` is unreadable until `stop()` writes its index.

**Recording session:** the active recording lives in `RecordingSession.shared` (not in a view's `@State`), and `LibraryView` presents `RecordingView` from the root with `fullScreenCover(item:)`, so it comes back if the system rebuilds the UI during a long background recording. Recording buttons, Siri and the control all call `RecordingSession.begin(folder:)`. While recording, the file name, folder, language and marks are kept in `UserDefaults` (`recordingInProgress`). At launch, `recoverInterruptedRecordings` turns audio files no lecture points to into lectures (deleting a lecture or discarding a recording removes its file, so leftovers are always interrupted recordings) and ends Live Activities left behind.
- API keys: one per provider in the Keychain (`KeychainStore`), entered in Ajustes (Settings). Never hardcode them.
