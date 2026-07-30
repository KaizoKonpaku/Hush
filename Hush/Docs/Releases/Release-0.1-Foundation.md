# HUSH 0.1 Foundation

## Summary
This milestone establishes the internal shape of HUSH as a two-surface macOS product. The overlay and app window now have a clearer role in the product story, and the documentation baseline is in place for future implementation work.

## Highlights
- Defined HUSH as an AI app built around an overlay and a full app window
- Clarified the role of Hush, Assistant, Sessions, and Settings
- Added a planning and release documentation system for the team

## AI & Providers
- Documented the current external-provider approach
- Left room for a future provider layer while keeping the app-facing runtime boundary flexible

## Live, Text, and Capture
- Defined Live, Text, and Capture as the three primary user-facing modes
- Established their intended product roles for future refinement

## Stealth & Privacy
- Positioned stealth as a core capability rather than optional polish
- Documented the expectation that privacy-sensitive defaults should remain conservative

## Fixes
- Resolved ambiguity around settings cleanup by keeping the existing sidebar topology intact

## Known Issues
- Several settings still expose bloated or speculative options in the current implementation
- Hush-specific workflows still need stronger definition relative to the Assistant area

## Notes for Internal Review
- Use this milestone as the baseline for UI cleanup, settings refinement, and roadmap sequencing
