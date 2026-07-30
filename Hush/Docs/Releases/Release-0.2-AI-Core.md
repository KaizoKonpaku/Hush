# HUSH 0.2 AI Core

## Summary
This milestone focuses on making HUSH feel more coherent as an AI product. Provider setup, model selection, and assistant defaults should become easier to understand and more reliable to operate.

## Highlights
- Tightened provider setup and validation flow
- Improved clarity between account configuration and model behavior
- Reduced ambiguity in intelligence-related settings

## AI & Providers
- Refined the boundary between `Accounts` and `Intelligence`
- Improved model selection defaults and fallback behavior
- Preserved a clean runtime seam so mock and real integrations can swap without rewriting the assistant UI

## Live, Text, and Capture
- Improved baseline consistency between text and capture-driven requests
- Reduced confusion around default behavior and mode expectations

## Stealth & Privacy
- Ensured AI configuration changes still respect privacy and cloud-usage expectations

## Fixes
- Reduced settings overlap between provider connections and AI behavior
- Improved copy around validated models and saved selections

## Known Issues
- First-party provider support is still pending
- Some local/on-device intelligence options may remain partially implemented

## Notes for Internal Review
- QA should focus on provider validation, model selection persistence, and fallback behavior
