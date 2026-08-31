# Architecture

## Boundaries

Hush is a Swift 6, strict-concurrency app with an OS 27 minimum. Shared code is organized by responsibility rather than the previous overlay/provider feature tree.

| Area | Responsibility |
| --- | --- |
| `Domain` | Codable, Sendable conversation/model/settings records, request snapshots, stream events, context normalization, safe model paths |
| `App/WorkspaceModel` | Main-actor observable state, navigation, drafts, generation/download task ownership, and persistence coordination |
| `Intelligence/InferenceRuntime` | Serialized model routing, Foundation Models sessions, Core AI resources, context accounting, unload coordination |
| `Intelligence/MLXEngine` | Metal-backed model container, tokenization, chat-session cache, memory bounds, streaming and cancellation |
| `Models` | Hugging Face metadata, immutable manifests, file verification, staged installation, discovery/library views |
| `Storage` | Versioned atomic library, managed files, Keychain token, and local attachment extraction |
| `Design`, `Workspace`, `Chat`, `Runtime`, `Settings` | Native SwiftUI presentation; no network or inference implementation inside views |
| `HushTV` | TV-specific coordinator and focus-driven UI using shared MLX/storage/model code |
| `PhoneCompanion`, `HushWatch` | Bounded, identified WatchConnectivity requests; generation occurs on the paired iPhone |

Views observe state and submit intent. Engine implementations do not own UI state. `InferenceServing` allows lifecycle tests to control event timing without loading a model.

## Generation Invariants

1. Only one workspace generation is admitted at a time. Every request snapshots model, settings, prompt, attachments, and history.
2. Stream events carry the original conversation, response, and job identity. Navigation cannot redirect tokens into a new chat.
3. Context contains alternating completed user/assistant exchanges. Failed or unanswered exchanges are omitted; retry replaces the prior answer rather than adding a second assistant turn.
4. Input is token-budgeted before generation. Old exchanges are dropped together, with a visible status update. MLX/Core AI use a conservative 32K application context cap; images use an explicit estimate where exact counting is unavailable. Engines still enforce their own limits.
5. MLX loads only a local verified directory. Its chat cache is reused only for matching conversation, settings, and exact expected history.
6. Cancellation preserves delivered partial text, drains MLX's producer, and invalidates the partial cache. Unload cannot race a new generation. A narrowly scoped `nonisolated(unsafe)` alias bridges upstream's non-Sendable `ChatSession.synchronize`; the actor owns the session exclusively and keeps its generation lock until the producer drains.
7. Completed metrics come from actual engine usage and measured elapsed time. Throughput excludes time to the first token but remains an application-level measurement, not a standardized benchmark. MLX allocation figures do not pretend to describe Foundation Models or Core AI memory.
8. Empty model output and unavailable capabilities are explicit errors. There is no remote fallback, simulated response, automatic tool execution, or background prompt upload.

The iPhone Watch bridge has its own bounded system-model session and does not load the main workspace's transcripts. Watch protocol messages carry a version and request UUID, are size-checked, and cannot apply stale updates to a newer request.

## File and Privacy Invariants

- `LibraryStore` owns the new `LocalWorkspace` schema. There is no migration path from old conversations, provider accounts, or preferences.
- The workspace is marked as excluded from OS backups, including downloaded model weights and attachments. TV uses its inherently evictable cache domain.
- Saves use atomic replacement and monotonically increasing revisions. Stale asynchronous saves cannot overwrite a newer archive. Corrupt or unsupported archives are reported and never overwritten by a fresh empty library.
- Turning off history stops saving new changes. Explicit deletions still apply to the saved archive. Referenced attachment files are not removed if the archive save fails.
- Fresh and per-conversation drafts survive navigation. Removed attachments are deleted only when no live or persisted conversation/draft references them. Startup prunes abandoned attachment files from previous sessions.
- Hugging Face manifests require a pinned revision, bounded file list, file sizes, and self-contained configuration/tokenizer/weights. Each file is checked against SHA-256 or its Git blob hash before installation.
- Relative paths reject traversal, absolute paths, encoded path separators, and symlink components. Core AI imports reject symlinks and executable/pickle file types. Hush parses supported model data; it never executes repository Python or shell code.
- A model remains in `Downloads` until every file verifies. Completed files survive cancellation and are reverified on retry; partial individual files do not resume by byte range. The complete folder moves into `Models` atomically.
- Hub read tokens use the device Keychain. Redirected model downloads strip authorization when leaving `huggingface.co` and reject non-HTTPS redirects.
- Attachments are bounded to four files per message and 25 MB per input. Images are downsampled, PDFs are page/text limited, and OCR/transcription runs on device. Raw dictation recordings are removed after completion or cancellation.

## Native Presentation

The design follows Together's quiet native surfaces, semantic color, SF Symbols, and glass control language while retaining Hush's editorial serif identity. Native controls provide pressed, focused, disabled, and hover states.

The composer is a single flexible layout: circular attach, a growing rounded text field, and circular send/stop. There is no backdrop around the entire row. Its controls retain identity while text, dictation, and generation state change. Width comes from the parent layout, not a measured-size feedback loop. Scroll geometry is used only to decide whether a reader is near the bottom, never to resize windows.

Mac Quick Chat is a native floating `Window`; discovery actions explicitly open the main workspace. Errors follow the active window using the system's appearance state, including the separate Settings scene. New Conversation is a toolbar SF Symbol. Standard Settings and keyboard commands replace custom keyboard interception. Reduce Motion is respected; primary reading/composer text scales with Dynamic Type. Vision uses `glassBackgroundEffect` and native spatial controls because its SDK does not expose the same Liquid Glass modifiers as iOS/macOS.

## Dependencies and Limits

`Package.resolved` is part of the source of truth. Notable pins:

| Package | Revision / Version |
| --- | --- |
| `mlx-swift-lm` | `37688d2cf7d3906e08c74479c9d9949ce6b81136` |
| `mlx-swift` | `0.31.6` |
| `coreai-models` | `de31ba508895c7aa3bdcc57f8837a23f13316871` |
| `swift-transformers` | `1.3.3` |
| `swift-huggingface` | `5c608861f9712cbf71a0c420f2909f6e31bae5e1`, upstream PR 58 |

The direct MLX chat adapter intentionally avoids the upstream Foundation Models bridge that did not compile against this installed beta's metadata API. This is not a copied compatibility shim. Core AI is excluded from the simulator dependency graph because the framework is absent from that SDK.

Apple/model runtimes schedule hardware. Memory policy is an MLX allocation allowance plus conservative admission estimates, not CPU/GPU utilization control. Thermal checks and a system reserve stay enabled. Model quality, license, architecture support, peak working set, and platform asset readiness remain real constraints.

There is no GGUF/llama.cpp engine, training/fine-tuning UI, image generation, autonomous tool runner, cross-device chat sync, global hotkey daemon, or old cloud/live/stealth implementation. Platform-specific capabilities and remaining QA are recorded in [Validation](Validation.md), not hidden behind inactive controls.
