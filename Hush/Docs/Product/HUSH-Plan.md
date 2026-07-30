# HUSH

## Product Summary
HUSH is a macOS AI app built around two surfaces that serve different moments of use.

- The overlay is the fast surface. It stays close, can remain low-visibility, and handles quick interaction without forcing the full app forward.
- The app window is the complete surface. It brings together Hush, Assistant, Sessions, and Settings in a single place for longer work.

HUSH is not only a chat app. It is an assistant that can listen, read, capture, respond, and disappear when discretion matters.

## Product Promise
HUSH should feel:

- Immediate when the user wants help now
- Quiet when the user does not want attention
- Native to macOS rather than web-like
- Context-aware without feeling invasive
- Private by default, with stealth as a core capability

## Core Surfaces
### Overlay
The overlay is the primary ambient interaction layer.

- Opens quickly and stays available above other work when needed
- Supports Live, Text, and Capture entry points
- Can present transcript, prompt entry, captures, and generated answers
- Supports stealth-oriented display behavior such as low visibility, passthrough, and reduced system presence
- Should never feel overloaded with settings or navigation

### App Window
The app window is the full workspace.

- Hosts durable workflows that do not fit the lightweight overlay
- Preserves the current top-level routing structure
- Remains the place for deeper review, session management, and settings

## Workspace Areas
### Hush
The Hush area is for HUSH-specific control and product identity.

- Entry point for app-specific workflows
- Houses product-led actions that do not belong in generic chat
- Reflects stealth, capture, and system-aware behavior more strongly than the Assistant area

### Assistant
The Assistant area is the main AI work surface.

- Used for normal chat, multimodal prompts, and result review
- Connects to providers and models selected in settings
- Receives routed session history from Sessions

### Sessions
Sessions store conversation history and recall.

- Shows prior interactions
- Reopens current and previous threads
- Bridges memory and transcript retention strategy

### Settings
Settings remain a separate area with the current sidebar topology unchanged.

- The sidebar structure stays intact
- Future cleanup should focus on the options inside each page
- Pages should become clearer, smaller, and more intentional

## Modes
### Live
Live mode listens to the microphone, system audio, or both, then responds based on what was said.

- Real-time transcription is visible while listening
- The app should distinguish between system audio and the user's speech well enough to remain useful
- Responses are generated after speech pauses or the exchange ends
- Live should optimize for speed, clarity, and low friction

### Text
Text mode is the general-purpose AI chat mode.

- Standard prompt and answer flow
- Supports streaming responses
- Should remain the most predictable and broadly useful mode

### Capture
Capture mode sends screenshots or files through AI.

- Supports quick capture from the overlay
- Helps with visual understanding and contextual problem solving
- Should work as a lightweight bridge between the screen and the assistant

## Stealth as a First-Class Capability
Stealth is a defining part of HUSH, not an optional novelty.

HUSH should be able to reduce its visibility across:

- screen presence
- Dock and app switcher presence
- Mission Control and Stage Manager visibility
- screen capture and sharing surfaces
- notifications and recent-item traces

Stealth features should default toward safety when they materially reduce exposure, but they should not make the product confusing or fragile.

## Provider Architecture
HUSH now routes assistant requests through a live provider runtime instead of a built-in mock responder.

### Current model
- OpenAI is the active live provider path
- Model slots are backed by validated account state and discovered model availability
- Requests stay unavailable until a live provider is configured

### Planned model
- Future provider integrations can sit behind the same app-facing runtime boundary
- Provider capability expansion should remain isolated from feature-layer UI code
- Unsupported providers should fail clearly rather than silently falling back

## Product Principles
- Keep the overlay lightweight and immediate
- Keep the app window organized around durable work
- Treat stealth as part of the product identity
- Hide complexity until it is relevant
- Prefer intent-based settings over technical plumbing
- Make advanced controls available without making them the default experience

## Settings Direction
The settings redesign must preserve the existing sidebar pages while simplifying the content within them.

- No sidebar restructuring in this phase
- Remove redundant controls inside pages
- Move rare controls into page-local advanced sections
- Show settings only when they matter
- Keep privacy-sensitive defaults conservative

## Roadmap
### Foundation
- tighten product language and internal documentation
- clean the settings content model without changing navigation
- reinforce the separation between overlay and app window responsibilities

### Provider Maturity
- stabilize provider connection flow
- improve model selection clarity
- document user-provided providers versus future first-party support

### Live Mode Maturity
- improve speech handling and transition timing
- refine source selection and listening defaults
- strengthen latency and reliability expectations

### Stealth Hardening
- make stealth behavior feel deliberate rather than experimental
- reduce discoverability on shared screens and system surfaces
- tune defaults to balance usability and discretion

### Release Readiness
- complete checklist-driven polish
- align changelog, release notes, and milestone status
- verify that HUSH reads as one coherent product across docs and UI

## Success Criteria
The product direction is working when:

- a new engineer can understand HUSH without reverse-engineering the codebase
- a designer or implementer can simplify settings without touching sidebar topology
- stealth, live, text, and capture all read as one system rather than disconnected features
- release notes and changelog entries can describe progress in a consistent way
