import SwiftUI
import Combine

/// Audio source type for recording
enum AudioSourceType {
    case microphone
    case systemAudio
}

/// Global application state model that holds the app's shared data
final class AppState: ObservableObject {
    // MARK: - Singleton
    
    /// Shared instance for global access
    static let shared = AppState()
    
    // MARK: - Recording State
    
    /// Current audio source for recording
    @Published var audioSource: AudioSourceType = .microphone {
        didSet {
            // Persist setting when changed
            AppPreferences.shared.audioSource = audioSource == .microphone ? 0 : 1
        }
    }
    
    /// Whether audio recording is currently active
    @Published var isRecording: Bool = false
    
    /// Whether processing of recording or text is in progress
    @Published var isProcessing: Bool = false
    
    /// Whether streaming data is being received
    @Published var isStreaming: Bool = false
    
    /// Whether live mode is active
    @Published var isLiveMode: Bool = false
    
    // MARK: - Transcription State
    
    /// Whether audio transcription is active
    @Published var isTranscribing: Bool = false
    
    /// Current transcript text
    @Published var transcriptText: String = ""
    
    /// Whether to show the transcript view
    @Published var showTranscript: Bool = false
    
    // MARK: - Screenshot State
    
    /// Array of captured screenshot images
    @Published var capturedImages: [CapturedImage] = []
    
    /// Whether the app is currently capturing screenshots
    @Published var isCapturingScreenshots: Bool = false
    
    // MARK: - UI State
    
    /// Whether text input mode is active
    @Published var isChatActive: Bool = false {
        didSet {
            // Only ignore mouse events when chat is not active
            for window in NSApp.windows where window.isVisible {
                window.ignoresMouseEvents = !isChatActive
                
                if isChatActive {
                    // Switch to accessory mode when chat is active
                    NSApp.setActivationPolicy(.accessory)
                    // Make window key and order front to get focus
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Switch back to prohibited mode when chat is inactive
                    NSApp.setActivationPolicy(.prohibited)
                }
            }
        }
    }
    
    /// Whether results panel should be displayed
    @Published var showResults: Bool = false
    
    /// Text input from the chat field
    @Published var chatText: String = ""
    
    /// Whether the window should stay on top of other windows
    @Published var isAlwaysOnTop: Bool = true {
        didSet {
            // Persist setting when changed
            AppPreferences.shared.isAlwaysOnTop = isAlwaysOnTop
            
            // Update window level for all windows
            updateWindowLevel()
        }
    }
    
    /// Window opacity value (0.0-1.0)
    @Published var windowOpacity: Double = 1.0 {
        didSet {
            // Persist setting when changed
            AppPreferences.shared.windowOpacity = windowOpacity
            
            // Update opacity for all windows
            updateWindowOpacity()
        }
    }
    
    // MARK: - Scroll State
    
    /// Current scroll position in results view
    @Published var scrollPosition: Int = 0
    
    /// Whether auto-scrolling is enabled for results
    @Published var isAutoScrollEnabled: Bool = false
    
    /// Speed of auto-scrolling (pixels per tick)
    @Published var autoScrollSpeed: Double = Constants.UI.AutoScroll.defaultSpeed
    
    // MARK: - Content
    
    /// Current content in the results panel
    @Published var resultContent: String = ""
    
    // MARK: - Private Properties
    
    /// Set of cancellables for managing subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes app state and loads persistent settings
    init() {
        setupInitialState()
    }
    
    // MARK: - Private Methods
    
    /// Loads initial state from user preferences
    private func setupInitialState() {
        let preferences = AppPreferences.shared
        isAlwaysOnTop = preferences.isAlwaysOnTop
        windowOpacity = preferences.windowOpacity
        audioSource = preferences.audioSource == 0 ? .microphone : .systemAudio
    }
    
    /// Updates window level for all app windows
    private func updateWindowLevel() {
        for window in NSApp.windows {
            // Always use .screenSaver level to stay on top of everything
            // If not always on top, use .floating which is still above normal windows
            // but allows full-screen apps to cover it
            window.level = isAlwaysOnTop ? .screenSaver : .floating
        }
    }
    
    /// Updates window opacity for all app windows
    private func updateWindowOpacity() {
        for window in NSApp.windows {
            window.alphaValue = windowOpacity
        }
    }
    
    // MARK: - Public Methods
    
    /// Resets app to initial state
    func resetToInitialState() {
        isRecording = false
        isProcessing = false
        isStreaming = false
        isLiveMode = false
        isChatActive = false
        showResults = false
        chatText = ""
        capturedImages = []
        
        // Reset transcription state
        isTranscribing = false
        transcriptText = ""
        showTranscript = false
        
        // Ignore mouse events for all windows since isChatActive is false
        for window in NSApp.windows where window.isVisible {
            window.ignoresMouseEvents = true
        }
        
        // Note: Memory entries in AppPreferences are preserved intentionally
        // as they should persist between sessions
    }
    
    /// Add a new captured screenshot
    /// - Parameter image: The NSImage to add
    func addCapturedImage(_ image: NSImage) {
        let capturedImage = CapturedImage(image: image)
        capturedImages.append(capturedImage)
        // Select the newly added image
        selectLastScreenshot()
    }
    
    /// Clear all captured screenshots
    func clearCapturedImages() {
        capturedImages = []
    }
    
    /// Helper method to load sample content for testing
    func loadSampleContent() {
        resultContent = """
        # Sample Results
        
        This is a sample result that would normally come from processing your recording.
        
        When you have the Gemini API configured, you'll see actual AI-generated responses here.
        
        ## Features
        
        - Streaming responses
        - Auto-scrolling
        - Keyboard shortcuts
        """
    }
    
    /// Delete the most recently added screenshot
    func deleteLatestScreenshot() {
        if !capturedImages.isEmpty {
            capturedImages.removeLast()
        }
    }
    
    /// Delete the selected screenshot
    func deleteSelectedScreenshot() {
        if let index = capturedImages.firstIndex(where: { $0.isSelected }) {
            capturedImages.remove(at: index)
            
            // If we have images left, select the last one or the one at the same index
            if !capturedImages.isEmpty {
                let newIndex = min(index, capturedImages.count - 1)
                selectScreenshot(at: newIndex)
            }
        } else {
            // If no screenshot is selected, delete the last one
            deleteLatestScreenshot()
        }
    }
    
    /// Select a screenshot at the specified index
    /// - Parameter index: The index of the screenshot to select
    func selectScreenshot(at index: Int) {
        guard index >= 0 && index < capturedImages.count else { return }
        
        // Create a new array with updated selection state
        var updatedImages = capturedImages
        
        // First deselect all images
        for i in 0..<updatedImages.count {
            updatedImages[i].isSelected = (i == index)
        }
        
        // Update the array to trigger UI refresh
        capturedImages = updatedImages
    }
    
    /// Select the next screenshot (for right arrow key)
    func selectNextScreenshot() {
        guard !capturedImages.isEmpty else { return }
        
        let currentIndex = capturedImages.firstIndex(where: { $0.isSelected }) ?? -1
        let nextIndex = (currentIndex + 1) % capturedImages.count
        selectScreenshot(at: nextIndex)
    }
    
    /// Select the previous screenshot (for left arrow key)
    func selectPreviousScreenshot() {
        guard !capturedImages.isEmpty else { return }
        
        let currentIndex = capturedImages.firstIndex(where: { $0.isSelected }) ?? capturedImages.count
        let prevIndex = (currentIndex - 1 + capturedImages.count) % capturedImages.count
        selectScreenshot(at: prevIndex)
    }
    
    /// Select the last screenshot in the list
    func selectLastScreenshot() {
        if !capturedImages.isEmpty {
            selectScreenshot(at: capturedImages.count - 1)
        }
    }
} 