import Foundation

struct MainWindowSearchEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let route: MainWindowRoute
    let icon: SidebarRowIcon
    let keywords: [String]
    let rank: Int
}

private struct MainWindowSearchMatch {
    let entry: MainWindowSearchEntry
    let score: Int
}

private enum MainWindowSearchIndex {
    static func results(for query: String, entries: [MainWindowSearchEntry]) -> [MainWindowSearchEntry] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let tokens = tokenize(normalizedQuery)
        let matches: [MainWindowSearchMatch] = entries.compactMap { entry in
            guard let score = score(for: entry, query: normalizedQuery, tokens: tokens) else {
                return nil
            }

            return MainWindowSearchMatch(entry: entry, score: score)
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.entry.rank != rhs.entry.rank { return lhs.entry.rank > rhs.entry.rank }
                return lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
            }
            .map(\.entry)
    }

    private static func score(
        for entry: MainWindowSearchEntry,
        query: String,
        tokens: [String]
    ) -> Int? {
        let title = normalize(entry.title)
        let subtitle = normalize(entry.subtitle)
        let keywordText = normalize(entry.keywords.joined(separator: " "))
        let titleTokens = tokenize(title)
        let subtitleTokens = tokenize(subtitle)
        let keywordTokens = tokenize(keywordText)

        var score = 0
        var matchedTokenCount = 0

        if title == query {
            score += 400
        } else if title.hasPrefix(query) {
            score += 250
        } else if title.contains(query) {
            score += 180
        } else if subtitle.contains(query) {
            score += 100
        } else if keywordText.contains(query) {
            score += 90
        }

        for token in tokens {
            let tokenScore = max(
                tokenMatchScore(token, in: titleTokens, exact: 50, prefix: 36, contains: 28),
                tokenMatchScore(token, in: subtitleTokens, exact: 32, prefix: 24, contains: 18),
                tokenMatchScore(token, in: keywordTokens, exact: 26, prefix: 20, contains: 16)
            )

            if tokenScore > 0 {
                matchedTokenCount += 1
                score += tokenScore
            }
        }

        if score == 0 {
            return nil
        }

        if tokens.count > 1 {
            if matchedTokenCount == tokens.count {
                score += 80
            } else if matchedTokenCount > 1 {
                score += 32
            } else if !title.contains(query) && !subtitle.contains(query) && !keywordText.contains(query) {
                return nil
            }
        }

        return score + entry.rank
    }

    private static func tokenMatchScore(
        _ token: String,
        in haystackTokens: [String],
        exact: Int,
        prefix: Int,
        contains: Int
    ) -> Int {
        for haystackToken in haystackTokens {
            if haystackToken == token {
                return exact
            }
        }

        for haystackToken in haystackTokens where haystackToken.hasPrefix(token) {
            return prefix
        }

        for haystackToken in haystackTokens where haystackToken.contains(token) {
            return contains
        }

        return 0
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

extension MainWindowView {
    var appSearchResults: [MainWindowSearchEntry] {
        MainWindowSearchIndex.results(for: searchQueryText, entries: allSearchEntries)
            .prefix(28)
            .map { $0 }
    }

    private var searchQueryText: String {
        store.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allSearchEntries: [MainWindowSearchEntry] {
        workspaceSearchEntries +
        settingsPageSearchEntries +
        settingsControlSearchEntries +
        shortcutSearchEntries
    }

    private var workspaceSearchEntries: [MainWindowSearchEntry] {
        [
            MainWindowSearchEntry(
                id: "search-workspace-hush",
                title: "Hush",
                subtitle: "Workspace",
                route: .hush,
                icon: .text("^-^"),
                keywords: ["home", "overview", "welcome", "start"],
                rank: 20
            ),
            MainWindowSearchEntry(
                id: "search-workspace-assistant",
                title: "Assistant",
                subtitle: "Workspace",
                route: .assistant,
                icon: .system("message.fill"),
                keywords: ["chat", "conversation", "prompt", "ai", "ask", "responses"],
                rank: 40
            ),
            MainWindowSearchEntry(
                id: "search-workspace-sessions",
                title: "Sessions",
                subtitle: "Workspace",
                route: .sessions,
                icon: .system("clock.fill"),
                keywords: ["history", "conversations", "threads", "chats", "session list", "timeline"],
                rank: 36
            ),
        ]
    }

    private var settingsPageSearchEntries: [MainWindowSearchEntry] {
        SettingsSection.allCases.map { section in
            MainWindowSearchEntry(
                id: "search-settings-\(section.rawValue.lowercased())",
                title: section.rawValue,
                subtitle: "Settings",
                route: .section(section),
                icon: .system(section.icon),
                keywords: section.searchKeywords,
                rank: 30
            )
        }
    }

    private var settingsControlSearchEntries: [MainWindowSearchEntry] {
        [
            searchEntry(
                "Launch at Login",
                in: .general,
                group: "App Basics",
                keywords: ["startup", "login item", "open on login", "boot", "sign in", "launch automatically"]
            ),
            searchEntry(
                "Show Menu Bar Item",
                in: .general,
                group: "App Basics",
                keywords: ["menu bar", "status item", "tray icon", "menubar", "top bar"]
            ),
            searchEntry(
                "Menu Bar Item Style",
                in: .general,
                group: "App Basics",
                keywords: ["menu bar icon", "menubar style", "status item style", "indicator style"]
            ),
            searchEntry(
                "Launch Presentation",
                in: .general,
                group: "Startup",
                keywords: ["startup", "open window", "open overlay", "launch behavior"]
            ),
            searchEntry(
                "Restore Window Locations",
                in: .general,
                group: "Startup",
                keywords: ["remember windows", "restore placement", "window positions", "reopen where left off"]
            ),
            searchEntry(
                "Open Mode",
                in: .general,
                group: "Overlay",
                keywords: ["default overlay mode", "startup mode", "overlay mode", "live text capture default"]
            ),
            searchEntry(
                "Store Secrets in Keychain",
                in: .accounts,
                group: "Security",
                keywords: ["password", "credentials", "keychain", "secrets", "security"]
            ),
            searchEntry(
                "Provider Connections",
                in: .accounts,
                group: "Providers",
                keywords: ["openai", "google", "anthropic", "x", "xai", "accounts", "api keys", "login", "connect provider"]
            ),
            searchEntry(
                "Protect Account Changes with Password / Touch ID",
                in: .accounts,
                group: "Security",
                keywords: ["touch id", "password", "biometrics", "authenticate", "protect accounts", "account security"]
            ),
            searchEntry(
                "Ask Again After",
                in: .accounts,
                group: "Security",
                keywords: ["touch id timeout", "approval timeout", "account security timeout", "ask again"]
            ),
            searchEntry(
                "Sync Preferences Across Devices",
                in: .accounts,
                group: "Sync",
                keywords: ["icloud", "sync settings", "devices", "preferences"]
            ),
            searchEntry(
                "Sync Memories & Prompts",
                in: .accounts,
                group: "Sync",
                keywords: ["sync memory", "prompt sync", "devices", "cloud memory"]
            ),
            searchEntry(
                "Default Profile",
                in: .intelligence,
                group: "Profiles",
                keywords: ["default model", "ai profile", "standard model", "assistant model"]
            ),
            searchEntry(
                "Fast Profile",
                in: .intelligence,
                group: "Profiles",
                keywords: ["fast model", "quick model", "speed profile"]
            ),
            searchEntry(
                "Advanced Profile",
                in: .intelligence,
                group: "Profiles",
                keywords: ["reasoning model", "deep thinking", "advanced model", "smart profile"]
            ),
            searchEntry(
                "Live Model",
                in: .intelligence,
                group: "Live",
                keywords: ["realtime model", "speech model", "voice model", "live conversation model", "openai realtime"]
            ),
            searchEntry(
                "Default Prompt",
                in: .intelligence,
                group: "Prompt Defaults",
                keywords: ["system prompt", "prompt preset", "instructions", "assistant style", "default instructions"]
            ),
            searchEntry(
                "Keep History",
                in: .memory,
                group: "History",
                keywords: ["retain chats", "conversation retention", "history length", "session history"]
            ),
            searchEntry(
                "Auto-Include History in Context",
                in: .memory,
                group: "History",
                keywords: ["context", "recent messages", "memory context", "prompt context"]
            ),
            searchEntry(
                "Enable Long-Term Memory",
                in: .memory,
                group: "Memory",
                keywords: ["remember facts", "persistent memory", "saved memory", "long term"]
            ),
            searchEntry(
                "Memory Scope",
                in: .memory,
                group: "Memory",
                keywords: ["global", "per app", "per project", "memory scope"]
            ),
            searchEntry(
                "Autosave Transcripts",
                in: .memory,
                group: "Transcripts",
                keywords: ["save chats", "save conversations", "transcript", "auto save"]
            ),
            searchEntry(
                "Transcript Format",
                in: .memory,
                group: "Transcripts",
                keywords: ["markdown", "json", "plain text", "export format"]
            ),
            searchEntry(
                "Include Metadata",
                in: .memory,
                group: "Transcripts",
                keywords: ["timestamps", "model metadata", "extra details", "context info"]
            ),
            searchEntry(
                "Auto-Name Sessions",
                in: .memory,
                group: "Transcripts",
                keywords: ["session titles", "automatic titles", "rename chats"]
            ),
            searchEntry(
                "Live Audio Source",
                in: .behaviours,
                group: "Live",
                keywords: ["microphone", "system audio", "audio source", "live input", "mic"]
            ),
            searchEntry(
                "Live Language",
                in: .behaviours,
                group: "Live",
                keywords: ["speech language", "transcription language", "english", "japanese"]
            ),
            searchEntry(
                "Auto-Listen",
                in: .behaviours,
                group: "Live",
                keywords: ["start listening", "hands free", "automatic live"]
            ),
            searchEntry(
                "Interrupt When Speaking",
                in: .behaviours,
                group: "Live",
                keywords: ["barge in", "interrupt", "voice interruption"]
            ),
            searchEntry(
                "Reduce Noise",
                in: .behaviours,
                group: "Live",
                keywords: ["noise suppression", "background noise", "audio cleanup"]
            ),
            searchEntry(
                "Stream Responses",
                in: .behaviours,
                group: "Responses",
                keywords: ["typing", "streaming", "incremental output", "live response", "response mode"]
            ),
            searchEntry(
                "Answer Length",
                in: .behaviours,
                group: "Responses",
                keywords: ["short", "medium", "long", "response length", "answer size"]
            ),
            searchEntry(
                "Markdown",
                in: .behaviours,
                group: "Responses",
                keywords: ["markdown rendering", "formatting", "rich text"]
            ),
            searchEntry(
                "Citations",
                in: .behaviours,
                group: "Responses",
                keywords: ["sources", "references", "links", "evidence"]
            ),
            searchEntry(
                "Quick Capture Mode",
                in: .behaviours,
                group: "Capture",
                keywords: ["screenshot mode", "selection capture", "window capture"]
            ),
            searchEntry(
                "Include Cursor",
                in: .behaviours,
                group: "Capture",
                keywords: ["mouse pointer", "cursor in screenshot"]
            ),
            searchEntry(
                "Enable Stealth Mode",
                in: .behaviours,
                group: "Stealth",
                keywords: ["privacy mode", "discreet", "hidden mode", "low profile"]
            ),
            searchEntry(
                "Launch Without Taking Focus",
                in: .behaviours,
                group: "Stealth",
                keywords: ["background launch", "without focus", "do not activate"]
            ),
            searchEntry(
                "Keep Window Above Other Apps",
                in: .behaviours,
                group: "Stealth",
                keywords: ["always on top", "stay on top", "floating", "window level"]
            ),
            searchEntry(
                "Hide from Dock and App Switcher",
                in: .behaviours,
                group: "Stealth",
                keywords: ["dock", "cmd tab", "command tab", "app switcher", "hide app"]
            ),
            searchEntry(
                "Hide from Mission Control and Stage Manager",
                in: .behaviours,
                group: "Stealth",
                keywords: ["mission control", "stage manager", "overview", "hide windows"]
            ),
            searchEntry(
                "Hide from Window Menu",
                in: .behaviours,
                group: "Stealth",
                keywords: ["windows menu", "window list", "hide from menu"]
            ),
            searchEntry(
                "Hide from Screen Sharing & Screenshots",
                in: .behaviours,
                group: "Stealth",
                keywords: ["screen capture", "screen recording", "hide from screenshots", "privacy"]
            ),
            searchEntry(
                "Ignore Mouse Interactions",
                in: .behaviours,
                group: "Stealth",
                keywords: ["click through", "mouse passthrough", "ignore clicks"]
            ),
            searchEntry(
                "Hide Window Shadow",
                in: .behaviours,
                group: "Stealth",
                keywords: ["remove shadow", "flat window", "stealth shadow"]
            ),
            searchEntry(
                "Window Opacity",
                in: .behaviours,
                group: "Stealth",
                keywords: ["transparency", "opacity", "alpha", "window transparency"]
            ),
            searchEntry(
                "Suppress Notification Center History",
                in: .behaviours,
                group: "Stealth",
                keywords: ["notification history", "privacy", "notifications", "stealth alerts"]
            ),
            searchEntry(
                "Suppress Recent Items and Handoff",
                in: .behaviours,
                group: "Stealth",
                keywords: ["recent items", "handoff", "privacy", "continuity"]
            ),
            searchEntry(
                "Confirm Actions",
                in: .behaviours,
                group: "Advanced",
                keywords: ["confirm destructive actions", "ask before actions", "confirmation"]
            ),
            searchEntry(
                "Filesystem Actions",
                in: .behaviours,
                group: "Advanced",
                keywords: ["file actions", "disk access", "write files", "filesystem"]
            ),
            searchEntry(
                "Network Actions",
                in: .behaviours,
                group: "Advanced",
                keywords: ["internet", "network", "online actions", "web access"]
            ),
            searchEntry(
                "Placement",
                in: .navigation,
                group: "Placement",
                keywords: ["window position", "overlay position", "where window opens"]
            ),
            searchEntry(
                "Screen",
                in: .navigation,
                group: "Placement",
                keywords: ["display", "monitor", "multi monitor", "screen placement"]
            ),
            searchEntry(
                "Snap to Screen Edges",
                in: .navigation,
                group: "Placement",
                keywords: ["snap", "edges", "magnet", "window snapping"]
            ),
            searchEntry(
                "Auto-Hide",
                in: .navigation,
                group: "Interaction",
                keywords: ["hide after inactivity", "fade away", "auto close"]
            ),
            searchEntry(
                "Focus Input on Open",
                in: .navigation,
                group: "Interaction",
                keywords: ["cursor", "text field focus", "focus on open"]
            ),
            searchEntry(
                "Trackpad Gestures",
                in: .navigation,
                group: "Advanced",
                keywords: ["gestures", "swipe", "trackpad controls"]
            ),
            searchEntry(
                "Keyboard Navigation",
                in: .navigation,
                group: "Advanced",
                keywords: ["keyboard only", "navigate with keyboard", "shortcuts navigation"]
            ),
            searchEntry(
                "Enable Notifications",
                in: .notifications,
                group: "System",
                keywords: ["allow notifications", "notification permission", "system alerts"]
            ),
            searchEntry(
                "Sound",
                in: .notifications,
                group: "System",
                keywords: ["notification sound", "play sound", "audio alert"]
            ),
            searchEntry(
                "Badge Menu Bar Item",
                in: .notifications,
                group: "System",
                keywords: ["badge", "menu bar badge", "notification dot"]
            ),
            searchEntry(
                "Content Preview",
                in: .notifications,
                group: "System",
                keywords: ["preview text", "notification preview", "message preview"]
            ),
            searchEntry(
                "In-App Banners",
                in: .notifications,
                group: "In-App",
                keywords: ["in app notifications", "banners", "local banners"]
            ),
            searchEntry(
                "Show Informational Updates",
                in: .notifications,
                group: "In-App",
                keywords: ["info banners", "mode changes", "updates"]
            ),
            searchEntry(
                "Auto-Dismiss Banners",
                in: .notifications,
                group: "In-App",
                keywords: ["auto dismiss", "hide banners", "dismiss notifications"]
            ),
            searchEntry(
                "Banner Duration",
                in: .notifications,
                group: "In-App",
                keywords: ["banner time", "notification duration", "how long banners stay"]
            ),
            searchEntry(
                "Background Task Finished",
                in: .notifications,
                group: "Alerts",
                keywords: ["job complete", "background complete", "task finished"]
            ),
            searchEntry(
                "Errors and Failures",
                in: .notifications,
                group: "Alerts",
                keywords: ["errors", "failures", "error alerts", "problem notifications"]
            ),
            searchEntry(
                "Theme",
                in: .themes,
                group: "Appearance",
                keywords: ["light mode", "dark mode", "appearance", "system theme"]
            ),
            searchEntry(
                "Accent",
                in: .themes,
                group: "Appearance",
                keywords: ["accent color", "highlight color", "theme color"]
            ),
            searchEntry(
                "Surface Material",
                in: .themes,
                group: "Appearance",
                keywords: ["glass", "liquid glass", "solid", "medium material", "surface style"]
            ),
            searchEntry(
                "Spacing",
                in: .themes,
                group: "Appearance",
                keywords: ["density", "padding", "compact", "spacious"]
            ),
            searchEntry(
                "Accent Action Pills",
                in: .themes,
                group: "Appearance",
                keywords: ["accent buttons", "action pills", "colored controls"]
            ),
            searchEntry(
                "Body Font",
                in: .themes,
                group: "Typography",
                keywords: ["font family", "typeface", "text font"]
            ),
            searchEntry(
                "Text Size",
                in: .themes,
                group: "Typography",
                keywords: ["font size", "text scale", "size"]
            ),
            searchEntry(
                "Line Height",
                in: .themes,
                group: "Typography",
                keywords: ["line spacing", "leading", "text spacing"]
            ),
            searchEntry(
                "Message Layout",
                in: .themes,
                group: "Messages",
                keywords: ["chat bubbles", "flat list", "bubble style"]
            ),
            searchEntry(
                "Show Avatars",
                in: .themes,
                group: "Messages",
                keywords: ["avatars", "profile icons", "speaker icons"]
            ),
            searchEntry(
                "Markdown Rendering",
                in: .themes,
                group: "Formatting",
                keywords: ["markdown", "render markdown", "rich formatting"]
            ),
            searchEntry(
                "Code Block Theme",
                in: .themes,
                group: "Formatting",
                keywords: ["syntax highlighting", "code colors", "editor theme"]
            ),
            searchEntry(
                "Code Line Numbers",
                in: .themes,
                group: "Formatting",
                keywords: ["line numbers", "code numbers", "editor lines"]
            ),
            searchEntry(
                "Response Animation",
                in: .themes,
                group: "Streaming",
                keywords: ["typewriter", "chunks", "instant", "response motion"]
            ),
            searchEntry(
                "Show Typing Indicator",
                in: .themes,
                group: "Streaming",
                keywords: ["typing indicator", "assistant typing", "loading indicator"]
            ),
            searchEntry(
                "Components",
                in: .components,
                group: "Status",
                keywords: ["plugins", "extensions", "add ons", "under development"]
            ),
            searchEntry(
                "Allow External Drives",
                in: .locations,
                group: "External Drives",
                keywords: ["external disk", "removable drive", "volumes", "usb drive"]
            ),
            searchEntry(
                "Sessions Location",
                in: .locations,
                group: "Storage",
                keywords: ["session storage", "history location", "session folder"]
            ),
            searchEntry(
                "Archives Location",
                in: .locations,
                group: "Storage",
                keywords: ["archive folder", "archives path", "stored archives"]
            ),
            searchEntry(
                "Models Location",
                in: .locations,
                group: "Models",
                keywords: ["model folder", "downloaded models", "model storage", "ai models"]
            ),
        ] + permissionSearchEntries
    }

    private var permissionSearchEntries: [MainWindowSearchEntry] {
        AppPermissionKind.allCases.map { permission in
            searchEntry(
                "\(permission.title) Permission",
                in: .permissions,
                group: "Permissions",
                keywords: permission.searchKeywords
            )
        }
    }

    private var shortcutSearchEntries: [MainWindowSearchEntry] {
        GlobalShortcutAction.allCases.map { action in
            MainWindowSearchEntry(
                id: "search-shortcut-\(action.rawValue)",
                title: action.title,
                subtitle: "Shortcuts > \(action.settingsGroup.rawValue)",
                route: .section(.shortcuts),
                icon: .system(SettingsSection.shortcuts.icon),
                keywords: action.searchKeywords,
                rank: 18
            )
        }
    }

    private func searchEntry(
        _ title: String,
        in section: SettingsSection,
        group: String,
        keywords: [String],
        rank: Int = 16
    ) -> MainWindowSearchEntry {
        MainWindowSearchEntry(
            id: "search-\(section.rawValue.lowercased())-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))",
            title: title,
            subtitle: "\(section.rawValue) > \(group)",
            route: .section(section),
            icon: .system(section.icon),
            keywords: keywords + [section.rawValue, group],
            rank: rank
        )
    }

}
