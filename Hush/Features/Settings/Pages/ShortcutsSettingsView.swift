import SwiftUI

extension MainWindowView {
    var shortcutsSettings: some View {
        _ = appModel.shortcutConfigurationVersion

        return Form {
            ForEach(ShortcutSettingsGroup.allCases) { group in
                shortcutsGroupSection(group)
            }
        }
        .settingsPageLayout()
    }

    func resetAllShortcutsToDefaults() {
        GlobalShortcutAction.allCases.forEach { action in
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
        performOnMainActor {
            appModel.syncRuntime(.shortcuts)
        }
    }

    @ViewBuilder
    func shortcutsGroupSection(_ group: ShortcutSettingsGroup) -> some View {
        Section {
            ForEach(group.actions, id: \.rawValue) { action in
                shortcutRow(for: action)
            }
        } header: {
            Text(group.rawValue)
        } footer: {
            Text(group.footer)
        }
    }

    func shortcutRow(for action: GlobalShortcutAction) -> some View {
        let shortcut = resolvedShortcut(for: action)

        return HStack(alignment: .center, spacing: 12) {
            Text(action.title)
            Spacer(minLength: 16)
            ShortcutRecorderField(
                shortcut: shortcutBinding(for: action),
                isConflicted: conflictingShortcuts.contains(shortcut)
            )
                .frame(width: 170, height: 28, alignment: .center)
        }
    }

    func shortcutBinding(for action: GlobalShortcutAction) -> Binding<GlobalShortcut> {
        Binding<GlobalShortcut>(
            get: {
                GlobalShortcut.fromDefaults(action.defaultsKey, fallback: action.defaultShortcut)
            },
            set: { newShortcut in
                newShortcut.save(to: action.defaultsKey)
                performOnMainActor {
                    appModel.syncRuntime(.shortcuts)
                }
            }
        )
    }

    func shortcutDisplayText(for action: GlobalShortcutAction) -> String {
        resolvedShortcut(for: action).displayText
    }

    private var currentShortcutAssignments: [GlobalShortcutAction: GlobalShortcut] {
        _ = appModel.shortcutConfigurationVersion
        return Dictionary(
            uniqueKeysWithValues: GlobalShortcutAction.allCases.map { action in
                (action, resolvedShortcut(for: action))
            }
        )
    }

    private var conflictingShortcuts: Set<GlobalShortcut> {
        let groupedAssignments = Dictionary(grouping: currentShortcutAssignments.values, by: { $0 })
        return Set(groupedAssignments.compactMap { shortcut, actions in
            actions.count > 1 ? shortcut : nil
        })
    }

    private func resolvedShortcut(for action: GlobalShortcutAction) -> GlobalShortcut {
        GlobalShortcut.fromDefaults(action.defaultsKey, fallback: action.defaultShortcut)
    }
}
