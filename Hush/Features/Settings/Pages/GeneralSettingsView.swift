import SwiftUI

extension MainWindowView {
    var generalSettings: some View {
        Form {
            Section {
                explainedToggle(
                    "Launch at Login",
                    description: "Starts HUSH automatically when you sign in.",
                    isOn: $generalLaunchAtLogin
                )
                explainedToggle(
                    "Show Menu Bar Item",
                    description: "Keeps HUSH available from the menu bar.",
                    isOn: $generalShowInMenuBar
                )
                if generalShowInMenuBar {
                    explainedPicker(
                        "Menu Bar Item Style",
                        description: "Choose how HUSH appears in the menu bar.",
                        selection: $stealthMenuBarVisibility
                    ) {
                        Text("HUSH").tag("default")
                        Text("^-^").tag("icon")
                        Text("•").tag("neutral")
                    }
                }
            } header: {
                Text("App Basics")
            }

            Section("Startup") {
                startupBehaviourControls
            }

            Section("Overlay") {
                overlayBehaviourControls
            }

            Section {
                LabeledContent("Version") { Text("1.0 (26)").foregroundStyle(.secondary) }
                LabeledContent("Build") { Text("1").foregroundStyle(.secondary) }
            } header: {
                Text("About")
            } footer: {
                Text("Keep this page focused on launch behavior and app identity.")
            }

            Section {
                Button("Reset HUSH Preferences…", role: .destructive) {
                    isShowingPreferencesResetConfirmation = true
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("This restores UI, shortcut, prompt, and model preferences to their defaults without removing accounts or saved sessions.")
            }
        }
        .settingsPageLayout()
    }

    func resetAllPreferencesToDefaults() {
        let defaults = UserDefaults.standard

        for key in defaults.dictionaryRepresentation().keys where AppPreferenceResetSupport.shouldReset(key: key) {
            defaults.removeObject(forKey: key)
        }

        IntelligencePreferencesMigration.migrateIfNeeded(defaults: defaults)
        AssistantPromptPresetStore.shared.refresh()
        providerStore.repairStoredSelectionsIfNeeded()
        appModel.isOverlayEnabled = true
        appModel.syncRuntime(.shortcuts)
        syncRuntimeSettings()
    }
}

private enum AppPreferenceResetSupport {
    private static let resettablePrefixes = [
        "assistant.",
        "behaviours.",
        "components.",
        "general.",
        "intel.",
        "memory.",
        "nav.",
        "notif.",
        "overlay.",
        "sessions.",
        "settings.",
        "shortcuts.",
        "stealth.",
        "themes.",
    ]

    private static let resettableExactKeys = Set([
        "accounts.lockTimeout",
        "accounts.lockWithPassword",
        "accounts.syncMemories",
        "accounts.syncPreferences",
        "accounts.useKeychain",
    ])

    static func shouldReset(key: String) -> Bool {
        if resettableExactKeys.contains(key) {
            return true
        }

        return resettablePrefixes.contains { key.hasPrefix($0) }
    }
}
