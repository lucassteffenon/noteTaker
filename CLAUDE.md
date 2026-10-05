# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal iOS app (SwiftUI, iOS 26+) for recording university lectures and getting a study summary. UI strings are in Brazilian Portuguese; code and comments are in English. Single user, no backend: everything is stored on the device.

## Commands

```bash
# Build for the simulator
xcodebuild -project NoteTaker.xcodeproj -scheme NoteTaker -destination 'generic/platform=iOS Simulator' build
```

There are no tests yet. The project uses file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`): any `.swift` file added under `NoteTaker/` is compiled automatically, so `project.pbxproj` doesn't need editing. Build settings and Info.plist keys (`INFOPLIST_KEY_*`) live in `project.pbxproj`; `Config/Info.plist` only holds `UIBackgroundModes = audio`, which lets recording continue with the screen locked.

## Pipeline

`RecordingView` → `AudioRecorder` (AAC, 16 kHz mono) → a `Lecture` is saved (SwiftData) → `LectureProcessor.process` runs:

1. **Transcription** – `LectureTranscriber` uses Apple's `SpeechAnalyzer`/`SpeechTranscriber` (on-device, pt-BR). The locale must be reserved with `AssetInventory.reserve(locale:)` before the model is installed. **It doesn't work on the Simulator** (`SpeechTranscriber.isAvailable == false`), so test on a real iPhone, or run the same code from a Swift script on macOS 26.
2. **Summary** – `Summarizer` calls the Claude Messages API over raw HTTP (there is no official Swift SDK): model `claude-opus-5-5`, structured outputs (`output_config.format` with a JSON schema) and `fallbacks: "default"` (beta header `server-side-fallback-2026-07-01`). The JSON schema in `Summarizer.schema` must stay in sync with `LectureSummary`.

Each step is persisted in `Lecture` (`transcript`, `summaryData`, `statusRaw`), so "Tentar novamente" (retry) skips the transcription when it already exists. A lecture stuck in `transcribing`/`summarizing` without a running task (the app was closed) is treated as interrupted in the UI and can be retried.

## Storage

- Audio: `Documents/Recordings/<uuid>.m4a`. `Lecture` stores only the file name, because the container path changes between installs.
- Anthropic API key: Keychain (`KeychainStore`), entered in Ajustes (Settings). Never hardcode it.
