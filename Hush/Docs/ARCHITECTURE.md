# HUSH Architecture (macOS 14+)

## Direction
- State-driven SwiftUI feature modules.
- No heavy view-model layer by default; keep behavior close to state + domain types.
- Explicit domain models and typed runtime errors.

## Current module structure
- `Backend`
  - `Domain/`
    - `AssistantModelCatalog.swift`
    - `ProviderAccountModels.swift`
  - `Infrastructure/`
    - `KeychainSecretStore.swift`
  - `OpenAI/`
    - `OpenAIService.swift`
  - `Accounts/`
    - `ProviderAccountStore.swift`
  - `Runtime/`
    - `IntelligenceRuntime.swift`
- `Features/MainWindow`
  - `MainWindowView.swift`
  - `MainWindowStore.swift`
  - `MainWindowSidebar.swift`
  - `MainWindowDetail.swift`
  - `MainWindowToolbar.swift`
  - `MainWindowTheme.swift`
  - `MainWindowRouting.swift`
- `Features/Settings`
  - `SettingsDetailRouter.swift`
  - `Pages/`
  - `Behaviours/`
  - `Components/`
- `Features/Overlay/Domain`
  - `OverlayProcessEntry.swift`
  - `OverlayError.swift`
- `Features/Overlay/Services`
  - `OverlayResponseService.swift`
- `Features/Overlay/Components`
  - `OverlayNotificationBar.swift`
- `Features/Overlay/OverlayView.swift`
- `Core/Sessions`
  - `SessionHistoryModels.swift`
  - `SessionHistoryStore.swift`
- `Features/Assistant`
  - `AssistantWindowView.swift`
  - `AssistantWorkspace.swift`
- `Features/Sessions`
  - `SessionsWindowView.swift`

## Backend responsibilities
- `Backend/Domain` holds provider-facing domain models and model catalog metadata used by Settings and runtime selection.
- `Backend/Infrastructure` owns local persistence primitives such as Keychain secret storage.
- `Backend/OpenAI` contains direct OpenAI HTTP integration for model discovery, Responses API requests, and organization usage/cost status lookups.
- `Backend/Accounts` owns saved provider account records, validation, migration from earlier storage, and publishable account/model state for the UI.
- `Backend/Runtime` is the feature-facing entry point that resolves the selected model and routes requests to supported live providers.

## Runtime flow
- Assistant and overlay features call `IntelligenceRuntime`.
- `IntelligenceRuntime` resolves the selected model from `ProviderAccountStore`.
- `ProviderAccountStore` supplies the active account, models, and locally stored secrets.
- `OpenAIService` performs live OpenAI requests when an OpenAI account is configured.
- Features stay focused on view state and interaction flow instead of directly owning provider API logic.

## Window model
- Main app window: hosts Hush, Assistant, Sessions, and Settings pages inside a single split-view shell.
- Overlay: primary floating interaction surface (Live/Text/Capture/Process).
- Sessions: a section inside the main app window that routes selected sessions into Assistant.
- Session history now migrates the legacy single `sessions.json` file into a per-session layout (`current-session.json` plus `sessions/<uuid>.json`) so pinning, search, deletion, and branching do not require rewriting one large file.
- No separate result/transcription windows.

## Error handling standard
- Represent user-facing errors as typed domain errors (`OverlayRuntimeError`).
- Map to UI-safe display state (`OverlayErrorState`).
- Render errors in a dedicated bottom bar under feature content.
- Do not silently fail for permission-denied paths.

## Security baseline
- Keep app sandbox enabled.
- Request sensitive permissions only when action is invoked.
- Surface permission-denied errors with clear guidance instead of silent no-op.

## Migration plan for remaining features
- Move each feature to the same layout: `Domain / Services / Components / FeatureView`.
- Introduce typed runtime errors per feature.
- Replace temporary placeholder behavior with service interfaces.
- Keep shared UI/theme types in `Features/Shared` only when used by multiple feature modules.
