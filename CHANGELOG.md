# Changelog

All notable changes to HUSH should be recorded in this file.

The format is organized by release, with `Unreleased` at the top. Entries should describe user-facing behavior, product structure, or implementation-level changes that matter to the team.

## Unreleased
### Added
- Added a structured internal documentation set for HUSH product planning, settings refinement, implementation tracking, and release notes.
- Added milestone release note templates covering foundation, AI/provider maturity, live/stealth progress, and 1.0 readiness.

### Changed
- Defined HUSH as a dual-surface macOS product with an overlay and a full app window.
- Locked the current settings sidebar topology and redirected future settings cleanup toward the contents of each page instead of navigation changes.
- Documented a settings simplification strategy for the existing pages, including keep, merge, de-emphasize, and remove decisions.

### Fixed
- Fixed documentation ambiguity around whether settings cleanup should restructure the sidebar. It should not.

### Removed
- Removed the assumption that settings cleanup requires page consolidation in the sidebar.

### Security
- Documented stealth and privacy behavior as first-class product concerns rather than optional polish.

### Known Issues
- Several existing settings appear to describe incomplete or speculative functionality and still need implementation review.
- Some docs and roadmap notes may still need cleanup after the move to a mock-only assistant runtime.

## 1.0
### Added
- Initial HUSH release.

### Changed
- Established the first complete product surface across overlay, assistant workflows, sessions, and settings.

### Fixed
- Stabilized core app startup and workspace behavior for the initial release target.

### Removed
- Removed pre-release-only assumptions from the shipping product framing.

### Security
- Introduced the initial privacy and stealth posture for the app.

### Known Issues
- Release-specific issues to be added when the 1.0 scope is frozen.
