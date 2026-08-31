import AppIntents

struct NewHushConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "New Hush Conversation"
    static let description = IntentDescription("Open a fresh, private conversation in Hush.")
    static var supportedModes: IntentModes { .foreground }
    @AppDependency private var workspace: WorkspaceModel

    @MainActor
    func perform() async throws -> some IntentResult {
        await workspace.bootstrap()
        workspace.newConversation()
        return .result()
    }
}

struct DiscoverHushModelsIntent: AppIntent {
    static let title: LocalizedStringResource = "Discover Local Models"
    static let description = IntentDescription("Find on-device models in Hush's Hugging Face catalog.")
    static var supportedModes: IntentModes { .foreground }
    @AppDependency private var workspace: WorkspaceModel

    @MainActor
    func perform() async throws -> some IntentResult {
        await workspace.bootstrap()
        workspace.page = .discover
        return .result()
    }
}

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewHushConversationIntent(), phrases: ["New conversation in \(.applicationName)"],
                    shortTitle: "New conversation", systemImageName: "square.and.pencil")
        AppShortcut(intent: DiscoverHushModelsIntent(), phrases: ["Find models in \(.applicationName)"],
                    shortTitle: "Discover models", systemImageName: "square.stack.3d.up")
    }
}
