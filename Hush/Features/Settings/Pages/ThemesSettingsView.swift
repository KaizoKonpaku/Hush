import SwiftUI

extension MainWindowView {
    var themesSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Text("Choose the app's overall appearance mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                explainedPicker(
                    "Accent",
                    description: "Color used for emphasis and selection.",
                    selection: $themesAccentPreset
                ) {
                    Text("Blue").tag("blue")
                    Text("Green").tag("green")
                    Text("Orange").tag("orange")
                    Text("Red").tag("red")
                    Text("Purple").tag("purple")
                    Text("Pink").tag("pink")
                    Text("Gray").tag("gray")
                }
                explainedPicker(
                    "Surface material",
                    description: "Choose a fixed solid surface, a stable medium material, or Liquid Glass when available.",
                    selection: themeMaterialStyleBinding
                ) {
                    Text("Solid").tag(InterfaceMaterialStyle.solid.rawValue)
                    Text("Medium").tag(InterfaceMaterialStyle.medium.rawValue)
                    if InterfaceMaterialStyle.isLiquidSupported {
                        Text("Liquid").tag(InterfaceMaterialStyle.liquid.rawValue)
                    }
                }
                explainedPicker(
                    "Spacing",
                    description: "Controls how airy the UI feels.",
                    selection: $themesDensity
                ) {
                    Text("Compact").tag("compact")
                    Text("Comfortable").tag("comfortable")
                    Text("Spacious").tag("spacious")
                }
                explainedToggle(
                    "Accent Action Pills",
                    description: "Uses the selected accent color for overlay action pills.",
                    isOn: $themesAccentActionPills
                )
            } header: {
                Text("Appearance")
            }
            Section {
                explainedPicker(
                    "Body font",
                    description: "Primary typeface used in chat content.",
                    selection: $themesFontFamily
                ) {
                    Text("System").tag("system")
                    Text("Monospace").tag("mono")
                    Text("Rounded").tag("custom")
                }
                explainedPicker(
                    "Text size",
                    description: "Default size for message content.",
                    selection: $themesFontSize
                ) {
                    Text("Small").tag(InterfaceFontSize.small.rawValue)
                    Text("Medium").tag(InterfaceFontSize.medium.rawValue)
                    Text("Large").tag(InterfaceFontSize.large.rawValue)
                }
                explainedPicker(
                    "Line height",
                    description: "Vertical spacing between text lines.",
                    selection: $themesLineHeight
                ) {
                    Text("Tight").tag("tight")
                    Text("Normal").tag("normal")
                    Text("Relaxed").tag("relaxed")
                }
            } header: {
                Text("Typography")
            }
            Section {
                explainedPicker(
                    "Message layout",
                    description: "Choose how conversations are visually grouped.",
                    selection: $themesMessageLayout
                ) {
                    Text("Chat bubbles").tag("bubbles")
                    Text("Flat list").tag("flat")
                }
                explainedToggle(
                    "Show avatars",
                    description: "Displays speaker avatars beside messages.",
                    isOn: $themesShowAvatars
                )
            } header: {
                Text("Messages")
            }
            Section {
                explainedPicker(
                    "Markdown",
                    description: "How strongly responses should be rendered as Markdown.",
                    selection: $themesRenderMarkdown
                ) {
                    Text("Full").tag("full")
                    Text("Limited").tag("limited")
                    Text("Plain text").tag("plain")
                }
                explainedPicker(
                    "Code block theme",
                    description: "Color theme used for code blocks.",
                    selection: $themesCodeTheme
                ) {
                    Text("Xcode").tag("xcode")
                    Text("Dracula").tag("dracula")
                    Text("GitHub").tag("github")
                }
                explainedToggle(
                    "Code line numbers",
                    description: "Shows line numbers in rendered code blocks.",
                    isOn: $themesCodeLineNumbers
                )
            } header: {
                Text("Formatting")
            }
            Section {
                explainedPicker(
                    "Response animation",
                    description: "Visual style for incremental response output.",
                    selection: $themesStreamingStyle
                ) {
                    Text("Typewriter").tag("typewriter")
                    Text("Chunks").tag("chunks")
                    Text("Instant").tag("instant")
                }
                explainedToggle(
                    "Show typing indicator",
                    description: "Shows typing activity while generating text.",
                    isOn: $themesTypingIndicator
                )
            } header: {
                Text("Streaming")
            }
        }
        .settingsPageLayout()
    }
}
