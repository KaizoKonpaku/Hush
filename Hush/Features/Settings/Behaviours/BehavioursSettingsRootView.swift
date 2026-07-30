import SwiftUI

extension MainWindowView {
    var behavioursSettings: some View {
        Form {
            Section("Live") {
                liveBehaviourControls
            }

            Section("Responses") {
                textBehaviourControls
            }

            Section("Capture") {
                captureBehaviourControls
            }

            Section("Stealth") {
                stealthBehaviourControls
            }

            Section {
                explainedToggle(
                    "Confirm actions",
                    description: "Asks before HUSH runs actions that change files or system state.",
                    isOn: $confirmActions
                )
                explainedPicker(
                    "Filesystem actions",
                    description: "Choose how HUSH handles file-related actions.",
                    selection: $behavioursAllowFilesystem
                ) {
                    Text("Prompt").tag("prompt")
                    Text("Allow").tag("allow")
                    Text("Never").tag("off")
                }
                explainedPicker(
                    "Network actions",
                    description: "Choose how HUSH handles network-related actions.",
                    selection: $behavioursAllowNetwork
                ) {
                    Text("Prompt").tag("prompt")
                    Text("Allow").tag("allow")
                    Text("Never").tag("off")
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("These controls are best kept out of the main flow unless you need more explicit safety boundaries.")
            }
        }
        .settingsPageLayout()
    }

    @ViewBuilder
    func behaviourSettingsView(for page: BehaviourSettingsPage) -> some View {
        switch page {
        case .startup:
            startupBehaviourSettings
        case .overlay:
            overlayBehaviourSettings
        case .stealth:
            stealthBehaviourSettings
        case .live:
            liveBehaviourSettings
        case .text:
            textBehaviourSettings
        case .capture:
            captureBehaviourSettings
        }
    }

    var startupBehaviourSettings: some View {
        Form {
            Section {
                startupBehaviourControls
            }
        }
        .settingsPageLayout()
    }

    var overlayBehaviourSettings: some View {
        Form {
            Section {
                overlayBehaviourControls
            }
        }
        .settingsPageLayout()
    }

    var stealthBehaviourSettings: some View {
        Form {
            Section {
                stealthBehaviourControls
            }
        }
        .settingsPageLayout()
    }

    var liveBehaviourSettings: some View {
        Form {
            Section {
                liveBehaviourControls
            }
        }
        .settingsPageLayout()
    }

    var textBehaviourSettings: some View {
        Form {
            Section {
                textBehaviourControls
            }
        }
        .settingsPageLayout()
    }

    var captureBehaviourSettings: some View {
        Form {
            Section {
                captureBehaviourControls
            }
        }
        .settingsPageLayout()
    }

    @ViewBuilder
    var startupBehaviourControls: some View {
        explainedPicker(
            "Launch presentation",
            description: "Choose whether HUSH opens the window, the overlay, or both at launch.",
            selection: $generalLaunchPresentation
        ) {
            Text("Window").tag(LaunchPresentation.window.rawValue)
            Text("Overlay").tag(LaunchPresentation.overlay.rawValue)
            Text("Window and Overlay").tag(LaunchPresentation.windowAndOverlay.rawValue)
        }
        explainedToggle(
            "Restore window locations",
            description: "Reopens Overlay, Sessions, and Settings where you left them.",
            isOn: $generalRestoreWindowLocations
        )
    }

    @ViewBuilder
    var overlayBehaviourControls: some View {
        explainedPicker(
            "Open mode",
            description: "Choose the default mode when the overlay opens.",
            selection: $defaultMode
        ) {
            Text("None").tag("none")
            Text("Live").tag("live")
            Text("Text").tag("text")
            Text("Capture").tag("capture")
        }
    }

    @ViewBuilder
    var stealthBehaviourControls: some View {
        stealthToggle(
            "Enable Stealth Mode",
            description: "Applies stealth settings immediately.",
            isOn: $stealthEnabled
        )

        if stealthEnabled {
            stealthToggle(
                "Launch without taking focus",
                description: "Shows HUSH on startup without making it the active app.",
                isOn: $stealthLaunchWithoutFocus
            )
            stealthToggle(
                "Keep window above other apps",
                description: "Keeps HUSH windows above normal app windows.",
                isOn: $stealthStayOnTop
            )
            stealthToggle(
                "Hide from Dock and App Switcher",
                description: "Hides HUSH from the Dock and Command-Tab.",
                isOn: $stealthHideFromDock
            )
            stealthToggle(
                "Hide from Mission Control and Stage Manager",
                description: "Reduces how often HUSH appears in overview surfaces.",
                isOn: stealthHideFromOverviewSurfacesBinding
            )
            stealthToggle(
                "Hide from Window Menu",
                description: "Removes HUSH windows from the Window menu inside the app.",
                isOn: $stealthHideFromActivityWindow
            )
            stealthToggle(
                "Hide from Screen Sharing & Screenshots",
                description: "Prevents HUSH windows from appearing in captures when supported.",
                isOn: $stealthHideFromScreenCapture
            )
            stealthToggle(
                "Ignore mouse interactions",
                description: "Passes clicks through to apps behind HUSH.",
                isOn: $stealthMousePassthrough
            )
            stealthToggle(
                "Hide window shadow",
                description: "Removes the shadow so the window feels flatter and less obvious.",
                isOn: $stealthNoWindowShadow
            )

            HStack(spacing: 8) {
                Text("Window opacity")
                Slider(value: $stealthOpacity, in: 0.2...1.0)
                    .frame(minWidth: 180)

                Text("\(Int(stealthOpacity * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            stealthToggle(
                "Suppress Notification Center history",
                description: "Keeps HUSH notifications out of Notification Center history.",
                isOn: $stealthSuppressNotificationHistory
            )
            stealthToggle(
                "Suppress Recent Items",
                description: "Reduces HUSH presence in recent documents and Handoff surfaces.",
                isOn: $stealthSuppressRecentItemsAndHandoff
            )
        }
    }

    @ViewBuilder
    var liveBehaviourControls: some View {
        explainedPicker(
            "Audio source",
            description: "Choose what Live listens to.",
            selection: $liveAudioSource
        ) {
            Text("Both").tag("both")
            Text("Microphone").tag("mic")
            Text("System audio").tag("system")
        }
        explainedPicker(
            "Language",
            description: "Speech recognition language for Live mode.",
            selection: $liveLanguage
        ) {
            Text("System").tag("system")
            Text("English").tag("en")
            Text("Japanese").tag("ja")
        }
        explainedToggle(
            "Auto-listen",
            description: "Starts listening automatically in Live mode.",
            isOn: $liveAutoListen
        )
        explainedToggle(
            "Interrupt when I speak",
            description: "Stops assistant speech when your voice is detected.",
            isOn: $liveInterruptWhenSpeak
        )
        explainedToggle(
            "Reduce background noise",
            description: "Softens busy audio before transcription when supported.",
            isOn: $liveReduceNoise
        )
    }

    @ViewBuilder
    var textBehaviourControls: some View {
        explainedToggle(
            "Stream responses",
            description: "Shows answers as they generate.",
            isOn: $textStreamResponses
        )
        explainedPicker(
            "Max answer length",
            description: "Sets the default output length target.",
            selection: $textMaxAnswerLength
        ) {
            Text("Short").tag("short")
            Text("Medium").tag("medium")
            Text("Long").tag("long")
        }
        explainedToggle(
            "Render Markdown",
            description: "Formats supported responses as Markdown.",
            isOn: $textMarkdown
        )
        explainedToggle(
            "Show citations",
            description: "Includes source citations when the model provides them.",
            isOn: $textCitations
        )
    }

    @ViewBuilder
    var captureBehaviourControls: some View {
        explainedPicker(
            "Picker target",
            description: "Choose what the capture picker targets.",
            selection: $captureQuickMode
        ) {
            Text("Selection").tag("selection")
            Text("Window").tag("window")
        }
        explainedToggle(
            "Include cursor",
            description: "Includes the mouse cursor in captures.",
            isOn: $captureIncludeCursor
        )
    }
}
