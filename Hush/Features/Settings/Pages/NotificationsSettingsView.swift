import SwiftUI
import UserNotifications
extension MainWindowView {
    private var hasSystemNotificationPermission: Bool {
        notificationManager.isPermissionGranted
    }

    private var notificationAccessBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled && notificationManager.isPermissionGranted },
            set: { isEnabled in
                if isEnabled {
                    notificationsEnabled = true

                    Task {
                        let granted = await notificationManager.requestAuthorizationIfNeeded()
                        if granted == false {
                            notificationsEnabled = false

                            if notificationManager.authorizationStatus == .denied {
                                notificationManager.openSystemNotificationSettings()
                            }
                        }

                        notificationManager.syncEnabledState()
                    }
                } else {
                    notificationsEnabled = false
                    notificationManager.syncEnabledState()
                }
            }
        )
    }

    private var notificationAccessDescription: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional:
            if notificationsEnabled {
                return "HUSH can send system notifications."
            }

            return "Notification access is allowed, but HUSH is currently paused."
        case .denied:
            return "macOS has notifications turned off for HUSH. Use the toolbar bell to change that."
        case .notDetermined:
            return "Turn this on to let macOS ask for notification access."
        @unknown default:
            return "Notification access is managed by macOS."
        }
    }

    var notificationSettings: some View {
        Form {
            Section {
                explainedToggle(
                    "Enable Notifications",
                    description: notificationAccessDescription,
                    isOn: notificationAccessBinding
                )

                if hasSystemNotificationPermission {
                    explainedToggle(
                        "Sound",
                        description: "Play a sound with delivered notifications.",
                        isOn: $notifSound
                    )

                    explainedToggle(
                        "Badge Menu Bar Item",
                        description: "Show badge state on the menu bar item.",
                        isOn: $notifBadge
                    )

                    explainedPicker(
                        "Content Preview",
                        description: "Choose how much text appears in notifications.",
                        selection: $notifPreviewContent
                    ) {
                        Text("Full").tag("full")
                        Text("Partial").tag("partial")
                        Text("None").tag("none")
                    }
                }
            } header: {
                Text("System")
            } footer: {
                if hasSystemNotificationPermission {
                    Text("The toolbar bell stays green while macOS allows notifications for HUSH.")
                } else {
                    Text("Grant notification access first. The toolbar bell turns red when macOS is not allowing notifications.")
                }
            }

            Section {
                explainedToggle(
                    "In-App Banners",
                    description: "Show notifications inside HUSH windows.",
                    isOn: $notifInAppEnabled
                )

                if notifInAppEnabled {
                    explainedToggle(
                        "Show Informational Updates",
                        description: "Show non-error updates like mode changes.",
                        isOn: $notifInAppShowInfo
                    )

                    explainedToggle(
                        "Auto-Dismiss Banners",
                        description: "Automatically hide non-error in-app banners.",
                        isOn: $notifInAppAutoDismiss
                    )

                    explainedPicker(
                        "Banner Duration",
                        description: "Choose how long banners stay visible.",
                        selection: $notifInAppDuration
                    ) {
                        Text("Short").tag("short")
                        Text("Normal").tag("normal")
                        Text("Long").tag("long")
                    }
                }
            } header: {
                Text("In-App")
            } footer: {
                Text("These controls stay local to HUSH and do not depend on system notification delivery.")
            }

            Section {
                Group {
                    explainedToggle(
                        "Background Task Finished",
                        description: "Send an alert when background work completes.",
                        isOn: $notifBackgroundComplete
                    )

                    explainedToggle(
                        "Errors and Failures",
                        description: "Send an alert when a request fails.",
                        isOn: $notifErrors
                    )
                }
                .disabled(!hasSystemNotificationPermission)
            } header: {
                Text("Alerts")
            } footer: {
                if hasSystemNotificationPermission {
                    Text("More alert types can be added here later.")
                } else {
                    Text("Grant notification access to edit these alert triggers.")
                }
            }
        }
        .onAppear {
            notificationManager.refreshSystemSettings()
            notificationManager.syncEnabledState()
        }
        .onChange(of: notificationsEnabled) { _, _ in
            notificationManager.syncEnabledState()
        }
        .onChange(of: notifBadge) { _, _ in
            notificationManager.syncEnabledState()
        }
        .settingsPageLayout()
    }
}
