import SwiftUI

extension MainWindowView {
    @ToolbarContentBuilder
    var mainWindowToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                goToPreviousSection()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!hasPreviousSection)
            .optionalKeyboardShortcut(navKeyboardNavigation, "[", modifiers: [.command])

            Button {
                goToNextSection()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!hasNextSection)
            .optionalKeyboardShortcut(navKeyboardNavigation, "]", modifiers: [.command])
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if currentRoute == .assistant {
                Button {
                    performOnMainActor {
                        appModel.assistantWorkspace.startNewSessionWithFeedback()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Session")

                Button {
                    isShowingAssistantInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isShowingAssistantInspector ? "Hide Assistant Inspector" : "Show Assistant Inspector")
            } else if currentRoute == .sessions {
                Button {
                    performOnMainActor {
                        sessionStore.openStorageDirectory()
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open Sessions Folder")
            } else if currentRoute == .section(.shortcuts) {
                Button {
                    isShowingShortcutResetConfirmation = true
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Reset Shortcuts to Defaults")
            } else if currentRoute == .section(.notifications) {
                Button {
                    notificationManager.openSystemNotificationSettings()
                } label: {
                    Image(systemName: notificationManager.isPermissionGranted ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(notificationManager.isPermissionGranted ? .green : .red)
                }
                .help("Open Notifications Settings")
            } else if currentRoute == .section(.permissions) {
                Button {
                    performOnMainActor {
                        permissionsManager.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Permission Status")

                Button {
                    performOnMainActor {
                        permissionsManager.openSystemSettings()
                    }
                } label: {
                    Image(systemName: "hand.raised.fill")
                }
                .help("Open Privacy & Security")
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func optionalKeyboardShortcut(
        _ isEnabled: Bool,
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        if isEnabled {
            keyboardShortcut(key, modifiers: modifiers)
        } else {
            self
        }
    }
}
