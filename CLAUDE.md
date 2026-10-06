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

There are no tests yet. The project uses file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`): any `.swift` file added under `NoteTaker/` is compiled automatically, so `project.pbxproj` doesn't need editing. Build settings and Info.plist keys (`INFOPLIST_KEY_*`) live in `project.pbxproj`; `Config/Info.plist` only holds `UIBackgroundModes = audio`, which lets recording continue with the screen locked.

## Pipeline

`RecordingView` → `AudioRecorder` (AAC, 16 kHz mono) → a `Lecture` is saved (SwiftData) → `LectureProcessor.process` runs:

1. **Transcription** – `LectureTranscriber` uses Apple's `SpeechAnalyzer`/`SpeechTranscriber` on-device, in the lecture's language (`AppLanguage`: pt-BR or en-US). The language is chosen in Ajustes and copied into `Lecture.languageRaw` when recording starts, so retries keep using it. The summary language is a separate setting, passed to `SummaryPrompt.system(for:)`. The locale must be reserved with `AssetInventory.reserve(locale:)` before the model is installed. **It doesn't work on the Simulator** (`SpeechTranscriber.isAvailable == false`), so test on a real iPhone, or run the same code from a Swift script on macOS 26.
2. **Summary** – the user picks the provider in Ajustes (`SummaryProvider`: Claude, OpenAI or Gemini, stored in `UserDefaults`). Each one implements the `Summarizer` protocol over raw HTTP and asks for JSON output using the same prompt and schema (`SummaryPrompt`, which must stay in sync with `LectureSummary`):
   - `ClaudeSummarizer`: Messages API, `output_config.format`. On Opus 5.5 / Sonnet 5.5 it also sends `effort` and `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`); Haiku 4.5 rejects both.
   - `OpenAISummarizer`: Responses API, `text.format` with a strict `json_schema`.
   - `GeminiSummarizer`: `generateContent`, `responseJsonSchema`. The key goes in the `x-goog-api-key` header, never in the URL.

   All three APIs return errors as `{"error": {"message": ...}}`, which `SummaryHTTP.post` handles in one place. The models offered per provider (cheapest first, which is the default) and their estimated cost per 1h30 lecture live in `SummaryProvider.models`; the user picks one in Ajustes.

Each step is persisted in `Lecture` (`transcript`, `summaryData`, `statusRaw`), so "Tentar novamente" (retry) skips the transcription when it already exists. A lecture stuck in `transcribing`/`summarizing` without a running task (the app was closed) is treated as interrupted in the UI and can be retried.

## Folders

`Folder` (SwiftData) groups lectures, one level only. `Lecture.folder == nil` means "Sem pasta" (unfiled). The relationship uses `deleteRule: .nullify`, so deleting a folder keeps its lectures. `LibraryView` is the root screen (folders + unfiled lectures); `FolderView` lists one folder; both reuse `LectureRows` (row, long-press "Mover para" menu, delete) and `RecordLectureButton`, which passes the folder to `RecordingView`. New stored properties on the models need a default value (or must be optional) so SwiftData can migrate existing data.

## Storage

- Audio: `Documents/Recordings/<uuid>.m4a`. `Lecture` stores only the file name, because the container path changes between installs.
- API keys: one per provider in the Keychain (`KeychainStore`), entered in Ajustes (Settings). Never hardcode them.
