import SwiftUI

/// Settings window controller for managing the settings window
final class SettingsWindowController {
    /// The window instance
    private var settingsWindow: NSWindow?
    
    /// Reference to app state for view model creation
    private var appState: AppState?

    /// Global event monitor for detecting Command+comma key presses
    private var keyEventMonitor: Any?

    /// Shows or brings to front the settings window
    /// - Parameter appState: Optional app state reference
    func showSettingsWindow(appState: AppState? = nil) {
        // Save app state for view model creation if provided
        if let appState = appState {
            self.appState = appState
        }
        
        // If window already exists, just bring it forward
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            // Remember the frontmost app before activating
            let frontApp = NSWorkspace.shared.frontmostApplication
            
            // We need to activate briefly to show settings (as this is intentional user interaction)
            NSApp.activate(ignoringOtherApps: true)
            
            // Return focus to previous app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Use activate() directly on macOS 14+ or fall back to the options parameter
                if #available(macOS 14.0, *) {
                    frontApp?.activate()
                } else {
                    frontApp?.activate(options: .activateIgnoringOtherApps)
                }
            }
            
            // Setup key event monitor for closing with Cmd+comma
            setupKeyEventMonitor()
            
            return
        }
        
        // Create the window with proper macOS sizing
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.title = "Hush Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)
        window.maxSize = NSSize(width: 800, height: 700)
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("HushSettingsWindow")
        
        // Hide from screen sharing for privacy/security
        if #available(macOS 12.0, *) {
            window.sharingType = .none
        }
        window.level = .modalPanel
        
        // Create view model and view
        let viewModel = SettingsViewModel(appState: self.appState ?? AppState())
        let settingsView = SettingsView(viewModel: viewModel)
        
        // Set content view
        window.contentView = NSHostingView(rootView: settingsView)
        
        // Setup key event monitor for closing with Cmd+comma
        setupKeyEventMonitor()
        
        // Add window close notification handler
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        
        // Save reference and show window
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        
        // Remember the frontmost app before activating
        let frontApp = NSWorkspace.shared.frontmostApplication
        
        // We need to activate briefly to show settings (as this is intentional user interaction)
        NSApp.activate(ignoringOtherApps: true)
        
        // Return focus to previous app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Use activate() directly on macOS 14+ or fall back to the options parameter
            if #available(macOS 14.0, *) {
                frontApp?.activate()
            } else {
                frontApp?.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
    
    /// Setup global key event monitor for Command+comma
    private func setupKeyEventMonitor() {
        // Remove any existing monitor
        removeKeyEventMonitor()
        
        // Create new monitor that watches for Command+comma
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Command+comma key combination
            if event.modifierFlags.contains(.command) && event.keyCode == 43 { // 43 is the key code for comma
                // Close the settings window
                self?.closeSettingsWindow()
                
                // Remove this monitor as we've handled the action
                self?.removeKeyEventMonitor()
            }
        }
    }
    
    /// Remove the key event monitor
    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    /// Handle window close notification
    @objc private func windowWillClose(_ notification: Notification) {
        // Remove the key event monitor when window closes
        removeKeyEventMonitor()
    }
    
    /// Closes the settings window
    func closeSettingsWindow() {
        settingsWindow?.close()
        removeKeyEventMonitor()
    }
    
    /// Deinitializer to clean up resources
    deinit {
        removeKeyEventMonitor()
    }
}

/// Settings view for the application
struct SettingsView: View {
    // MARK: - Properties
    
    /// The view model for settings
    @ObservedObject var viewModel: SettingsViewModel
    
    /// State for paste feedback
    @State private var showPasteFeedback = false
    
    /// State for API key visibility
    @State private var showAPIKey = false
    
    // MARK: - Body
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            apiTab
                .tabItem {
                    Label("API", systemImage: "network")
                }
            
            customPromptsTab
                .tabItem {
                    Label("Prompts", systemImage: "text.bubble")
                }
            
            memoryTab
                .tabItem {
                    Label("Memory", systemImage: "brain")
                }
            
            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // MARK: - Tab Views
    
    /// General settings tab
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("General")
                        .font(.largeTitle)
                        .fontWeight(.medium)
                    
                    Text("Configure appearance and startup behavior")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // Appearance Section
                SettingsSection(title: "Appearance") {
                    VStack(spacing: 12) {
                        SettingsRow(
                            title: "Start at login",
                            description: "Automatically launch Hush when you sign in to your Mac"
                        ) {
                            Toggle("", isOn: $viewModel.startAtLogin)
                                .toggleStyle(.switch)
                    .onChange(of: viewModel.startAtLogin) {
                        viewModel.toggleStartAtLogin()
                    }
                        }
                        
                        SettingsRow(
                            title: "Keep window on top",
                            description: "Hush window stays above other application windows"
                        ) {
                            Toggle("", isOn: $viewModel.isAlwaysOnTop)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Window opacity",
                            description: "Adjust the transparency of the Hush window"
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(viewModel.defaultOpacity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                        .frame(width: 40)
                                
                                Slider(
                                    value: $viewModel.defaultOpacity,
                                    in: Constants.UI.Opacity.range,
                                    step: 0.05
                                )
                                .frame(width: 120)
                            }
                        }
                    }
                }
                
                // Audio Features Section
                SettingsSection(title: "Audio Features") {
                    VStack(spacing: 12) {
                        SettingsRow(
                            title: "Default audio source",
                            description: "Choose the default audio input for transcription"
                        ) {
                Picker("", selection: $viewModel.audioSource) {
                                Label("Microphone", systemImage: "mic").tag(0)
                                Label("System Audio", systemImage: "speaker.wave.2").tag(1)
                }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        
                        SettingsRow(
                            title: "Show transcription viewer",
                            description: "Display real-time transcription by default. You can toggle this anytime with ⌘⇧L, or switch audio sources with ⌘⌃L"
                        ) {
                            Toggle("", isOn: $viewModel.showTranscriptionViewer)
                                .toggleStyle(.switch)
                    .onChange(of: viewModel.showTranscriptionViewer) {
                        viewModel.saveSettings()
                    }
                        }
                    }
                }
            }
            .padding(24)
            }
    }
    
    /// API configuration tab
    private var apiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
            Text("API Configuration")
                        .font(.largeTitle)
                    .fontWeight(.medium)
                
                    Text("Set up your AI service connections")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // Gemini API Section
                SettingsSection(title: "Google Gemini") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                if showAPIKey {
                                    TextField("Enter your Gemini API key", text: $viewModel.geminiApiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("Enter your Gemini API key", text: $viewModel.geminiApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                Button(action: {
                                    showAPIKey.toggle()
                                }) {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.bordered)
                                .help(showAPIKey ? "Hide API key" : "Show API key")
                            }
                            
                            HStack(spacing: 8) {
                                Button("Paste") {
                                    pasteAPIKey()
            }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .help("Paste API key from clipboard")
                                
                                Button("Save") {
                        viewModel.saveApiKey()
                    }
                    .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity, minHeight: 32)
                            }
            
            HStack {
                    if viewModel.showApiKeySaved {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Saved")
                }
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                                
                                if showPasteFeedback {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.clipboard.fill")
                                            .foregroundColor(.blue)
                                        Text("Pasted")
                                    }
                                    .foregroundColor(.blue)
                                    .transition(.opacity)
            }
            
            Spacer()
        }
    }
    
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Get your API key")
                .font(.headline)
            
                            Text("You'll need a Google AI Studio account to get your API key. It's free to get started. Click the paste button to paste your API key from the clipboard.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Link("Open Google AI Studio", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                                .font(.body)
                        }
                    }
            }
        }
            .padding(24)
        }
    }
    
    /// Custom Prompts tab
    private var customPromptsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Prompts")
                        .font(.largeTitle)
                    .fontWeight(.medium)
                
                    Text("Create and manage custom prompts for AI processing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Instructions for adding prompts
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to add prompts:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("1. Copy your prompt text to the clipboard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                        Text("2. Click 'Paste as Prompt' to add it")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                        Text("3. Click 'Select' to use it for AI processing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                // Custom Prompts Section
                SettingsSection(title: "Your Prompts") {
                    VStack(spacing: 12) {
                        // Paste button only
                HStack {
                            Button("Paste as Prompt") {
                                pasteAsNewPrompt()
                    }
                    .buttonStyle(.borderedProminent)
                            .help("Paste clipboard content as a new prompt")
            
            Spacer()
                        }
                        
                        // List of custom prompts
                        if viewModel.customPrompts.isEmpty {
                            Text("No custom prompts yet. Copy some text and click 'Paste as Prompt' to get started.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(viewModel.customPrompts) { prompt in
                                CustomPromptRow(
                                    prompt: prompt,
                                    isSelected: viewModel.selectedPromptId == prompt.id,
                                    onSelect: {
                                        viewModel.selectPrompt(prompt.id)
                                    },
                                    onDelete: {
                                        viewModel.deletePrompt(prompt.id)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
                    }
                }
                
    /// Memory management tab
    private var memoryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory")
                        .font(.largeTitle)
                        .fontWeight(.medium)
                    
                    Text("Add persistent memory for the AI to remember")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                    // Instructions for adding memories
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to add memories:")
                    .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                
                        Text("1. Copy your memory text to the clipboard")
                    .font(.caption)
                            .foregroundColor(.secondary)
                            
                        Text("2. Click 'Paste as Memory' to add it")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                        Text("3. Toggle memories on/off as needed")
                            .font(.caption)
                            .foregroundColor(.secondary)
            }
                    .padding(.top, 8)
                }
                
                // Add Memory Section
                SettingsSection(title: "Add Memory") {
                    VStack(spacing: 12) {
                        // Paste button only
            HStack {
                            Button("Paste as Memory") {
                                pasteAsNewMemory()
                }
                .buttonStyle(.borderedProminent)
                            .help("Paste clipboard content as a new memory")
                            
                            Spacer()
            }
        }
                    .padding(4)
                }
                
                // Memories List Section
                SettingsSection(title: "Your Memories") {
                    VStack(spacing: 12) {
                        if viewModel.memories.isEmpty {
                            Text("No memories added yet. Copy some text and click 'Paste as Memory' to help the AI remember important context.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                                .multilineTextAlignment(.center)
                        } else {
                            ForEach(viewModel.memories) { memory in
                                MemoryRow(
                                    memory: memory,
                                    onToggle: { enabled in
                                        viewModel.toggleMemoryEnabled(id: memory.id, enabled: enabled)
                                    },
                                    onDelete: {
                                        viewModel.deleteMemory(id: memory.id)
                                    }
                                )
                                
                                if viewModel.memories.last?.id != memory.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .padding(24)
        }
    }
    
    /// Keyboard shortcuts tab
    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
            Text("Keyboard Shortcuts")
                        .font(.largeTitle)
                        .fontWeight(.medium)
                    
                    Text("Enable or disable keyboard shortcuts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // Shortcuts Section
                SettingsSection(title: "Available Shortcuts") {
                    LazyVStack(spacing: 8) {
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.newSession, title: "New Session", shortcut: "⌘N", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.textMode, title: "Text Mode", shortcut: "⌘T", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.capture, title: "Screenshot", shortcut: "⌘H", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.delete, title: "Delete Screenshot", shortcut: "⌘D", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.process, title: "Process", shortcut: "⌘↩", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.liveMode, title: "Audio Recording", shortcut: "⌘L", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.showTranscriptViewer, title: "Toggle Transcript Viewer", shortcut: "⌘⇧L", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.toggleAudioSource, title: "Switch Audio Source", shortcut: "⌘⌃L", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.autoScroll, title: "Toggle Auto-scroll", shortcut: "⌘.", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.scrollUp, title: "Scroll Up", shortcut: "⌘↑", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.scrollDown, title: "Scroll Down", shortcut: "⌘↓", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.scrollSpeedUp, title: "Increase Scroll Speed", shortcut: "⌘⇧+", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.scrollSpeedDown, title: "Decrease Scroll Speed", shortcut: "⌘⇧-", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.moveWindow, title: "Move Window", shortcut: "⌘⇧↑/↓/←/→", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.copyResults, title: "Copy Results", shortcut: "⌘⇧C", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.toggleOpacity, title: "Toggle Opacity", shortcut: "⌘O", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.resetPosition, title: "Reset Position", shortcut: "⌘R", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.hideApp, title: "Show/Hide App", shortcut: "⌘K", viewModel: viewModel)
                        ShortcutRow(key: Constants.SettingKeys.Shortcuts.quitApp, title: "Quit App", shortcut: "⌘Q", viewModel: viewModel)
                    }
                }
                
                // Reset Section
            HStack {
                Spacer()
                    Button("Reset All to Default") {
                    viewModel.resetToDefaults()
                }
                    .buttonStyle(.bordered)
                }
                .padding(.top)
            }
            .padding(24)
        }
    }
    
    /// About tab
    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 32) {
                // App Header
                VStack(spacing: 16) {
                    // App Icon
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        // Fallback icon if AppIcon is not found
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.gradient)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text("H")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                    }
                    
                    VStack(spacing: 4) {
            Text("Hush")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
            
                        Text("Version 1.1.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("AI powered screenshot, audio transcription, and text processing for macOS")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 16)
                
                // Features Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Features")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 240), spacing: 16)
                    ], spacing: 16) {
                        FeatureCard(
                            icon: "mic.fill",
                            title: "Audio Transcription",
                            description: "Real-time transcription from microphone and system audio"
                        )
                        
                        FeatureCard(
                            icon: "camera.viewfinder",
                            title: "Screenshot Processing",
                            description: "Capture and analyze screenshots with AI"
                        )
                        
                        FeatureCard(
                            icon: "brain.head.profile",
                            title: "AI-Powered Analysis",
                            description: "Intelligent content processing with Google Gemini"
                        )
                        
                        FeatureCard(
                            icon: "text.bubble.fill",
                            title: "Live Transcript Viewer",
                            description: "View transcriptions in real-time as you speak"
                        )
                        
                        FeatureCard(
                            icon: "keyboard.fill",
                            title: "Keyboard Shortcuts",
                            description: "Comprehensive shortcuts for efficient workflow"
                        )
                        
                        FeatureCard(
                            icon: "arrow.up.arrow.down.circle.fill",
                            title: "Auto-Scroll Results",
                            description: "Automatically scroll through long content"
                        )
                        
                        FeatureCard(
                            icon: "slider.horizontal.3",
                            title: "Window Controls",
                            description: "Adjustable opacity and always-on-top options"
                        )
                        
                        FeatureCard(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Audio Source Switching",
                            description: "Quickly switch between mic and system audio"
                        )
                        
                        FeatureCard(
                            icon: "textformat",
                            title: "Text Mode",
                            description: "Direct text input for AI processing"
                        )
                        
                        FeatureCard(
                            icon: "plus.circle.fill",
                            title: "Session Management",
                            description: "Create new sessions and manage your workflow"
                        )
                    }
                }
                
                // Copyright and Links
                VStack(spacing: 16) {
                    Divider()
                    
                    VStack(spacing: 8) {
                        Text("© 2025 Hush App.")
                .font(.caption)
                            .foregroundColor(.secondary)
            
                        HStack(spacing: 20) {
                            Link("GitHub", destination: URL(string: "https://github.com/KaizoKonpaku/Hush")!)
                                .font(.caption)
            
                            Link("X", destination: URL(string: "https://x.com/KaizooKonpaku")!)
                .font(.caption)
        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Private Methods
    
    /// Pastes API key from clipboard
    private func pasteAPIKey() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string), !clipboardContent.isEmpty {
            viewModel.geminiApiKey = clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Show paste feedback
            showPasteFeedback = true
            
            // Hide feedback after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showPasteFeedback = false
            }
        }
    }
    
    /// Pastes clipboard content as a new prompt
    private func pasteAsNewPrompt() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string), !clipboardContent.isEmpty {
            let newPrompt = CustomPrompt(name: "Custom Prompt", prompt: clipboardContent)
            AppPreferences.shared.addCustomPrompt(newPrompt)
            viewModel.customPrompts = AppPreferences.shared.customPrompts
        }
    }
    
    /// Pastes clipboard content as a new memory
    private func pasteAsNewMemory() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string), !clipboardContent.isEmpty {
            viewModel.pasteAsNewMemory(content: clipboardContent)
        }
    }
}

/// A styled settings section with title and content
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

/// A settings row with title, description and control
struct SettingsRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control
    
    init(title: String, description: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 16)
            
            control
        }
        .padding(.vertical, 4)
    }
}

/// A keyboard shortcut row
struct ShortcutRow: View {
    let key: String
    let title: String
    let shortcut: String
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and shortcut in first row
        HStack {
            Text(title)
                    .font(.body)
                    .fontWeight(.medium)
            
                Spacer()
            
            Text(shortcut)
                    .font(.caption)
                    .fontWeight(.medium)
                .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.tertiaryLabelColor).opacity(0.3))
                    .cornerRadius(6)
            }
            
            // Toggle in second row
            HStack {
                Text("Enable this shortcut")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            
            Toggle("", isOn: Binding(
                get: { viewModel.shortcutKeys[key] ?? true },
                set: { newValue in 
                    var updatedShortcuts = viewModel.shortcutKeys
                    updatedShortcuts[key] = newValue
                    viewModel.shortcutKeys = updatedShortcuts
                    viewModel.saveSettings()
                    
                    // Post notification to refresh hotkeys
                    NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
                }
            ))
                .toggleStyle(.switch)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

/// A feature card view for displaying app capabilities
struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 120, maxHeight: 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Shortcuts help window controller for managing the help window
final class ShortcutsHelpWindowController {
    /// The help window instance
    private var helpWindow: NSWindow?
    
    /// Global event monitor for blocking other events when help is open
    private var eventMonitor: Any?
    
    /// Shows or hides the shortcuts help window (toggle)
    func toggleShortcutsHelp() {
        if let window = helpWindow, window.isVisible {
            closeShortcutsHelp()
        } else {
            showShortcutsHelp()
        }
    }
    
    /// Shows the shortcuts help window
    private func showShortcutsHelp() {
        // If window already exists, just bring it forward
        if let window = helpWindow {
            window.makeKeyAndOrderFront(nil)
            setupEventBlocking()
            return
        }
        
        // Create the help window with toolbar style
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties for toolbar-like appearance
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.identifier = NSUserInterfaceItemIdentifier("ShortcutsHelpWindow")
        window.isMovable = false
        window.backgroundColor = .clear
        
        // Hide from screen sharing for privacy
        if #available(macOS 12.0, *) {
            window.sharingType = .none
        }
        
        // Create the help view
        let helpView = ShortcutsHelpView {
            self.closeShortcutsHelp()
        }
        
        // Set content view
        window.contentView = NSHostingView(rootView: helpView)
        
        // Add window close notification handler
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        
        // Save reference and show window
        self.helpWindow = window
        window.makeKeyAndOrderFront(nil)
        
        // Block other events
        setupEventBlocking()
    }
    
    /// Closes the shortcuts help window
    private func closeShortcutsHelp() {
        helpWindow?.close()
        removeEventBlocking()
    }
    
    /// Sets up event blocking to prevent other shortcuts while help is open
    private func setupEventBlocking() {
        removeEventBlocking()
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Allow Cmd+Shift+? to close the help window
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 44 { // 44 is slash
                self.closeShortcutsHelp()
                return nil // Consume the event
            }
            
            // Allow Escape to close the help window
            if event.keyCode == 53 { // 53 is Escape
                self.closeShortcutsHelp()
                return nil // Consume the event
            }
            
            // Block all other keyboard events
            return nil
        }
    }
    
    /// Removes event blocking
    private func removeEventBlocking() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    /// Handle window close notification
    @objc private func windowWillClose(_ notification: Notification) {
        removeEventBlocking()
    }
    
    /// Deinitializer to clean up resources
    deinit {
        removeEventBlocking()
    }
}

/// Shortcuts help view displaying all keyboard shortcuts
struct ShortcutsHelpView: View {
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
            // Blur background similar to toolbar
            VisualEffectBlur(material: .toolTip, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Press ⌘⇧? or Esc to close")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)
                
                // Shortcuts grid - two by two layout
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 20) {
                    
                    // Essential
                    ShortcutSection(title: "Essential", shortcuts: [
                        ("⌘N", "New Session"),
                        ("⌘T", "Text Mode"),
                        ("⌘H", "Screenshot"),
                        ("⌘L", "Audio Recording"),
                        ("⌘↩", "Process"),
                        ("⌘,", "Settings")
                    ])
                    
                    // Audio & Transcription
                    ShortcutSection(title: "Audio", shortcuts: [
                        ("⌘L", "Toggle Recording"),
                        ("⌘⇧L", "Transcript Viewer"),
                        ("⌘⌃L", "Switch Audio Source")
                    ])
                    
                    // Content Management
                    ShortcutSection(title: "Content", shortcuts: [
                        ("⌘D", "Delete Screenshot"),
                        ("⌘⇧C", "Copy Results"),
                        ("⌘A", "Auto-scroll"),
                        ("⌘↑/↓", "Manual Scroll")
                    ])
                    
                    // Window Controls
                    ShortcutSection(title: "Window", shortcuts: [
                        ("⌘O", "Toggle Opacity"),
                        ("⌘R", "Reset Position"),
                        ("⌘H", "Show/Hide"),
                        ("⌘Q", "Quit")
                    ])
                    
                    // Advanced
                    ShortcutSection(title: "Advanced", shortcuts: [
                        ("⌘⇧+", "Increase Speed"),
                        ("⌘⇧-", "Decrease Speed"),
                        ("⌘⇧↑/↓/←/→", "Move Window"),
                        ("⌘⇧?", "This Help")
                    ])
                    
                    // Navigation (to balance the grid)
                    ShortcutSection(title: "Navigation", shortcuts: [
                        ("⌘←", "Previous Screenshot"),
                        ("⌘→", "Next Screenshot"),
                        ("⌘↑", "Scroll Up"),
                        ("⌘↓", "Scroll Down")
                    ])
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
        .frame(width: 750, height: 550)
    }
}

/// A compact section showing shortcuts for a category
struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 6) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    HStack {
                        Text(shortcut.0)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .frame(minWidth: 80, alignment: .leading)
                        
                        Text(shortcut.1)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Visual effect blur view for background
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

/// Custom prompt row view
struct CustomPromptRow: View {
    let prompt: CustomPrompt
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(prompt.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isSelected {
                        Text("SELECTED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                }
                
                Text(prompt.prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Select") {
                    onSelect()
                }
                .buttonStyle(.bordered)
                .disabled(isSelected)
                
                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

/// Memory row view
struct MemoryRow: View {
    let memory: MemoryEntry
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.name)
                        .font(.headline)
                    
                    Text(formatDate(memory.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { memory.isEnabled },
                        set: { onToggle($0) }
            ))
            .labelsHidden()
                    .toggleStyle(.switch)
                    
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Label(isExpanded ? "Hide" : "Show", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                    
                    HStack {
                        Spacer()
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut, value: isExpanded)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
} 
