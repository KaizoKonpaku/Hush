import SwiftUI

extension MainWindowView {
    @ViewBuilder
    func settingsDetailView(for route: MainWindowRoute) -> some View {
        switch route {
        case .sessions:
            SessionsWindowView()
                .formStyle(.grouped)
        case .section(_):
            settingsFormDetailView(for: route)
        case .behaviour(.startup), .behaviour(.overlay):
            generalSettings
        case .behaviour(.stealth), .behaviour(.live), .behaviour(.text), .behaviour(.capture):
            behavioursSettings
        case .hush, .assistant:
            EmptyView()
        }
    }

    @ViewBuilder
    func settingsFormDetailView(for route: MainWindowRoute) -> some View {
        switch route {
        case .section(.general):
            generalSettings
        case .section(.accounts):
            accountsSettings
        case .section(.intelligence):
            intelligenceSettings
        case .section(.memory):
            memorySettings
        case .section(.behaviours):
            behavioursSettings
        case .section(.navigation):
            navigationSettings
        case .section(.notifications):
            notificationSettings
        case .section(.themes):
            themesSettings
        case .section(.shortcuts):
            shortcutsSettings
        case .section(.components):
            componentsSettings
        case .section(.locations):
            locationsSettings
        case .section(.permissions):
            permissionsSettings
        case .hush, .assistant, .sessions, .behaviour(_):
            EmptyView()
        }
    }
}
