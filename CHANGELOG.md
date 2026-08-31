# Changelog

## Live Features

- Replaced record-then-transcribe dictation with OS 27 streaming speech input.
- Added local hands-free voice, sentence-streamed spoken replies, interruption, mute/end controls, and voice/rate/turn-pause preferences.
- Added per-message read aloud, pause/resume/stop, and optional automatic reading of typed responses.
- Added native live camera and ScreenCaptureKit context with explicit selection, visible previews, bounded frame processing, and per-question snapshots.
- Added message editing into preserved branches, branch-from-response, conversation renaming, and return-to-original navigation.
- Added regression tests for turn identity, stale transcripts, mute, interruption, audio conversion/playback, captured-frame sizing/orientation, and branch persistence; added a real native speech synthesis/transcription round-trip test.
- Kept the existing workspace and circular composer design. Screen capture is unavailable in the current simulator SDK; camera and voice hardware flows still require interactive device QA.

## 2.0 - OS 27 Rewrite

### Added
- Native SwiftUI workspace for macOS, iOS/iPadOS, and visionOS; dedicated Apple TV and Watch companion targets.
- Apple Foundation Models inference with OS 27 vision, context accounting, and streaming.
- MLX/Metal local inference, follow-up KV-cache reuse, safe cancellation, and device-aware memory policies.
- Hugging Face search, model metadata, revision-pinned verified downloads, local model management, and Core AI bundle import.
- Local image/PDF/text context, OCR, bounded SpeechAnalyzer dictation, App Intents, and measured runtime information.
- Lifecycle, storage, model-safety, Watch protocol, and opt-in real-inference tests.

### Changed
- Rebuilt the interface around Together-inspired native glass, semantic teal, adaptive navigation, a floating rounded composer, circular controls, and a toolbar New Conversation action.
- Replaced custom overlay frame choreography with a native resizable floating Mac window and stable SwiftUI control identity.
- Introduced an actor-based runtime and revision-aware atomic persistence. New conversations use a fresh store without importing old history.
- Added reproducible dependency pins and explicit physical-device versus simulator capability boundaries.

### Removed
- The old cloud/provider backend, provider-account UI, live/stealth pipeline, custom keyboard/window orchestration, history migration, and older-OS compatibility layers.
- Obsolete implementation plans, placeholder release documentation, and tests for deleted behavior.

### Validation
- See [Validation](Documentation/Validation.md) for verified builds, real inference results, and remaining beta/device limitations. This entry does not assert App Store or cross-device release readiness.

## 1.x

The previous macOS overlay and provider-based application is preserved in Git history. It is not part of the OS 27 runtime.
