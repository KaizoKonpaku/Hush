import Foundation
import Combine
import Security

/// Data structure representing a custom prompt
struct CustomPrompt: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var prompt: String
    var createdAt: Date
    var updatedAt: Date
    
    init(id: String = UUID().uuidString, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    mutating func update(name: String, prompt: String) {
        self.name = name
        self.prompt = prompt
        self.updatedAt = Date()
    }
}

/// Data structure representing a memory entry for AI context
struct MemoryEntry: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var content: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(id: String = UUID().uuidString, name: String, content: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    mutating func update(name: String, content: String, isEnabled: Bool) {
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.updatedAt = Date()
    }
}

/// Service that handles storing and retrieving application preferences
class AppPreferences {
    // MARK: - Keys
    private enum Keys {
        static let isAlwaysOnTop = "isAlwaysOnTop"
        static let windowOpacity = "windowOpacity"
        static let startAtLogin = "startAtLogin"
        static let enabledShortcuts = "enabledShortcuts"
        static let showTranscriptionViewer = "showTranscriptionViewer"
        static let audioSource = "audioSource"
        static let customPrompts = "customPrompts"
        static let selectedPromptId = "selectedPromptId"
        static let memories = "memories"
        static let saveChatsLocally = "saveChatsLocally"
        
        // Keychain constants
        static let keychainService = "com.hush.app"
        static let apiKeyAccount = "geminiApiKey"
    }
    
    // MARK: - Singleton Instance
    static let shared = AppPreferences()
    
    // MARK: - UserDefaults Reference
    private let defaults = UserDefaults.standard
    
    // MARK: - Private Initialization
    private init() {
        // Register default values
        registerDefaults()
    }
    
    // MARK: - Default Values Setup
    private func registerDefaults() {
        let defaultValues: [String: Any] = [
            Keys.isAlwaysOnTop: true,
            Keys.windowOpacity: 1.0,
            Keys.startAtLogin: false,
            Keys.enabledShortcuts: [:], // Empty dictionary for now
            Keys.showTranscriptionViewer: true,
            Keys.audioSource: 1 // Default to system audio (1)
        ]
        
        defaults.register(defaults: defaultValues)
    }
    
    // MARK: - Public Getters and Setters
    
    /// Get/set whether the app window should always stay on top
    var isAlwaysOnTop: Bool {
        get { defaults.bool(forKey: Keys.isAlwaysOnTop) }
        set { defaults.set(newValue, forKey: Keys.isAlwaysOnTop) }
    }
    
    /// Get/set the window opacity value (0.0-1.0)
    var windowOpacity: Double {
        get { defaults.double(forKey: Keys.windowOpacity) }
        set { defaults.set(newValue, forKey: Keys.windowOpacity) }
    }
    
    /// Get/set whether the app should start at login
    var startAtLogin: Bool {
        get { defaults.bool(forKey: Keys.startAtLogin) }
        set { 
            defaults.set(newValue, forKey: Keys.startAtLogin)
            // In a real app, this would also configure the login item
            configureLoginItem(enabled: newValue)
        }
    }
    
    /// Get/set the audio source (0 = microphone, 1 = system audio)
    var audioSource: Int {
        get { defaults.integer(forKey: Keys.audioSource) }
        set { defaults.set(newValue, forKey: Keys.audioSource) }
    }
    
    /// Get/set the enabled shortcuts dictionary
    var enabledShortcuts: [String: Bool] {
        get {
            if let data = defaults.dictionary(forKey: Keys.enabledShortcuts) as? [String: Bool] {
                return data
            }
            
            // Return default enabled shortcuts if none are saved
            return defaultEnabledShortcuts()
        }
        set { defaults.set(newValue, forKey: Keys.enabledShortcuts) }
    }
    
    /// Get/set the Gemini API key (stored in keychain)
    var geminiApiKey: String? {
        get {
            return getApiKeyFromKeychain()
        }
        set {
            if let newValue = newValue {
                saveApiKeyToKeychain(newValue)
            } else {
                deleteApiKeyFromKeychain()
            }
        }
    }
    
    /// Check if a specific shortcut is enabled
    /// - Parameter key: The shortcut identifier
    /// - Returns: Boolean indicating if the shortcut is enabled
    func isShortcutEnabled(_ key: String) -> Bool {
        return enabledShortcuts[key] ?? true // Default to enabled if not found
    }
    
    /// Enable or disable a specific shortcut
    /// - Parameters:
    ///   - key: The shortcut identifier
    ///   - enabled: Whether the shortcut should be enabled
    func setShortcutEnabled(_ key: String, enabled: Bool) {
        var shortcuts = enabledShortcuts
        shortcuts[key] = enabled
        enabledShortcuts = shortcuts
    }
    
    /// Get/set whether transcription viewer is shown
    var showTranscriptionViewer: Bool {
        get { defaults.bool(forKey: Keys.showTranscriptionViewer) }
        set { defaults.set(newValue, forKey: Keys.showTranscriptionViewer) }
    }
    
    /// Get/set custom prompts
    var customPrompts: [CustomPrompt] {
        get {
            guard let data = defaults.data(forKey: Keys.customPrompts),
                  let prompts = try? JSONDecoder().decode([CustomPrompt].self, from: data) else {
                return defaultCustomPrompts()
            }
            return prompts
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.customPrompts)
            }
        }
    }
    
    /// Get/set selected prompt ID
    var selectedPromptId: String? {
        get { defaults.string(forKey: Keys.selectedPromptId) }
        set { defaults.set(newValue, forKey: Keys.selectedPromptId) }
    }
    
    /// Get the currently selected prompt
    var selectedPrompt: CustomPrompt? {
        guard let id = selectedPromptId else { return nil }
        return customPrompts.first { $0.id == id }
    }
    
    /// Add a new custom prompt
    /// - Parameter prompt: The prompt to add
    func addCustomPrompt(_ prompt: CustomPrompt) {
        var prompts = customPrompts
        prompts.append(prompt)
        customPrompts = prompts
    }
    
    /// Update an existing custom prompt
    /// - Parameter prompt: The updated prompt
    func updateCustomPrompt(_ prompt: CustomPrompt) {
        var prompts = customPrompts
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index] = prompt
            customPrompts = prompts
        }
    }
    
    /// Delete a custom prompt
    /// - Parameter id: The ID of the prompt to delete
    func deleteCustomPrompt(id: String) {
        var prompts = customPrompts
        prompts.removeAll { $0.id == id }
        customPrompts = prompts
        
        // Clear selection if deleted prompt was selected
        if selectedPromptId == id {
            selectedPromptId = nil
        }
    }
    
    /// Get/set memory entries
    var memories: [MemoryEntry] {
        get {
            guard let data = defaults.data(forKey: Keys.memories),
                  let memories = try? JSONDecoder().decode([MemoryEntry].self, from: data) else {
                return []
            }
            return memories
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.memories)
            }
        }
    }
    
    /// Get all enabled memory entries
    var enabledMemories: [MemoryEntry] {
        return memories.filter { $0.isEnabled }
    }
    
    /// Add a new memory entry
    /// - Parameter memory: The memory to add
    func addMemory(_ memory: MemoryEntry) {
        var currentMemories = memories
        currentMemories.append(memory)
        memories = currentMemories
    }
    
    /// Update an existing memory entry
    /// - Parameter memory: The updated memory
    func updateMemory(_ memory: MemoryEntry) {
        var currentMemories = memories
        if let index = currentMemories.firstIndex(where: { $0.id == memory.id }) {
            currentMemories[index] = memory
            memories = currentMemories
        }
    }
    
    /// Delete a memory entry
    /// - Parameter id: The ID of the memory to delete
    func deleteMemory(id: String) {
        var currentMemories = memories
        currentMemories.removeAll { $0.id == id }
        memories = currentMemories
    }
    
    /// Toggle memory enabled status
    /// - Parameters:
    ///   - id: The memory ID
    ///   - enabled: Whether the memory should be enabled
    func toggleMemoryEnabled(id: String, enabled: Bool) {
        var currentMemories = memories
        if let index = currentMemories.firstIndex(where: { $0.id == id }) {
            currentMemories[index].isEnabled = enabled
            memories = currentMemories
        }
    }
    
    /// Get/set whether chats should be saved locally
    var saveChatsLocally: Bool {
        get { defaults.bool(forKey: Keys.saveChatsLocally) }
        set { defaults.set(newValue, forKey: Keys.saveChatsLocally) }
    }
    
    /// Reset all preferences to default values
    func resetToDefaults() {
        isAlwaysOnTop = true
        windowOpacity = 1.0
        startAtLogin = false
        enabledShortcuts = defaultEnabledShortcuts()
        showTranscriptionViewer = true
        customPrompts = defaultCustomPrompts()
        selectedPromptId = nil
        saveChatsLocally = true
        // Don't reset API key when resetting other preferences
    }
    
    // MARK: - Helper Methods
    
    /// Configure launch at login for the application
    /// - Parameter enabled: Whether launch at login should be enabled
    private func configureLoginItem(enabled: Bool) {
        // In a real app, this would use Login Items API or SMAppService
        print("Configuring login item: \(enabled)")
    }
    
    /// Returns the default custom prompts
    /// - Returns: Array of default custom prompts
    private func defaultCustomPrompts() -> [CustomPrompt] {
        return [
            CustomPrompt(
                id: "default-interview",
                name: "Interview Style",
                prompt: "You are an AI that helps me answer questions like I'm speaking in a real interview. Respond as if I'm the one giving the answer, using clear, confident, and conversational language — no dramatic, overly formal, or show-offy words. Keep it natural and direct, like I'm explaining things in a relaxed, professional way. Only respond to the latest question — don't repeat or summarize older context unless I ask for it."
            ),
            CustomPrompt(
                id: "default-analyze",
                name: "Analyze Content",
                prompt: "Please analyze the provided content and give me a detailed summary with key insights."
            ),
            CustomPrompt(
                id: "default-code-review",
                name: "Code Review",
                prompt: "Review this code for potential issues, improvements, and best practices. Provide specific suggestions."
            ),
            CustomPrompt(
                id: "default-explain",
                name: "Explain Simply",
                prompt: "Explain this content in simple terms that anyone can understand. Break down complex concepts."
            ),
            CustomPrompt(
                id: "default-creative",
                name: "Creative Writing",
                prompt: "Help me write creative content based on this input. Be imaginative and engaging."
            )
        ]
    }
    
    /// Returns the default enabled shortcuts configuration
    /// - Returns: Dictionary mapping shortcut keys to enabled status
    private func defaultEnabledShortcuts() -> [String: Bool] {
        return [
            "settings": true,
            "newSession": true,
            "textMode": true,
            "capture": true,
            "process": true,
            "autoScroll": true,
            "scrollUp": true,
            "scrollDown": true,
            "moveWindow": true,
            "copyResults": true,
            "toggleOpacity": true,
            "resetPosition": true,
            "hideApp": true,
            "quitApp": true,
            "activation": true,  // App activation shortcut
            "liveMode": true,    // Live mode shortcut
            "showTranscriptViewer": true, // Show transcript viewer shortcut
            "toggleAudioSource": true  // Toggle between mic and system audio
        ]
    }
    
    // MARK: - Keychain Operations
    
    /// Save API key to the keychain
    private func saveApiKeyToKeychain(_ apiKey: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.apiKeyAccount,
            kSecValueData as String: apiKey.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // First delete any existing item
        deleteApiKeyFromKeychain()
        
        // Then add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error saving API key to keychain: \(status)")
        }
    }
    
    /// Retrieve API key from the keychain
    private func getApiKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        } else {
            return nil
        }
    }
    
    /// Delete API key from the keychain
    private func deleteApiKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.apiKeyAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
