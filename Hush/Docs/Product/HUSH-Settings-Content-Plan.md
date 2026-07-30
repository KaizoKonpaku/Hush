# HUSH Settings Content Plan

## Direction
Keep the current settings sidebar pages. Improve only the contents of each page.

This plan is intentionally conservative about navigation and aggressive about clarity. Every page should have a single purpose, fewer sections, and fewer controls competing for attention.

## Global Rules
- Do not change the current settings sidebar topology in this phase
- Give every page a one-sentence purpose at the top of implementation notes or design review
- Limit each page to a small set of meaningful sections
- Use short, action-led labels and one-idea helper text
- Remove duplicate controls even if the current code makes them easy to keep
- Move rare or technical controls into an `Advanced` section inside the same page
- Hide settings that do not apply until the related feature, provider, or permission exists
- Prefer privacy-safe and stealth-safe defaults when tradeoffs are meaningful

## Page Plan
### General
Purpose: Control app-wide basics that are not specific to AI, stealth, or visual customization.

Keep:
- launch at login
- menu bar visibility
- launch presentation when it is framed as an app-wide startup behavior
- about/version information

Merge:
- none

De-emphasize:
- app icon style if it remains cosmetic rather than functional

Remove:
- any control that is really about navigation, AI, stealth, or themes

Recommended sections:
- `Startup`
- `App`
- `About`

### Accounts
Purpose: Manage provider connections, saved keys, and account security.

Keep:
- provider list
- connect and manage providers
- add, edit, and remove local sign-ins
- add, edit, and remove local API keys
- key reveal protection
- keychain storage
- account-change protection
- ask-again timing

Merge:
- security controls into the same page as account changes
- keep sync secondary until it exists end to end

De-emphasize:
- repeated mock-runtime explanations
- validation or provider details that belong in `Intelligence`

Remove:
- app-reopen lock language
- any option that implies cloud account systems not present in the product yet

Recommended sections:
- `Providers`
- `Security`
- `Sync`

### Intelligence
Purpose: Define which models HUSH uses and how the assistant behaves by default.

Keep:
- default model
- fast model
- advanced model
- allow cloud usage
- fallback behavior
- tone

Merge:
- local execution preferences into one compact execution section

De-emphasize:
- provider-specific sourcing details; keep these as short helper text only

Remove:
- provider connection setup
- key management

Recommended sections:
- `Models`
- `Execution`
- `Response Defaults`
- `Advanced`

### Memory
Purpose: Control what HUSH remembers, how long it keeps it, and what becomes reusable context.

Keep:
- conversation retention
- transcript saving
- memory scope
- saved context behavior

Merge:
- transcript format and export-oriented controls into one transcripts section

De-emphasize:
- storage-shape details that describe implementation instead of user intent

Remove:
- low-level storage terminology that users do not need

Recommended sections:
- `Conversation History`
- `Memory`
- `Transcripts`
- `Advanced`

### Behaviours
Purpose: Set default behavior for startup, Live, Text, Capture, and stealth mode.

Keep:
- launch presentation
- default mode
- restore window locations
- live audio source
- live language
- auto-listen
- interrupt when speaking
- text send behavior
- stream responses
- max answer length
- quick capture mode
- include cursor
- stealth enablement
- stealth defaults

Merge:
- overlap between startup behavior and general presentation into one startup group

De-emphasize:
- very rare stealth toggles that are better treated as advanced

Remove:
- controls that duplicate `Navigation`, `Notifications`, or `Themes`

Recommended sections:
- `Startup`
- `Live`
- `Text`
- `Capture`
- `Stealth`
- `Advanced`

### Navigation
Purpose: Control overlay and window placement, targeting, and interaction behavior.

Keep:
- overlay position memory
- screen targeting
- interaction and auto-hide controls
- overlay behavior that is about placement rather than concealment

Merge:
- duplicate movement controls into one placement section

De-emphasize:
- controls that are only useful for edge-case multi-display setups

Remove:
- stealth visibility options that belong in `Behaviours`
- generic app-wide startup controls

Recommended sections:
- `Placement`
- `Screen Targeting`
- `Interaction`
- `Advanced`

### Notifications
Purpose: Define when HUSH alerts the user and how visible that information should be.

Keep:
- notification enablement
- alert timing or event categories
- style
- sound
- preview level
- in-app notices

Merge:
- overlapping notification visibility toggles into fewer, clearer controls

De-emphasize:
- over-detailed in-app notification tuning if only one or two states matter

Remove:
- settings that compete with stealth privacy rules without adding real control

Recommended sections:
- `Alerts`
- `Preview & Privacy`
- `In-App`

### Themes
Purpose: Control appearance and presentation without turning the page into a style lab.

Keep:
- appearance mode
- accent choice
- material style
- density
- typography
- message layout
- avatar visibility if it materially changes readability
- markdown presentation
- streaming presentation

Merge:
- related text presentation controls into tighter typography and formatting sections

De-emphasize:
- decorative options that do not materially improve comprehension
- style combinations that create too many nearly identical outcomes

Remove:
- purely ornamental toggles that dilute the page

Recommended sections:
- `Appearance`
- `Typography`
- `Messages`
- `Formatting`
- `Advanced`

### Shortcuts
Purpose: Define keyboard control for HUSH without changing the current structural grouping.

Keep:
- existing structural grouping of shortcuts
- mode shortcuts
- capture shortcuts
- window and movement shortcuts
- results navigation shortcuts
- app shortcuts

Merge:
- label cleanup only; do not collapse the overall structure in this phase

De-emphasize:
- rarely used shortcuts that can be shown lower in each group

Remove:
- duplicate shortcut definitions

Recommended sections:
- keep the existing structural grouping, improve naming and help text only

### Components
Purpose: Expose only the UI component toggles that are genuinely user-facing and cannot live elsewhere.

Keep:
- mode visibility toggles if they affect what the overlay can expose
- export presentation choices if users explicitly act on them

Merge:
- feature-specific controls into their owning pages whenever possible

De-emphasize:
- experimental UI options
- integration toggles that are not complete or useful

Remove:
- generic visibility toggles with weak product value
- controls that duplicate `Themes`, `Behaviours`, or `Intelligence`

Recommended sections:
- `Modes`
- `Exports`
- `Advanced`

### Locations
Purpose: Manage whether HUSH uses location as context and how precise that context should be.

Keep:
- allow location context
- precision level
- privacy-aware usage explanation

Merge:
- related privacy language into one clear usage section

De-emphasize:
- location when it does not materially improve answers

Remove:
- location controls that do not affect real product behavior

Recommended sections:
- `Context`
- `Privacy`

### Permissions
Purpose: Show system access state and help the user resolve missing permissions quickly.

Keep:
- permission status visibility
- action-oriented guidance
- refresh and re-check behavior

Merge:
- permission categories into a clean status-first layout

De-emphasize:
- verbose macOS explanation once the user understands the issue

Remove:
- unrelated behavior toggles

Recommended sections:
- `System Access`
- `Live Features`
- `Management`

## Decision Matrix
### General
| Control area | Decision | Notes |
| --- | --- | --- |
| Launch at login | Keep | Core app behavior |
| Menu bar visibility | Keep | App-wide and useful |
| Launch presentation | Merge | Can remain here or Behaviours, but only one home should exist |
| App icon style | De-emphasize | Cosmetic |
| Version/build | Keep | Belongs in About |

### Accounts
| Control area | Decision | Notes |
| --- | --- | --- |
| Preferred provider | Keep | Useful for model ordering |
| Provider add/remove | Keep | Core setup flow |
| API key entry | Keep | Core setup flow |
| Validate / refresh | Keep | Core setup flow |
| Validation status | Keep | Core setup flow |
| Sync preferences | De-emphasize | Keep only if real sync exists |
| Sync memories & prompts | Remove | Reads speculative unless implemented |
| Keychain storage | Keep | Important trust setting |
| App lock / idle timeout | De-emphasize | Keep only if fully implemented |

### Intelligence
| Control area | Decision | Notes |
| --- | --- | --- |
| Default / fast / advanced model | Keep | Core AI behavior |
| On-device model toggle | Keep | Useful if local inference is real |
| Hardware usage | Merge | Keep compact |
| Cloud usage | Keep | Important privacy and routing decision |
| Fallback model | Keep | Useful resilience control |
| Tone | Keep | Helpful default behavior |
| Provider sourcing explanation | Merge | Helper text only |

### Memory
| Control area | Decision | Notes |
| --- | --- | --- |
| Retention period | Keep | Core memory decision |
| Save conversation history | Keep | Core memory decision |
| Memory scope | Keep | Core memory decision |
| Transcript save format | Merge | Keep only if export exists |
| Transcript toggles | Keep | Useful if transcripts are a real feature |
| Storage-plumbing language | Remove | Too technical |

### Behaviours
| Control area | Decision | Notes |
| --- | --- | --- |
| Startup presentation | Keep | Clear product value |
| Default mode | Keep | Clear product value |
| Restore window locations | Keep | Startup behavior |
| Live source / language / auto-listen | Keep | Core Live defaults |
| Interrupt when I speak | Keep | Core Live interaction |
| Text send behavior | Keep | Core chat behavior |
| Stream responses | Keep | Core chat behavior |
| Max answer length | Keep | Useful default |
| Quick capture target | Keep | Useful default |
| Include cursor | Keep | Useful capture behavior |
| Stealth enablement | Keep | Product identity |
| Rare stealth toggles | De-emphasize | Move lower or into advanced section |

### Navigation
| Control area | Decision | Notes |
| --- | --- | --- |
| Position restore and placement | Keep | Main reason this page exists |
| Screen targeting | Keep | Important for overlay |
| Interaction controls | Keep | Important for overlay |
| Duplication of stealth behavior | Remove | Belongs elsewhere |
| Edge-case multi-display tuning | De-emphasize | Keep lower in page |

### Notifications
| Control area | Decision | Notes |
| --- | --- | --- |
| Enablement | Keep | Core choice |
| Style and sound | Keep | Core choice |
| Preview level | Keep | Privacy-sensitive |
| In-app notices | Keep | Useful when concise |
| Overlapping visibility toggles | Merge | Reduce clutter |

### Themes
| Control area | Decision | Notes |
| --- | --- | --- |
| Appearance mode | Keep | Core visual choice |
| Accent / material / density | Keep | Useful when limited |
| Typography controls | Keep | Useful when grouped well |
| Message layout / avatars | Keep | Useful if it changes readability |
| Markdown style options | Merge | Reduce option sprawl |
| Decorative variants | De-emphasize | Avoid theme-lab feeling |

### Shortcuts
| Control area | Decision | Notes |
| --- | --- | --- |
| Existing shortcut groups | Keep | Locked by current plan |
| Labels and helper text | Merge | Improve clarity |
| Duplicates or weak shortcuts | Remove | Only if actually duplicated |

### Components
| Control area | Decision | Notes |
| --- | --- | --- |
| Mode visibility toggles | Keep | If they affect real UI |
| Export format choices | Keep | If export is user-facing |
| Generic component toggles | Remove | Too bloated |
| Cross-feature duplicate toggles | Remove | Should live with owning feature |

### Locations
| Control area | Decision | Notes |
| --- | --- | --- |
| Allow location usage | Keep | Privacy-sensitive, user-facing |
| Precision level | Keep | Privacy-sensitive, user-facing |
| Weak contextual options | De-emphasize | Only if location clearly helps |
| Non-functional location controls | Remove | Avoid noise |

### Permissions
| Control area | Decision | Notes |
| --- | --- | --- |
| Status display | Keep | Core value of page |
| Recovery guidance | Keep | Needed for macOS permissions |
| Refresh/re-check | Keep | Needed for setup flow |
| Extra unrelated controls | Remove | Keep page focused |

## Implementation Notes
- Preserve `SettingsSection` and current routing structure
- Rewrite page contents, labels, sectioning, and defaults only
- Prefer concise helper text that explains intent rather than implementation
- Use conditional visibility to avoid showing non-functional options too early
- If a feature is incomplete, either lower its prominence or remove the setting until the feature is real
