import SwiftUI

private enum SidebarSelection: Hashable {
    case page(WorkspacePage)
    case conversation(UUID)
}

struct WorkspaceView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var showsInspector = false
    @State private var conversationToDelete: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 290)
        } detail: {
            ZStack {
                WorkspaceBackdrop()
                switch workspace.page {
                case .chat: ChatView()
                case .discover: ModelDiscoveryView()
                case .library: ModelLibraryView()
                case .runtime: RuntimeView()
                case .settings: PreferencesView()
                }
            }
            .navigationTitle(workspace.page == .chat ? "" : workspace.page.title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if workspace.page == .chat { ModelPicker() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("New conversation", systemImage: "square.and.pencil") { workspace.newConversation() }
                        .labelStyle(.iconOnly)
                        .help("New conversation (Command-N)")
                    Button("Runtime inspector", systemImage: "sidebar.right") {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { showsInspector.toggle() }
                    }.labelStyle(.iconOnly)
                }
                #if !os(visionOS)
                .visibilityPriority(.high)
                #endif
            }
            #if os(visionOS)
            .sheet(isPresented: $showsInspector) {
                RuntimeInspector().frame(width: 380, height: 580)
            }
            #else
            .inspector(isPresented: $showsInspector) {
                RuntimeInspector().inspectorColumnWidth(min: 270, ideal: 290, max: 340)
            }
            #endif
        }
        .tint(HushStyle.accent)
        .preferredColorScheme(workspace.settings.appearance == "system" ? nil : workspace.settings.appearance == "dark" ? .dark : .light)
        #if os(macOS)
        .frame(minWidth: 660, minHeight: 500)
        #endif
        .task { await workspace.bootstrap() }
        .onChange(of: workspace.settings) { workspace.savePreferences() }
        .onChange(of: workspace.page) { compactColumn = .detail }
        .hushNotices()
        .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { conversationToDelete != nil }, set: { if !$0 { conversationToDelete = nil } })) {
            Button("Delete conversation", role: .destructive) {
                if let id = conversationToDelete { workspace.deleteConversation(id) }
                conversationToDelete = nil
            }
        } message: { Text("This removes the conversation from this device. Export it first if you want to keep a copy.") }
    }

    private var sidebar: some View {
        @Bindable var workspace = workspace
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                HushMark(size: 30)
                Text("hush").font(.system(size: 28, weight: .medium, design: .serif)).tracking(-1.2)
                Spacer()
                Text("27").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary).padding(6).overlay(Circle().stroke(.quaternary))
            }
            .padding(.horizontal, 21).padding(.top, 18).padding(.bottom, 22)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Find a conversation", text: $workspace.conversationSearch).textFieldStyle(.plain)
            }
            .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: .capsule)
            .padding(.horizontal, 14).padding(.bottom, 12)

            List(selection: sidebarSelection) {
                Section {
                    ForEach(WorkspacePage.allCases.filter { $0 != .settings }) { page in
                        NavigationLink(value: SidebarSelection.page(page)) {
                            Label(page.title, systemImage: page.symbol).font(.system(size: 13, weight: .medium))
                                .padding(.vertical, 4)
                        }
                    }
                }
                Section("Conversations") {
                    if workspace.filteredConversations.isEmpty {
                        Text(workspace.conversationSearch.isEmpty ? "A fresh start." : "No matches")
                            .font(.caption).foregroundStyle(.tertiary).listRowSeparator(.hidden)
                    }
                    ForEach(workspace.filteredConversations) { conversation in
                        NavigationLink(value: SidebarSelection.conversation(conversation.id)) {
                            HStack(spacing: 8) {
                                Image(systemName: conversation.isPinned ? "pin" : "bubble.left")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                Text(conversation.title).lineLimit(1).font(.system(size: 12))
                                if workspace.activeConversationID == conversation.id { ProgressView().controlSize(.mini) }
                            }
                            .padding(.vertical, 3)
                        }
                        .contextMenu {
                            Button(conversation.isPinned ? "Unpin" : "Pin", systemImage: "pin") { workspace.togglePin(conversation.id) }
                            ShareLink(item: conversation.exportText) { Label("Export conversation", systemImage: "square.and.arrow.up") }
                            Button("Delete", systemImage: "trash", role: .destructive) { conversationToDelete = conversation.id }
                                .disabled(workspace.activeConversationID == conversation.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 13) {
                if workspace.download?.isActive == true { DownloadProgressView(compact: true) }
                Button { workspace.page = .settings } label: {
                    Label("Settings", systemImage: "gearshape").font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                HStack(spacing: 8) {
                    Circle().fill(HushStyle.accent).frame(width: 5, height: 5)
                    Text(workspace.hardware.chipName).font(.system(size: 10, weight: .medium, design: .monospaced))
                    Spacer()
                    Image(systemName: "lock.shield").font(.system(size: 11))
                }.foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding {
            if workspace.page == .chat, let id = workspace.selectedConversationID { .conversation(id) }
            else { .page(workspace.page) }
        } set: { selection in
            switch selection {
            case .page(let page):
                if page == .chat { workspace.newConversation() } else { workspace.page = page }
            case .conversation(let id): workspace.selectConversation(id)
            case nil: break
            }
        }
    }
}

struct ModelPicker: View {
    @Environment(WorkspaceModel.self) private var workspace
    var onDiscover: (() -> Void)?
    var body: some View {
        Menu {
            ForEach(workspace.availableModels) { model in
                Button { workspace.selectModel(model) } label: {
                    if workspace.selectedModel.id == model.id { Label(model.name, systemImage: "checkmark") }
                    else { Text(model.name) }
                }
            }
            Divider()
            Button("Discover models", systemImage: "plus.magnifyingglass") {
                workspace.page = .discover
                onDiscover?()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: workspace.selectedModel.engine == .apple ? "apple.intelligence" : "cube.transparent")
                    .foregroundStyle(HushStyle.accent)
                Text(workspace.selectedModel.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: 220)
        }
        .menuStyle(.automatic)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Choose a local model")
    }
}

#if os(macOS)
struct QuickChatView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HushMark(size: 24)
                ModelPicker(onDiscover: { openWindow(id: "workspace") })
                Spacer()
                Button("New conversation", systemImage: "square.and.pencil") { workspace.newConversation() }
                Button("Open workspace", systemImage: "arrow.up.forward.app") {
                    workspace.page = .chat
                    openWindow(id: "workspace")
                }
                Button("Close quick chat", systemImage: "xmark") { dismissWindow(id: "quick-chat") }
            }
            .buttonStyle(.borderless).labelStyle(.iconOnly)
            .padding(.horizontal, 20).padding(.vertical, 12)
            ChatView(compact: true, onDiscover: { openWindow(id: "workspace") })
        }
        .frame(minWidth: 340, minHeight: 240)
        .background { WorkspaceBackdrop() }
        .tint(HushStyle.accent)
        .preferredColorScheme(workspace.settings.appearance == "system" ? nil : workspace.settings.appearance == "dark" ? .dark : .light)
        .hushNotices()
        .task { await workspace.bootstrap() }
    }
}
#endif
