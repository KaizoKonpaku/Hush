import SwiftUI
import HotKey

/// Protocol defining all possible hotkey actions
protocol HotKeyActionHandler {
    /// Opens the settings window
    func openSettings()
    
    /// Creates a new session
    func newSession()
    
    /// Toggles text input mode
    func toggleChat()
    
    /// Toggles recording state
    func toggleRecording()
    
    /// Captures a screenshot
    func captureScreenshot()
    
    /// Clears all screenshots
    func clearScreenshots()
    
    /// Deletes the latest screenshot
    func deleteLatestScreenshot()
    
    /// Deletes the selected screenshot
    func deleteSelectedScreenshot()
    
    /// Navigate to the next screenshot
    func navigateToNextScreenshot()
    
    /// Navigate to the previous screenshot
    func navigateToPreviousScreenshot()
    
    /// Processes screenshots with Gemini API
    func processScreenshots()
    
    /// Processes current content
    func processRecording()
    
    /// Toggles live mode
    func toggleLive()
    
    /// Toggles auto-scrolling of results
    func toggleAutoScroll()
    
    /// Adjusts auto-scroll speed
    /// - Parameter faster: Whether to increase or decrease speed
    func adjustAutoScrollSpeed(faster: Bool)
    
    /// Scrolls results in specified direction
    /// - Parameter direction: Direction to scroll
    func scrollResults(direction: ArrowDirection)
    
    /// Moves window in specified direction
    /// - Parameters:
    ///   - direction: Direction to move
    ///   - distance: Distance to move
    func moveWindowInDirection(_ direction: ArrowDirection, distance: CGFloat)
    
    /// Copies results to clipboard
    func copyResultsToClipboard()
    
    /// Toggles window opacity
    func toggleOpacity()
    
    /// Resets window position
    func resetWindowPosition()
    
    /// Hides the application
    func hideApp()
    
    /// Quits the application
    func quitApp()
    
    /// Shows keyboard shortcuts help
    func showKeyboardShortcutsHelp()
    
    /// Toggles transcript viewer
    func toggleTranscriptViewer()
    
    /// Toggles between microphone and system audio sources
    func toggleAudioSource()
}

/// Service class responsible for managing all application hotkeys
final class HotKeyManager: ObservableObject {
    // MARK: - Properties
    
    // Settings and basic app controls
    private var settingsHotKey: HotKey?
    private var newSessionHotKey: HotKey?
    private var textModeHotKey: HotKey?
    private var captureHotKey: HotKey?
    private var deleteHotKey: HotKey?
    private var processHotKey: HotKey?
    
    // Screenshot navigation
    private var navigateLeftHotKey: HotKey?
    private var navigateRightHotKey: HotKey?
    
    // Auto-scroll controls
    private var autoScrollHotKey: HotKey?
    private var scrollSpeedUpHotKey: HotKey?
    private var scrollSpeedDownHotKey: HotKey?
    private var scrollUpHotKey: HotKey?
    private var scrollDownHotKey: HotKey?
    
    // Window controls
    private var moveWindowUpHotKey: HotKey?
    private var moveWindowDownHotKey: HotKey?
    private var moveWindowLeftHotKey: HotKey?
    private var moveWindowRightHotKey: HotKey?
    private var copyResultsHotKey: HotKey?
    private var toggleOpacityHotKey: HotKey?
    private var resetPositionHotKey: HotKey?
    
    // App management
    private var toggleVisibilityHotKey: HotKey?
    private var quitAppHotKey: HotKey?
    private var helpHotKey: HotKey?
    
    // Reference to app preferences
    private let preferences = AppPreferences.shared
    
    // Add property for live mode hotkey
    private var liveModeHotKey: HotKey?
    
    // Add property for show transcript viewer hotkey
    private var showTranscriptViewerHotKey: HotKey?
    
    // Add property for toggle audio source hotkey
    private var toggleAudioSourceHotKey: HotKey?
    
    // MARK: - Initialization
    
    /// Initializes the hot key manager
    init() {}
    
    // MARK: - Public Methods
    
    /// Sets up all application hotkeys with their respective callbacks
    /// - Parameter handler: The callback handler for each hotkey action
    func setupHotKeys(handler: HotKeyActionHandler) {
        // Clean up any existing hotkeys first
        cleanup()
        
        // Setup new hotkeys
        setupAppControlHotKeys(handler: handler)
        setupScreenshotNavigationHotKeys(handler: handler)
        setupScrollHotKeys(handler: handler)
        setupWindowHotKeys(handler: handler)
        setupAppManagementHotKeys(handler: handler)
    }
    
    /// Cleans up all hotkeys when they're no longer needed
    func cleanup() {
        // Settings and controls
        settingsHotKey = nil
        newSessionHotKey = nil
        textModeHotKey = nil
        captureHotKey = nil
        deleteHotKey = nil
        processHotKey = nil
        
        // Screenshot navigation
        navigateLeftHotKey = nil
        navigateRightHotKey = nil
        
        // Auto-scroll
        autoScrollHotKey = nil
        scrollSpeedUpHotKey = nil
        scrollSpeedDownHotKey = nil
        scrollUpHotKey = nil
        scrollDownHotKey = nil
        
        // Window controls
        moveWindowUpHotKey = nil
        moveWindowDownHotKey = nil
        moveWindowLeftHotKey = nil
        moveWindowRightHotKey = nil
        copyResultsHotKey = nil
        toggleOpacityHotKey = nil
        resetPositionHotKey = nil
        
        // App management
        toggleVisibilityHotKey = nil
        quitAppHotKey = nil
        helpHotKey = nil
        
        // Live mode and transcript
        liveModeHotKey = nil
        showTranscriptViewerHotKey = nil
        
        // Toggle audio source
        toggleAudioSourceHotKey = nil
    }
    
    // MARK: - Private Methods
    
    /// Sets up app control hotkeys
    /// - Parameter handler: The action handler
    private func setupAppControlHotKeys(handler: HotKeyActionHandler) {
        // Settings (⌘,)
        // Always enable CMD+, for settings regardless of preferences
        settingsHotKey = HotKey(key: .comma, modifiers: [.command])
        settingsHotKey?.keyDownHandler = {
            handler.openSettings()
        }
        
        // NEW (⌘N)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.newSession) {
        newSessionHotKey = HotKey(key: .n, modifiers: [.command])
        newSessionHotKey?.keyDownHandler = {
            handler.newSession()
            }
        }
        
        // TEXT/CHAT (⌘T)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.textMode) {
        textModeHotKey = HotKey(key: .t, modifiers: [.command])
        textModeHotKey?.keyDownHandler = {
            handler.toggleChat()
            }
        }
        
        // CAPTURE/STOP (⌘C)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.capture) {
        captureHotKey = HotKey(key: .c, modifiers: [.command])
        captureHotKey?.keyDownHandler = {
            handler.captureScreenshot()
            }
        }
        
        // DELETE (⌘D)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.delete) {
        deleteHotKey = HotKey(key: .d, modifiers: [.command])
        deleteHotKey?.keyDownHandler = {
            handler.deleteSelectedScreenshot()
            }
        }
        
        // PROCESS (⌘Return)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.process) {
        processHotKey = HotKey(key: .return, modifiers: [.command])
        processHotKey?.keyDownHandler = {
            // Check for captured images first, if there are any, process them
            if !AppState.shared.capturedImages.isEmpty {
                handler.processScreenshots()
            } else {
            handler.processRecording()
        }
            }
        }
        
        // LIVE (⌘L)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.liveMode) {
            liveModeHotKey = HotKey(key: .l, modifiers: [.command])
            liveModeHotKey?.keyDownHandler = {
                handler.toggleLive()
            }
        }
        
        // SHOW TRANSCRIPT VIEWER (⌘⇧L)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.showTranscriptViewer) {
            showTranscriptViewerHotKey = HotKey(key: .l, modifiers: [.command, .shift])
            showTranscriptViewerHotKey?.keyDownHandler = {
                handler.toggleTranscriptViewer()
            }
        }
        
        // TOGGLE AUDIO SOURCE (⌘+Ctrl+L)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.toggleAudioSource) {
            toggleAudioSourceHotKey = HotKey(key: .l, modifiers: [.command, .control])
            toggleAudioSourceHotKey?.keyDownHandler = {
                handler.toggleAudioSource()
            }
        }
    }
    
    /// Sets up screenshot navigation hotkeys
    /// - Parameter handler: The action handler
    private func setupScreenshotNavigationHotKeys(handler: HotKeyActionHandler) {
        // Navigate left (⌘←)
        navigateLeftHotKey = HotKey(key: .leftArrow, modifiers: [.command])
        navigateLeftHotKey?.keyDownHandler = {
            handler.navigateToPreviousScreenshot()
        }
        
        // Navigate right (⌘→)
        navigateRightHotKey = HotKey(key: .rightArrow, modifiers: [.command])
        navigateRightHotKey?.keyDownHandler = {
            handler.navigateToNextScreenshot()
        }
    }
    
    /// Sets up scroll-related hotkeys
    /// - Parameter handler: The action handler
    private func setupScrollHotKeys(handler: HotKeyActionHandler) {
        // Auto-scroll toggle (⌘A)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.autoScroll) {
        autoScrollHotKey = HotKey(key: .a, modifiers: [.command])
        autoScrollHotKey?.keyDownHandler = {
            handler.toggleAutoScroll()
            }
        }
        
        // Scroll speed up (⌘⇧+)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.scrollSpeedUp) {
        scrollSpeedUpHotKey = HotKey(key: .equal, modifiers: [.command, .shift])
        scrollSpeedUpHotKey?.keyDownHandler = {
            handler.adjustAutoScrollSpeed(faster: true)
            }
        }
        
        // Scroll speed down (⌘⇧-)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.scrollSpeedDown) {
        scrollSpeedDownHotKey = HotKey(key: .minus, modifiers: [.command, .shift])
        scrollSpeedDownHotKey?.keyDownHandler = {
            handler.adjustAutoScrollSpeed(faster: false)
            }
        }
        
        // Scroll up (⌘↑)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.scrollUp) {
        scrollUpHotKey = HotKey(key: .upArrow, modifiers: [.command])
        scrollUpHotKey?.keyDownHandler = {
            handler.scrollResults(direction: .up)
            }
        }
        
        // Scroll down (⌘↓)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.scrollDown) {
        scrollDownHotKey = HotKey(key: .downArrow, modifiers: [.command])
        scrollDownHotKey?.keyDownHandler = {
            handler.scrollResults(direction: .down)
            }
        }
        }
        
    /// Sets up window management hotkeys
    /// - Parameter handler: The action handler
    private func setupWindowHotKeys(handler: HotKeyActionHandler) {
        // Move window up (⌘⇧↑)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.moveWindow) {
        moveWindowUpHotKey = HotKey(key: .upArrow, modifiers: [.command, .shift])
        moveWindowUpHotKey?.keyDownHandler = {
            handler.moveWindowInDirection(.up, distance: Constants.UI.Movement.standardDistance)
        }
        
        // Move window down (⌘⇧↓)
        moveWindowDownHotKey = HotKey(key: .downArrow, modifiers: [.command, .shift])
        moveWindowDownHotKey?.keyDownHandler = {
            handler.moveWindowInDirection(.down, distance: Constants.UI.Movement.standardDistance)
        }
        
        // Move window left (⌘⇧←)
        moveWindowLeftHotKey = HotKey(key: .leftArrow, modifiers: [.command, .shift])
        moveWindowLeftHotKey?.keyDownHandler = {
            handler.moveWindowInDirection(.left, distance: Constants.UI.Movement.standardDistance)
        }
        
        // Move window right (⌘⇧→)
        moveWindowRightHotKey = HotKey(key: .rightArrow, modifiers: [.command, .shift])
        moveWindowRightHotKey?.keyDownHandler = {
            handler.moveWindowInDirection(.right, distance: Constants.UI.Movement.standardDistance)
            }
        }
        
        // Copy results (⌘⇧C)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.copyResults) {
        copyResultsHotKey = HotKey(key: .c, modifiers: [.command, .shift])
        copyResultsHotKey?.keyDownHandler = {
            handler.copyResultsToClipboard()
            }
        }
        
        // Toggle opacity (⌘O)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.toggleOpacity) {
        toggleOpacityHotKey = HotKey(key: .o, modifiers: [.command])
        toggleOpacityHotKey?.keyDownHandler = {
            handler.toggleOpacity()
            }
        }
        
        // Reset position (⌘R)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.resetPosition) {
        resetPositionHotKey = HotKey(key: .r, modifiers: [.command])
        resetPositionHotKey?.keyDownHandler = {
            handler.resetWindowPosition()
            }
        }
        }
        
    /// Sets up app management hotkeys
    /// - Parameter handler: The action handler
    private func setupAppManagementHotKeys(handler: HotKeyActionHandler) {
        // Toggle app visibility (⌘H)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.hideApp) {
        toggleVisibilityHotKey = HotKey(key: .h, modifiers: [.command])
            toggleVisibilityHotKey?.keyDownHandler = { [weak self] in
                self?.toggleAppVisibility()
            }
        } 
        
        // Quit app (⌘Q)
        if preferences.isShortcutEnabled(Constants.SettingKeys.Shortcuts.quitApp) {
        quitAppHotKey = HotKey(key: .q, modifiers: [.command])
        quitAppHotKey?.keyDownHandler = {
            handler.quitApp()
            }
        }
        
        // Help (⌘?)
        helpHotKey = HotKey(key: .slash, modifiers: [.command, .shift])
        helpHotKey?.keyDownHandler = {
            handler.showKeyboardShortcutsHelp()
        }
    }
    
    /// Toggles app visibility without stealing focus when unhiding
    private func toggleAppVisibility() {
        // Get reference to the main window
        guard let window = NSApp.windows.first else { return }
        
        if window.isVisible {
            // Hide the window
            window.orderOut(nil)
        } else {
            // Show the window without activating the app
            window.orderFrontRegardless()
        }
    }
} 
