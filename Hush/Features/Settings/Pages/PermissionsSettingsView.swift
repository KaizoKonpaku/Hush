import SwiftUI

extension MainWindowView {
    var permissionsSettings: some View {
        Form {
            ForEach(AppPermissionKind.allCases) { permission in
                permissionRow(permission)
            }
        }
        .settingsPageLayout()
    }

    func permissionRow(_ permission: AppPermissionKind) -> some View {
        let state = permissionsManager.state(for: permission)

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: permission.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            permissionStatusIndicator(for: state)

            if let buttonTitle = permissionButtonTitle(for: state) {
                Button(buttonTitle) {
                    handlePermissionAction(for: permission, state: state)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    func permissionButtonTitle(for state: AppPermissionState) -> String? {
        state.resolutionAction.buttonTitle
    }

    func handlePermissionAction(for permission: AppPermissionKind, state: AppPermissionState) {
        switch state.resolutionAction {
        case .openSystemSettings:
            performOnMainActor {
                permissionsManager.openSystemSettings(for: permission)
            }
        case .request:
            Task { @MainActor in
                await permissionsManager.request(permission)
            }
        case .none:
            break
        }
    }

    func syncRuntimeSettings() {
        performOnMainActor {
            appModel.syncRuntime(.launchAtLogin)
            appModel.syncRuntime(.menuBar)
            appModel.syncRuntime(.navigation)
            appModel.syncRuntime(.stealth)
        }
    }

    func permissionStatusIndicator(for state: AppPermissionState) -> some View {
        Group {
            if state == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Granted")
            } else {
                Text(state.statusLabel)
                    .font(.caption)
                    .foregroundStyle(permissionStatusColor(for: state))
            }
        }
    }

    func permissionStatusColor(for state: AppPermissionState) -> Color {
        switch state {
        case .granted:
            return .green
        case .notDetermined, .needsApproval:
            return .orange
        case .denied:
            return .red
        case .restricted:
            return .secondary
        }
    }
}
