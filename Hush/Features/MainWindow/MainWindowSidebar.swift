import SwiftUI

enum SidebarRowIcon {
    case system(String)
    case text(String)
}

private struct SidebarEntry: Identifiable {
    let title: String
    let icon: SidebarRowIcon
    let route: MainWindowRoute

    var id: String {
        switch route {
        case .hush:
            return "workspace-hush"
        case .assistant:
            return "workspace-assistant"
        case .sessions:
            return "workspace-sessions"
        case let .section(section):
            return "settings-\(section.rawValue)"
        case let .behaviour(page):
            return "settings-behaviour-\(page.rawValue)"
        }
    }
}

extension MainWindowView {
    var mainWindowSidebar: some View {
        ZStack {
            if sidebarFilterText.isEmpty || !appSearchResults.isEmpty {
                List {
                    if sidebarFilterText.isEmpty {
                        if !allWorkspaceEntries.isEmpty {
                            Section("Workspace") {
                                ForEach(allWorkspaceEntries) { entry in
                                    sidebarRow(
                                        title: entry.title,
                                        icon: entry.icon,
                                        route: entry.route
                                    )
                                }
                            }
                        }

                        if !allSettingsEntries.isEmpty {
                            Section("Settings") {
                                ForEach(allSettingsEntries) { entry in
                                    sidebarRow(
                                        title: entry.title,
                                        icon: entry.icon,
                                        route: entry.route
                                    )
                                }
                            }
                        }
                    } else {
                        Section("Results") {
                            ForEach(appSearchResults) { result in
                                searchResultRow(result)
                            }
                        }
                    }
                }
            } else {
                VStack {
                    Spacer(minLength: 0)
                    ContentUnavailableView("No results", systemImage: "magnifyingglass")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .searchable(
            text: Binding(
                get: { store.sidebarSearchText },
                set: { store.sidebarSearchText = $0 }
            ),
            placement: .sidebar,
            prompt: "Search"
        )
        .tint(themesAccentColor)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 56)
        }
        .overlay(alignment: .bottom) {
            sidebarOverlayTogglePill
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
    }

    fileprivate var selectedSidebarEntry: MainWindowSidebarSelection {
        currentRoute.sidebarSelection
    }

    fileprivate var sidebarFilterText: String {
        store.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate var allWorkspaceEntries: [SidebarEntry] {
        [
            SidebarEntry(title: "Hush", icon: .text("^-^"), route: .hush),
            SidebarEntry(title: "Assistant", icon: .system("message.fill"), route: .assistant),
            SidebarEntry(title: "Sessions", icon: .system("clock.fill"), route: .sessions),
        ]
    }

    fileprivate var allSettingsEntries: [SidebarEntry] {
        SettingsSection.allCases.map { section in
            SidebarEntry(
                title: section.rawValue,
                icon: .system(section.icon),
                route: .section(section)
            )
        }
    }

    fileprivate func sidebarRowIsSelected(for route: MainWindowRoute) -> Bool {
        selectedSidebarEntry == route.sidebarSelection
    }

    func sidebarRow(title: String, icon: String, route: MainWindowRoute) -> some View {
        sidebarRow(title: title, icon: .system(icon), route: route)
    }

    func sidebarRow(title: String, iconText: String, route: MainWindowRoute) -> some View {
        sidebarRow(title: title, icon: .text(iconText), route: route)
    }

    func sidebarRow(title: String, icon: SidebarRowIcon, route: MainWindowRoute) -> some View {
        let isSelected = sidebarRowIsSelected(for: route)

        return Button {
            navigate(to: route)
        } label: {
            HStack(spacing: 8) {
                sidebarRowIconView(icon, isSelected: isSelected)
                    .frame(width: 24, alignment: .leading)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? themesAccentColor.opacity(0.18) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? themesAccentColor.opacity(0.26) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverCursor(.pointingHand)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    func sidebarRowIconView(_ icon: SidebarRowIcon, isSelected: Bool) -> some View {
        switch icon {
        case let .system(name):
            Image(systemName: name)
                .frame(width: 16)
                .foregroundStyle(isSelected ? .primary : .secondary)
        case let .text(value):
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
    }

    func searchResultRow(_ result: MainWindowSearchEntry) -> some View {
        Button {
            navigate(to: result.route)
        } label: {
            HStack(spacing: 8) {
                sidebarRowIconView(result.icon, isSelected: false)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .foregroundStyle(.primary)
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverCursor(.pointingHand)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .listRowBackground(Color.clear)
    }

    var sidebarOverlayTogglePill: some View {
        Button {
            performOnMainActor {
                appModel.toggleOverlay()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Overlay")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(toggleOverlayShortcut.displayTokens, id: \.self) { token in
                        Text(token)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .hoverCursor(.pointingHand)
    }

    var toggleOverlayShortcut: GlobalShortcut {
        _ = appModel.shortcutConfigurationVersion
        return GlobalShortcut.fromDefaults(
            GlobalShortcutAction.hideUnhideFromScreen.defaultsKey,
            fallback: GlobalShortcutAction.hideUnhideFromScreen.defaultShortcut
        )
    }
}

private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                guard isHovering != self.isHovering else { return }
                self.isHovering = isHovering

                if isHovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard isHovering else { return }
                isHovering = false
                NSCursor.pop()
            }
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
    }
}
