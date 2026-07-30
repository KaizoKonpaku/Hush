# HUSH Implementation Checklist

Use this document to track product completion, polish, and blockers across the current HUSH direction.

## Now
### App Structure
- [x] Maintain dual-surface product model: overlay plus app window
- [x] Keep `Hush`, `Assistant`, `Sessions`, and `Settings` as the app window's top-level areas
- [ ] Clarify the functional role of `Hush` versus `Assistant` in the UI copy and product behavior
- [ ] Align toolbar, routing, and empty states with the product plan

### Overlay
- [x] Support overlay presentation and visibility toggling
- [x] Surface Live, Text, Capture, and result content in the overlay
- [ ] Refine the overlay so it feels lighter than the app window in every state
- [ ] Reduce visual and behavioral clutter when multiple modes are active

### Live Mode
- [x] Support microphone, system audio, and combined source selection
- [x] Show live transcript state in the overlay
- [ ] Improve response timing after speech pauses
- [ ] Improve handling when the user and another speaker alternate quickly
- [ ] Define stronger expectations for interruption, listening state, and answer generation

### Text Mode
- [x] Support general prompt and response workflow
- [x] Support streaming responses
- [ ] Tighten defaults for send behavior, answer length, and empty-state guidance
- [ ] Ensure text mode feels complete without relying on capture or live inputs

### Capture Mode
- [x] Support selection/window capture workflows
- [x] Support image/file context in runtime requests
- [ ] Clarify the product boundary between quick capture and richer file attachment flows
- [ ] Tighten capture affordances and post-capture review flow

### Settings Cleanup
- [x] Keep current settings sidebar topology unchanged
- [ ] Reduce bloated or speculative controls inside each settings page
- [ ] Move rare controls into page-local advanced sections
- [ ] Remove duplicate or weak settings that do not map to real user value

## Next
### Hush Workspace
- [ ] Define Hush-specific workflows that do not collapse into generic assistant chat
- [ ] Give the Hush area a clearer role in stealth, capture, and product-led actions

### Assistant
- [x] Route AI interactions through the shared workspace/runtime
- [ ] Improve mode transitions between overlay and full assistant view
- [ ] Align assistant defaults with the model and memory plans

### Sessions
- [x] Persist session history
- [x] Replace the single session JSON blob with a migrated per-session file layout
- [x] Reopen prior sessions into the workspace
- [x] Add session search, pinning, deletion, and branch-oriented recovery flows
- [ ] Improve session naming, scanning, and recovery flows
- [ ] Connect sessions more clearly to memory and transcript retention policy

### Providers
- [x] Support external provider validation and model discovery
- [x] Persist provider-specific model selections
- [ ] Tighten provider setup copy and validation recovery states
- [ ] Separate provider connection concerns from model-choice concerns in settings

### Memory
- [x] Persist session history separately from transient overlay state
- [ ] Define which memory behaviors are real product features versus future intent
- [ ] Simplify memory settings around user intent: retain, save, scope, reuse
- [x] Clarify transcript retention and saved context policy in Accounts and Intelligence

## Later
### Runtime Cleanup
- [x] Remove package-backed provider flow from the app target
- [x] Remove the built-in mock runtime from the assistant path
- [ ] Decide whether future real integrations return as adapters or a separate app variant

### Stealth & Privacy
- [x] Support stealth mode activation and core stealth window behaviors
- [x] Support hiding from selected system surfaces and capture paths where available
- [ ] Tune safer defaults for stealth-sensitive settings
- [ ] Reduce the number of stealth toggles exposed at once without losing capability
- [ ] Verify stealth behavior remains dependable across common macOS environments

### Permissions
- [x] Show permission status and guidance
- [ ] Improve the post-approval refresh flow for screen recording and related permissions
- [ ] Reduce setup friction for Live and Capture prerequisites

### Notifications
- [x] Support app-level notification settings
- [ ] Reconcile notification settings with stealth privacy behavior
- [ ] Reduce overlapping notification controls to a smaller, clearer model

## Fixes / Polish
- [ ] Remove settings copy that describes speculative or incomplete features as if they already exist
- [ ] Make helper text shorter and more product-led across settings
- [ ] Ensure advanced controls do not dominate first-run experience
- [ ] Standardize naming for overlay, window, live, capture, and stealth across the app
- [ ] Review default values for privacy, stealth, and clarity
- [ ] Align release notes language with in-app language

## Blocked / Depends on Package or Backend
- [ ] Any future provider implementation beyond the current live runtime
- [ ] Any real cloud sync behavior for preferences, memories, or prompts
- [ ] On-device model path if local inference support is incomplete
- [ ] Final memory architecture if future integrations change storage or context boundaries
- [ ] Any provider-specific capability expansion that depends on a restored backend layer

## Release Readiness
- [ ] Product plan stays aligned with actual implementation
- [ ] Settings content cleanup is complete without sidebar changes
- [ ] Changelog is maintained from `Unreleased`
- [ ] Release notes exist for each milestone
- [ ] Known issues are documented before beta or wider release
- [ ] QA covers overlay, app window, live mode, capture, providers, permissions, and stealth
