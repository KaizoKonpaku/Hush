# Validation

## Environment

Validated on 2026-08-30 using an Apple M4 Mac mini with 16 GB unified memory, macOS 27 build `26A5421a`, and Xcode 27 beta build `27A5228h`. Device SDKs are version 27. Dependency versions are locked in `Package.resolved`.

## Results

| Check | Result |
| --- | --- |
| macOS arm64 Debug build and automated tests | Passed |
| macOS arm64 optimized Release build | Passed |
| iOS / iPadOS generic device build | Passed, including embedded Watch app |
| iOS arm64 generic simulator build | Passed using `HushSimulator` |
| visionOS generic device build | Passed |
| tvOS generic device build | Passed |
| watchOS generic device build | Passed |
| Real Apple Foundation Models generation on Mac | Passed, nonempty response and reported usage |
| Real MLX download and generation on Mac | Passed with `mlx-community/Qwen3-0.6B-4bit` |
| MLX follow-up cache reuse | Passed with nonzero cached prompt tokens |
| MLX mid-response cancellation and immediate restart | Passed |
| Mac Release bundle signing | Local ad-hoc signature with sandbox and hardened runtime; strict verification passed |
| Mac application launch | Launched from `~/Applications/Hush.app` on the validation Mac |
| Interactive visual validation | Blocked: the Mac was locked |

The real-model test initially downloaded and checksum-verified the approximately 337 MB Qwen installation. Subsequent tests reuse that verified installation under the temporary `Hush-Model-Validation` directory. Model weights are not checked into Git. The short arithmetic prompts validate the execution path, not model quality or sustained performance.

The full opt-in suite passed **30 tests in five suites**, including both real-model tests. Automated coverage includes conversation identity during streaming, duplicate-submit exclusion, partial-response cancellation, retry normalization, draft restoration, atomic persistence, stale-write protection, corrupt-library preservation, fresh history, backup exclusion, attachment cleanup, deletion while history is disabled, failed-save safety, model-removal/generation exclusion, model path traversal and symlink rejection, checksums, fully staged download reuse, Core AI bundle requirements, and Watch packet validation.

## Reproduce

Normal tests do not download or run models. Use the main `Hush` scheme:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project Hush.xcodeproj -scheme Hush -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/Hush27 \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -skipPackagePluginValidation test CODE_SIGNING_ALLOWED=NO
```

To opt into the real-model tests as well, substitute `-scheme HushModelValidation`. The Apple test is enabled only when the OS reports its local model available. The MLX test downloads its small test model on first use, then checks generation, follow-up cache reuse, cancellation, restart, and unload.

For platform builds, use the same command structure with `build` instead of `test`, the scheme/destination below, and a distinct derived-data directory per platform:

| Scheme | Destination | Derived Data |
| --- | --- | --- |
| `Hush` | `platform=macOS,arch=arm64` | `build/Hush27` |
| `Hush` | `generic/platform=iOS` | `build/Hush27Device` |
| `HushSimulator` | `generic/platform=iOS Simulator` | `build/Hush27iOS` |
| `Hush` | `generic/platform=visionOS` | `build/Hush27Vision` |
| `HushTV` | `generic/platform=tvOS` | `build/Hush27TV` |
| `HushWatch` | `generic/platform=watchOS` | `build/Hush27Watch` |

For optimized Mac builds, select `-configuration Release`. Review/trust the pinned MLX CUDA plugin before using the per-command plugin-validation flag; no global setting is disabled. See the [README](../README.md).

Local logs and `.xcresult` bundles are retained under ignored `build/` directories. `test-final.log` records the full opt-in suite. Device build logs use `build-device.log`, `build-simulator.log`, `build-vision.log`, `build-tv.log`, and `build-watch.log`; `build-macos-release.log` records Release compilation.

## Remaining QA

- Unlock the Mac and inspect the actual glass appearance, light/dark modes, native focus/press feedback, and Reduce Motion. Resize both windows repeatedly, grow/shrink the composer, invoke Command-comma, switch models, open attachments, cancel a response, and navigate during streaming. No visual result is claimed while the screen is inaccessible.
- Test iPhone/iPad touch targets, keyboard avoidance, Dynamic Type, rotation, Files permissions, and background/foreground behavior on physical devices. The physical iPhone was unavailable during this run.
- Validate imported Core AI inference with real compiled language and vision bundles. Import rejection and SDK integration were tested; actual Core AI bundle inference was not.
- Exercise image understanding, real PDFs, microphone permissions, speech-asset installation, and dictation with representative user files and audio. Those paths compile but were not interactively verified.
- Test paired iPhone/Watch streaming, loss of reachability, cancellation, and background expiration. Watch protocol tests are not a substitute for paired-device testing.
- Test tvOS remote focus, inference performance, model storage eviction, and large-screen layout on hardware. Vision requires spatial UI and input testing on a headset. Those targets were compile-validated, not run on physical hardware.
- Complete distribution signing/provisioning, final platform icon packaging, model-license review, accessibility testing, and App Store/notarization validation before treating this as a distributable release.

## Known Constraints

The current beta's Core AI framework is not in the simulator SDK. Apple SystemLanguageModel does not provide the same on-device runtime on TV or Watch. Watch generation deliberately runs on the paired iPhone and never claims Watch-local inference.

The reviewed `swift-huggingface` platform fix is still an unmerged upstream revision. The pinned MLX dependency emits C++ language-extension warnings; they were not suppressed or patched in the dependency checkout. The locked-session test host also logged App Intents `linkd` registration connection failures while the tests themselves passed. Shortcuts still need interactive validation.

The locally installed Mac app is ad-hoc signed for development, not notarized for distribution. Build success and a successful launch do not establish complete cross-platform runtime or visual correctness.

As requested, accessible old `current-session.json`, `sessions.json`, and archived session JSON files were removed from this host's non-sandbox Hush storage. The old protected sandbox container could not be inspected through the terminal; no claim is made that every old file there was erased. The new app never reads or imports either legacy store.
