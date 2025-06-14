import SwiftUI
import Combine

/// ViewModel for the Settings screen
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// Whether app should start at login
    @Published var startAtLogin: Bool = false
    
    /// Whether window should stay on top
    @Published var isAlwaysOnTop: Bool = true
    
    /// Default window opacity value
    @Published var defaultOpacity: Double = 1.0
    
    /// Dictionary of enabled keyboard shortcuts
    @Published var shortcutKeys: [String: Bool] = [:]
    
    /// API key for Gemini AI service
    @Published var geminiApiKey: String = ""
    
    /// Whether transcription viewer is shown
    @Published var showTranscriptionViewer: Bool = true
    
    /// Whether to show API key saved confirmation
    @Published var showApiKeySaved: Bool = false
    
    /// Whether chats should be saved locally
    @Published var saveChatsLocally: Bool = true
    
    /// Selected audio source (0 = microphone, 1 = system audio)
    @Published var audioSource: Int = 0
    
    /// Custom prompts array
    @Published var customPrompts: [CustomPrompt] = []
    
    /// Selected prompt ID
    @Published var selectedPromptId: String? = nil
    
    /// Memory entries array
    @Published var memories: [MemoryEntry] = []
    
    /// Temporary name for new memory entry
    @Published var newMemoryName: String = ""
    
    /// Temporary content for new memory entry
    @Published var newMemoryContent: String = ""
    
    // MARK: - Private Properties
    
    /// Reference to the app's global state
    private let appState: AppState
    
    /// Storage for Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    /// Reference to app preferences
    private let preferences = AppPreferences.shared
    
    // MARK: - Initialization
    
    /// Initialize settings view model with app state
    /// - Parameter appState: The app's global state
    init(appState: AppState) {
        self.appState = appState
        
        // Load initial values from app state and preferences
        loadSettings()
        
        // Set up binding between view model and app state
        setupBindings()
    }
    
    // MARK: - Private Methods
    
    /// Load settings from preferences
    private func loadSettings() {
        // Load from app state
        self.isAlwaysOnTop = appState.isAlwaysOnTop
        self.defaultOpacity = appState.windowOpacity
        
        // Load from preferences
        self.startAtLogin = preferences.startAtLogin
        self.shortcutKeys = preferences.enabledShortcuts
        self.showTranscriptionViewer = preferences.showTranscriptionViewer
        self.saveChatsLocally = preferences.saveChatsLocally
        
        // Load API key if available
        if let apiKey = preferences.geminiApiKey {
            self.geminiApiKey = apiKey
        }
        
        // Load audio source
        self.audioSource = preferences.audioSource
        
        // Load custom prompts
        self.customPrompts = preferences.customPrompts
        
        // Load selected prompt ID
        self.selectedPromptId = preferences.selectedPromptId
        
        // Load memory entries
        self.memories = preferences.memories
    }
    
    /// Set up two-way bindings between view model and app state
    private func setupBindings() {
        // When isAlwaysOnTop changes, update app state
        $isAlwaysOnTop
            .sink { [weak self] value in
                self?.appState.isAlwaysOnTop = value
            }
            .store(in: &cancellables)
        
        // When defaultOpacity changes, update app state
        $defaultOpacity
            .sink { [weak self] value in
                self?.appState.windowOpacity = value
            }
            .store(in: &cancellables)
        
        // When audio source changes, update preferences
        $audioSource
            .sink { [weak self] value in
                self?.preferences.audioSource = value
                self?.appState.audioSource = value == 0 ? .microphone : .systemAudio
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Save the current API key to secure storage
    func saveApiKey() {
        // Save API key to preferences
            preferences.geminiApiKey = geminiApiKey
        
        // Show confirmation
        showApiKeySaved = true
        
        // Hide confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showApiKeySaved = false
        }
    }
    
    /// Toggle the start at login setting
    func toggleStartAtLogin() {
        startAtLogin.toggle()
        preferences.startAtLogin = startAtLogin
    }
    
    /// Save all settings to persistent storage
    func saveSettings() {
        // Save to preferences
        preferences.isAlwaysOnTop = isAlwaysOnTop
        preferences.windowOpacity = defaultOpacity
        preferences.startAtLogin = startAtLogin
        preferences.enabledShortcuts = shortcutKeys
        preferences.showTranscriptionViewer = showTranscriptionViewer
        preferences.audioSource = audioSource
        preferences.customPrompts = customPrompts
        preferences.selectedPromptId = selectedPromptId
        preferences.saveChatsLocally = saveChatsLocally
    }
    
    /// Reset all settings to default values
    func resetToDefaults() {
        // Reset preferences
        preferences.resetToDefaults()
        
        // Reload settings from defaults
        loadSettings()
        
        // Update app state with reset values
        appState.isAlwaysOnTop = isAlwaysOnTop
        appState.windowOpacity = defaultOpacity
        
        // Notify that shortcuts have changed
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
    
    // MARK: - Custom Prompt Methods
    
    /// Select a prompt for use
    /// - Parameter id: The ID of the prompt to select
    func selectPrompt(_ id: String) {
        selectedPromptId = id
        preferences.selectedPromptId = id
    }
    
    /// Delete a prompt
    /// - Parameter id: The ID of the prompt to delete
    func deletePrompt(_ id: String) {
        preferences.deleteCustomPrompt(id: id)
        customPrompts = preferences.customPrompts
        
        // Update selected prompt if it was deleted
        if selectedPromptId == id {
            selectedPromptId = nil
        }
    }
    
    // MARK: - Memory Methods
    
    /// Paste clipboard content as a new memory with automatic naming
    /// - Parameter content: Memory content from the clipboard
    func pasteAsNewMemory(content: String) {
        // Generate a sequential name for the memory (Memory 1, Memory 2, etc.)
        let nextNumber = memories.count + 1
        let memoryName = "Memory \(nextNumber)"
        
        // Create and add the new memory
        let memory = MemoryEntry(
            name: memoryName,
            content: content
        )
        
        preferences.addMemory(memory)
        
        // Refresh memories from preferences
        self.memories = preferences.memories
    }
    
    /// Add a new memory entry
    func addMemory() {
        guard !newMemoryName.isEmpty, !newMemoryContent.isEmpty else { return }
        
        let memory = MemoryEntry(
            name: newMemoryName,
            content: newMemoryContent
        )
        
        preferences.addMemory(memory)
        
        // Refresh memories from preferences
        self.memories = preferences.memories
        
        // Reset form fields
        newMemoryName = ""
        newMemoryContent = ""
    }
    
    /// Delete a memory entry
    /// - Parameter id: ID of memory to delete
    func deleteMemory(id: String) {
        preferences.deleteMemory(id: id)
        
        // Refresh memories from preferences
        self.memories = preferences.memories
    }
    
    /// Toggle memory enabled status
    /// - Parameters:
    ///   - id: ID of memory to toggle
    ///   - enabled: New enabled state
    func toggleMemoryEnabled(id: String, enabled: Bool) {
        preferences.toggleMemoryEnabled(id: id, enabled: enabled)
        
        // Refresh memories from preferences
        self.memories = preferences.memories
    }
} 