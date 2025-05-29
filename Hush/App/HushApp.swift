import SwiftUI
import HotKey

let kAppSubsystem = "com.kaizokonpaku.Hush"

/// Custom window that prevents it from becoming key or main window
class NonActivatingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - App Delegate

/// Application delegate for handling app lifecycle events
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Custom window for the app
    private var window: NonActivatingWindow!
    
    /// Shared app state
    private var appState = AppState.shared
    
    /// Called when the application finishes launching
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to prohibited - prevents Space switching
        NSApp.setActivationPolicy(.prohibited)
        
        createCustomWindow()
        AppInitializer.initializeApp(window: window)
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
        window.ignoresMouseEvents = true // Always ignore mouse events
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
