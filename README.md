# Hush

A native, local-first AI workspace for Apple silicon and OS 27. SwiftUI, native glass, Apple Foundation Models, MLX, and Core AI. No web wrapper, cloud inference backend, provider accounts, or older-OS compatibility layer.

This is the 2.0 rewrite. It starts with a fresh library and does not import conversations or settings from Hush 1.x.

## The App

- A Together-inspired native workspace with adaptive navigation, semantic teal, SF Symbols, and glass reserved for controls. The bottom composer has a rounded field and circular attach/send controls, without a second background panel.
- A Mac floating Quick Chat window, menu bar access, native Settings, and keyboard commands. SwiftUI owns window layout; there is no AppKit frame-measurement/resize loop.
- Streaming conversations with cancellation, retry, per-conversation drafts, pinning, search, and text export. Generation remains attached to its original conversation when you navigate elsewhere.
- Hugging Face model discovery, model cards, licenses, revision-pinned downloads, integrity verification, and a local model library. Public models need no token; gated repositories can use a Keychain-stored read token.
- Images, PDFs, and text files as local context. Vision models receive images; text-only models can use extracted image text. SpeechAnalyzer provides explicit, on-device dictation with a 60-second recording limit.
- Real token counts, first-token latency, response throughput, MLX allocations, hardware information, and memory policy controls. No simulated usage meters or benchmark scores.

## Platforms

Every target requires **27.0 or newer**. Hardware, model architecture, language, region, and available memory still determine what can run.

| Platform | Native Experience | Inference |
| --- | --- | --- |
| macOS | Workspace, Quick Chat, menu bar, Settings, App Intents | Apple On-Device, MLX/Metal, imported Core AI |
| iOS / iPadOS | Adaptive workspace, Files attachments, dictation, App Intents | Apple On-Device, MLX/Metal, imported Core AI |
| visionOS | Spatial workspace using native glass backgrounds | Apple On-Device, MLX/Metal, imported Core AI |
| tvOS | Remote-first chat, model discovery, device information | Small local MLX models; TV storage is evictable |
| watchOS | Short questions and streamed answers | Paired iPhone's on-device Apple model, **not** inference on Watch |

Apple does not expose identical model or UI capabilities on every platform. The Watch companion says where inference runs and does not copy the phone's conversation history. TV conversations are session-only.

## Models and Hardware

**Apple On-Device** uses the OS 27 Foundation Models API, including vision attachments, context size, token accounting, and streaming. Apple Intelligence must be enabled and its system assets ready. Hush does not fall back to Private Cloud Compute or a remote provider.

**MLX** loads supported language/vision architectures from verified local safetensors installations. CPU-side tokenization and Metal GPU kernels use Apple silicon's unified memory. Follow-up turns reuse the KV cache when model, settings, and history match. Unsupported architectures fail explicitly; a Hugging Face listing is not a guarantee of compatibility.

**Core AI** accepts complete exported `llm` or `vlm` bundles from Apple's model recipes. A bundle must contain `metadata.json`, its referenced `.aimodel` assets, and an embedded tokenizer with `tokenizer.json` and `tokenizer_config.json`. The compiled model variant determines CPU, GPU, or Neural Engine execution. Hush never downloads missing tokenizer files during inference.

**Maximum** uses up to Metal's recommended working-set allowance, constrained by a system-memory reserve. Low Power Mode reduces the allowance; critical thermal state stops generation. This is not an unsafe physical-memory override or a promise to run every processor simultaneously. Smaller quantized models are appropriate for phones and Apple TV.

Model weights are not bundled with the app or committed to this repository. Check each model's license before using or redistributing it.

## Build

Use an Apple silicon Mac with Xcode 27 and the corresponding OS 27 SDKs. The rewrite was validated against Xcode beta build `27A5228h`; beta APIs and dependency revisions can change.

Open `Hush.xcodeproj` and choose a scheme:

| Scheme | Purpose |
| --- | --- |
| `Hush` | macOS, physical iOS/iPadOS, and physical visionOS |
| `HushSimulator` | iOS / visionOS simulator UI and MLX build; no Core AI framework |
| `HushTV` | Apple TV |
| `HushWatch` | Watch companion, also embedded in the iOS app |
| `HushModelValidation` | Opt-in tests that exercise real models on Mac |

The installed beta's simulator SDK does not contain Core AI. The separate simulator target keeps that missing framework out of its dependency graph; it is not an older-OS fallback.

Unsigned local validation:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project Hush.xcodeproj -scheme Hush \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/Hush27 \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -skipPackagePluginValidation test CODE_SIGNING_ALLOWED=NO
```

The per-command plugin flag follows review of the pinned MLX package's CUDA build plugin, which does no CUDA work on Apple platforms. In Xcode, review and trust that plugin explicitly. No global plugin-validation setting is changed.

For signed installation, select your development team. An unsigned device build is a compile check, not a deployable iPhone/Watch release. See [validation](Documentation/Validation.md) for commands, results, and remaining device QA.

## Privacy and Storage

New conversations use `Application Support/HUSH/LocalWorkspace` inside the app's storage domain, marked as excluded from system backups. TV uses its cache directory. Old session formats are never loaded. Files are local JSON and attachment assets, not application-level encrypted storage. OS device security still matters.

History saving can be disabled. Existing saved conversations remain until explicitly deleted; deletion also removes their unshared attachments after the library save succeeds. Unreferenced attachments from a previous session are pruned on startup. Model downloads are staged separately and become runnable only after every file verifies.

Network requests are limited to discovery/downloads, optional model access, and OS-managed language/model asset installation. Prompts and attachments are not submitted to an inference server. Explicit Share actions and Watch requests are user-directed exceptions to remaining within one app/device.

## Engineering

Read [architecture and invariants](Documentation/Architecture.md), [validation](Documentation/Validation.md), and [the changelog](CHANGELOG.md).

The dependency lockfile is intentional. In particular, `swift-huggingface` is pinned to the reviewed, **unmerged** platform fix in [upstream PR 58](https://github.com/huggingface/swift-huggingface/pull/58). Its released version referenced unavailable OAuth presentation APIs on tvOS. Replace the pin with an upstream release once that fix is included; no dependency source is vendored or locally patched.

## Primary References

- [WWDC26 sessions](https://developer.apple.com/videos/wwdc2026/)
- [WWDC26 Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 MLX](https://developer.apple.com/videos/play/wwdc2026/232/)
- [WWDC26 Core AI](https://developer.apple.com/videos/play/wwdc2026/326/)
- [WWDC26 SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)
- [Apple Core AI model recipes](https://github.com/apple/coreai-models)
- [MLX Swift language models](https://github.com/ml-explore/mlx-swift-lm)
- [Hugging Face Hub API](https://huggingface.co/docs/hub/api)
