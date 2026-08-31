import AppIntents
import SwiftUI

@main
struct HushApp: App {
    @State private var workspace: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(MacLifecycle.self) private var lifecycle
    #endif
    #if os(iOS)
    @State private var companion = PhoneCompanion()
    #endif

    init() {
        let workspace = WorkspaceModel()
        _workspace = State(initialValue: workspace)
        AppDependencyManager.shared.add(dependency: workspace)
    }

    var body: some Scene {
        #if os(macOS)
        Window("Hush", id: "workspace") {
            WorkspaceView().environment(workspace)
                .onAppear { lifecycle.workspace = workspace }
        }
        .defaultSize(width: 1120, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation", systemImage: "square.and.pencil") {
                    workspace.newConversation()
                    openWindow(id: "workspace")
                }.keyboardShortcut("n")
                Button("Discover Models", systemImage: "magnifyingglass") {
                    workspace.page = .discover
                    openWindow(id: "workspace")
                }.keyboardShortcut("k")
                Button("Quick Chat", systemImage: "rectangle.bottomthird.inset.filled") {
                    openWindow(id: "quick-chat")
                }.keyboardShortcut(" ", modifiers: [.command, .shift])
            }
            SidebarCommands()
        }

        Window("Quick Chat", id: "quick-chat") {
            QuickChatView().environment(workspace)
        }
        .defaultSize(width: 650, height: 440)
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            PreferencesView().frame(width: 600, height: 650)
                .hushNotices().environment(workspace)
        }

        MenuBarExtra("Hush", systemImage: "waveform.circle") {
            Button("Open Hush") { openWindow(id: "workspace") }
            Button("Quick Chat") { openWindow(id: "quick-chat") }
            Divider()
            Text(workspace.isGenerating ? "Generating on device" : "On-device intelligence")
            if workspace.isGenerating { Button("Stop Response") { workspace.stop() } }
            Divider()
            Button("Quit Hush") { NSApplication.shared.terminate(nil) }
        }
        #else
        WindowGroup {
            WorkspaceView().environment(workspace)
                #if os(iOS)
                .task { companion.activate() }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await workspace.prepareToClose() } }
        }
        #endif
    }
}
