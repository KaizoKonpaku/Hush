import SwiftUI
import HotKey

let kAppSubsystem = "com.kaizokonpaku.Hush"

/// Custom window that prevents it from becoming key or main window
class NonActivatingWindow: NSWindow {
    override var canBecomeKey: Bool { 
        // Allow window to become key when chat is active
        AppState.shared.isChatActive 
    }
    override var canBecomeMain: Bool { false }
    
    override func makeKeyAndOrderFront(_ sender: Any?) {
        // Only allow becoming key when chat is active
        if AppState.shared.isChatActive {
            super.makeKeyAndOrderFront(sender)
        } else {
            orderFront(sender)
        }
    }
}

// MARK: - App Delegate

/// Application delegate for handling app lifecycle events
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Custom window for the app
    private var window: NonActivatingWindow!
    
    /// Shared app state
    private var appState = AppState.shared
    
    /// Chat session service
    private let chatSessionService = ChatSessionService.shared
    
    /// Called when the application finishes launching
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start with prohibited policy - will switch to accessory when chat is active
        NSApp.setActivationPolicy(.prohibited)
        
        createCustomWindow()
        AppInitializer.initializeApp(window: window)
        
        // Initialize chat session if chat is active
        if appState.isChatActive {
            print("🚀 App launching with active chat - starting session")
            chatSessionService.startNewSession()
        }
        
        // Set up additional observers for app lifecycle
        setupAppLifecycleObservers()
    }
    
    /// Called when the application is about to terminate
    func applicationWillTerminate(_ notification: Notification) {
        // Save any active chat session
        print("👋 App terminating - saving chat session")
        chatSessionService.closeCurrentSession()
    }
    
    /// Called when the application becomes active (foreground)
    func applicationDidBecomeActive(_ notification: Notification) {
        print("👁️ App became active")
        
        // Check if we need a new chat session when returning to foreground
        if appState.isChatActive && chatSessionService.currentSession == nil {
            print("🔄 Resuming chat session")
            chatSessionService.startNewSession()
        }
    }
    
    /// Called when the application resigns active state (background)
    func applicationWillResignActive(_ notification: Notification) {
        print("🔽 App resigning active - saving chat session")
        chatSessionService.saveCurrentSession()
    }
    
    /// Set up observers for app lifecycle events
    private func setupAppLifecycleObservers() {
        // Register for sleep/wake notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    /// Called when system is about to sleep
    @objc private func systemWillSleep() {
        print("💤 System going to sleep - saving chat session")
        chatSessionService.saveCurrentSession()
    }
    
    /// Called when system wakes from sleep
    @objc private func systemDidWake() {
        print("⏰ System woke from sleep")
        // Check if we need to restore chat session
        if appState.isChatActive && chatSessionService.currentSession == nil {
            chatSessionService.startNewSession()
        }
    }
    
    /// Creates the custom floating window
    private func createCustomWindow() {
        let contentView = ContentView(appState: appState)
        
        // Create window with borderless style using our custom non-activating window class
        window = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: Constants.UI.windowWidth, height: Constants.UI.toolbarHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties with the highest level in the system
        window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.isReleasedWhenClosed = false
        
        // Add all focus-prevention settings
        window.ignoresMouseEvents = !appState.isChatActive // Set based on chat state
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.isExcludedFromWindowsMenu = true
        window.hasShadow = true
        window.preventsApplicationTerminationWhenModal = false
        
        // Hide window from screen sharing
        window.sharingType = .none
        
        // Configure window behavior for spaces with .transient to avoid dedicated space
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
            .transient
        ]
        
        // Position window on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let xPosition = screenFrame.midX - (Constants.UI.windowWidth / 2)
            let yPosition = screen.frame.maxY - Constants.UI.toolbarHeight - 120
            window.setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
        }
        
        // Set window content without animation
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        window.contentView = NSHostingView(rootView: contentView)
        window.orderFrontRegardless() // Most aggressive way to show the window without activation
        NSAnimationContext.endGrouping()
    }
}

// MARK: - Application Initialization

/// Service responsible for initializing the application
final class AppInitializer {
    // MARK: - Static Properties
    
    /// Global activation hotkey for the app
    private static var activationHotKey: HotKey?
    
    /// Reference to the main window
    private static weak var appWindow: NSWindow?
    
    // MARK: - Initialization
    
    /// Set up the application
    static func initializeApp(window: NSWindow? = nil) {
        // Store weak reference to window for hotkey handler
        appWindow = window
        
        setupActivationShortcut()
        
        // Listen for shortcuts changes
        NotificationCenter.default.addObserver(
            forName: .shortcutsChanged,
            object: nil,
            queue: .main
        ) { _ in
            refreshActivationShortcut()
        }
    }
    
    // MARK: - Private Methods
    
    /// Set up a global hotkey for activating the app
    private static func setupActivationShortcut() {
        // Setup global hotkey for app activation (Command+Tab)
        if AppPreferences.shared.isShortcutEnabled("activation") {
        activationHotKey = HotKey(key: .tab, modifiers: [.command])
        activationHotKey?.keyDownHandler = {
                // Just order window front - no unhide or activation that could trigger space switch
                appWindow?.orderFrontRegardless()
            }
        }
    }
    
    /// Refresh the activation shortcut based on current settings
    private static func refreshActivationShortcut() {
        // Clean up existing hotkey
        activationHotKey = nil
        
        // Set up again with new settings
        setupActivationShortcut()
            }
        }
