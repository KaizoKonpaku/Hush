import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case accounts = "Accounts"
    case intelligence = "Intelligence"
    case memory = "Memory"
    case behaviours = "Behaviours"
    case navigation = "Navigation"
    case notifications = "Notifications"
    case themes = "Themes"
    case shortcuts = "Shortcuts"
    case components = "Components"
    case locations = "Locations"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .accounts: return "person.crop.circle.fill"
        case .intelligence: return "wand.and.stars"
        case .memory: return "brain.fill"
        case .behaviours: return "line.3.horizontal.decrease.circle.fill"
        case .navigation: return "square.grid.2x2.fill"
        case .notifications: return "bell.fill"
        case .themes: return "paintpalette.fill"
        case .shortcuts: return "command.circle.fill"
        case .components: return "square.stack.3d.up.fill"
        case .locations: return "externaldrive.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var searchKeywords: [String] {
        switch self {
        case .general:
            return ["startup", "launch", "menu bar", "overlay defaults", "app basics"]
        case .accounts:
            return ["security", "keychain", "sync", "password", "touch id"]
        case .intelligence:
            return ["ai", "assistant", "models", "profiles", "prompt presets", "default prompt", "runtime"]
        case .memory:
            return ["history", "memory", "transcripts", "autosave", "context"]
        case .behaviours:
            return ["live", "responses", "text", "capture", "stealth", "actions", "defaults"]
        case .navigation:
            return ["position", "placement", "screen", "auto hide", "gestures"]
        case .notifications:
            return ["alerts", "banners", "sound", "badge", "preview"]
        case .themes:
            return ["appearance", "theme", "accent", "glass", "fonts", "formatting"]
        case .shortcuts:
            return ["hotkeys", "keyboard shortcuts", "commands", "key bindings"]
        case .components:
            return ["plugins", "extensions", "components", "under development"]
        case .locations:
            return ["storage", "folders", "paths", "models", "archives", "sessions"]
        case .permissions:
            return ["privacy", "permissions", "access", "camera", "microphone", "notifications"]
        }
    }
}

enum BehaviourSettingsPage: String, CaseIterable, Identifiable {
    case startup = "Startup"
    case overlay = "Overlay"
    case stealth = "Stealth"
    case live = "Live"
    case text = "Text"
    case capture = "Capture"

    static let appPages: [Self] = [.startup, .overlay]
    static let modePages: [Self] = [.stealth, .live, .text, .capture]

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .startup:
            return "power.circle.fill"
        case .overlay:
            return "rectangle.3.group.bubble.fill"
        case .stealth:
            return "eye.slash.fill"
        case .live:
            return "waveform"
        case .text:
            return "text.bubble.fill"
        case .capture:
            return "camera.viewfinder"
        }
    }
}

enum MainWindowSidebarSelection: Hashable {
    case hush
    case assistant
    case sessions
    case settings(SettingsSection)
}

enum MainWindowRoute: Hashable {
    case hush
    case assistant
    case sessions
    case section(SettingsSection)
    case behaviour(BehaviourSettingsPage)

    var title: String {
        switch self {
        case .hush:
            return "Hush"
        case .assistant:
            return "Assistant"
        case .sessions:
            return "Sessions"
        case let .section(section):
            return section.rawValue
        case .behaviour(.startup), .behaviour(.overlay):
            return SettingsSection.general.rawValue
        case .behaviour(.stealth), .behaviour(.live), .behaviour(.text), .behaviour(.capture):
            return SettingsSection.behaviours.rawValue
        }
    }

    var sidebarSelection: MainWindowSidebarSelection {
        switch self {
        case .hush:
            return .hush
        case .assistant:
            return .assistant
        case .sessions:
            return .sessions
        case let .section(section):
            return .settings(section)
        case .behaviour(.startup), .behaviour(.overlay):
            return .settings(.general)
        case .behaviour(.stealth), .behaviour(.live), .behaviour(.text), .behaviour(.capture):
            return .settings(.behaviours)
        }
    }

    var isSettingsRoute: Bool {
        switch self {
        case .section(_), .behaviour(_):
            return true
        case .hush, .assistant, .sessions:
            return false
        }
    }

    var usesSettingsChrome: Bool {
        switch self {
        case .hush, .assistant, .sessions:
            return false
        case .section(_), .behaviour(_):
            return true
        }
    }

    var normalizedSettingsRoute: MainWindowRoute {
        switch self {
        case .behaviour(.startup), .behaviour(.overlay):
            return .section(.general)
        case .behaviour(.stealth), .behaviour(.live), .behaviour(.text), .behaviour(.capture):
            return .section(.behaviours)
        case .section(_), .hush, .assistant, .sessions:
            return self
        }
    }

    var rememberedSettingsRouteToken: String? {
        let route = normalizedSettingsRoute

        switch route {
        case let .section(section):
            return "section:\(section.rawValue)"
        case let .behaviour(page):
            return "behaviour:\(page.rawValue)"
        case .hush, .assistant, .sessions:
            return nil
        }
    }

    static func rememberedSettingsRoute(from token: String?) -> MainWindowRoute {
        guard let token else {
            return .section(.general)
        }

        let components = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return .section(.general)
        }

        switch components[0] {
        case "section":
            if let section = SettingsSection(rawValue: components[1]) {
                return MainWindowRoute.section(section)
            }
        case "behaviour":
            if let page = BehaviourSettingsPage(rawValue: components[1]) {
                return MainWindowRoute.behaviour(page).normalizedSettingsRoute
            }
        default:
            break
        }

        return .section(.general)
    }

    func matchesToggleTarget(_ requestedRoute: MainWindowRoute) -> Bool {
        if self == requestedRoute {
            return true
        }

        switch (self, requestedRoute) {
        case (.behaviour(.stealth), .section(.behaviours)),
             (.behaviour(.live), .section(.behaviours)),
             (.behaviour(.text), .section(.behaviours)),
             (.behaviour(.capture), .section(.behaviours)),
             (.section(.behaviours), .behaviour(.stealth)),
             (.section(.behaviours), .behaviour(.live)),
             (.section(.behaviours), .behaviour(.text)),
             (.section(.behaviours), .behaviour(.capture)),
             (.behaviour(.startup), .section(.general)),
             (.behaviour(.overlay), .section(.general)),
             (.section(.general), .behaviour(.startup)),
             (.section(.general), .behaviour(.overlay)):
            return true
        default:
            return false
        }
    }
}
