import SwiftUI
import Combine

/// ViewModel for the main application screen
final class MainViewModel: ObservableObject, HotKeyActionHandler {
    // MARK: - Published Properties
    
    /// Structured content from streaming response
    @Published var structuredContent = StreamContent()
    
    // MARK: - Dependencies
    
    /// Shared app state
    @ObservedObject private var appState: AppState
    
    /// Manager for keyboard shortcuts
    private var hotKeyManager = HotKeyManager()
    
    /// Controller for settings window
    private let settingsController = SettingsWindowController()
    
    /// Controller for shortcuts help window
    private let shortcutsHelpController = ShortcutsHelpWindowController()
    
    /// Service for AI interactions
    private let geminiService = GeminiService.shared
    
    /// Service for screenshot capture
    private let screenshotService = ScreenshotService.shared
    
    /// Service for audio transcription
    private let transcriptionService = TranscriptionService.shared
    
    // MARK: - Private Properties
    
    /// Set of cancellables for managing subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Timer for auto-scrolling functionality
    private var autoScrollTimer: Timer?
    
    // MARK: - Initialization
    
    /// Initializes the view model with app state
    /// - Parameter appState: The shared app state
    init(appState: AppState) {
        self.appState = appState
        setupHotKeys()
        
        // Listen for shortcut changes from settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsChanged),
            name: .shortcutsChanged,
            object: nil
        )
        
        // Subscribe to transcription updates
        setupTranscriptionSubscription()
    }
    
    /// Called when shortcuts are changed in settings
    @objc private func shortcutsChanged() {
        // Re-setup hotkeys
        refreshHotKeys()
    }
    
    // MARK: - Lifecycle Methods
    
    /// Sets up keyboard shortcuts
    func setupHotKeys() {
        hotKeyManager.setupHotKeys(handler: self)
    }
    
    /// Refreshes the hotkey configuration after settings changes
    func refreshHotKeys() {
        // Clean up and re-register all hotkeys
        hotKeyManager.cleanup()
        hotKeyManager.setupHotKeys(handler: self)
    }
    
    /// Sets up subscription to transcription service updates
    private func setupTranscriptionSubscription() {
        transcriptionService.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] transcript in
                self?.appState.transcriptText = transcript
            }
            .store(in: &cancellables)
        
        transcriptionService.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                self?.appState.isTranscribing = isRecording
            }
            .store(in: &cancellables)
    }
    
    /// Cleans up resources when view model is no longer needed
    func cleanup() {
        stopAutoScroll()
        hotKeyManager.cleanup()
        
        // Stop transcription if active
        if appState.isTranscribing {
            transcriptionService.stopRecording()
        }
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI Action Methods
    
    /// Opens the settings window
    func openSettings() {
        // Toggle settings window
        let settingsWindows = NSApp.windows.filter { 
            $0.title.contains("Settings") || 
            $0.identifier?.rawValue.contains("Settings") == true || 
            $0.windowController?.windowNibName?.contains("Settings") == true 
        }
        
        if let existingWindow = settingsWindows.first, existingWindow.isVisible {
            // Settings window is open, close it
            existingWindow.close()
        } else {
            // Open settings window
        settingsController.showSettingsWindow(appState: appState)
        }
    }
    
    /// Creates a new session and resets app state
    func newSession() {
        // Stop any ongoing streaming and processing
        appState.isProcessing = false
        appState.isStreaming = false
        
        // Stop transcription if active
        if appState.isTranscribing {
            transcriptionService.stopRecording()
        }
        
        // Stop system audio recording if active
        if SystemAudioRecorder.shared.isRecording {
            SystemAudioRecorder.shared.stopRecording()
        }
        
        // Cancel any ongoing streaming request in GeminiService
        geminiService.cancelStreaming()
        
        // Clear content before resetting state
        structuredContent = StreamContent()
        
        // Reset app state to initial state
        appState.resetToInitialState()
    }
    
    /// Toggles chat mode
    func toggleChat() {
        // Toggle chat state
        appState.isChatActive.toggle()
        
        // Mouse events are now handled in the AppState didSet observer for isChatActive
            }
    
    /// Toggles recording state
    func toggleRecording() {
        appState.isRecording.toggle()
        
        // If we stop recording, also stop any processing
        if !appState.isRecording {
            appState.isProcessing = false
            appState.showResults = false
        }
    }
    
    /// Captures a screenshot from the screen
    func captureScreenshot() {
        // Capture a full screen screenshot
        screenshotService.captureScreenshot(type: .full) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let image):
                // Add the captured image to the app state
                self.appState.addCapturedImage(image)
            case .failure(let error):
                // Handle error - could add an error state to AppState
                print("Screenshot capture failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Clears all captured screenshots
    func clearScreenshots() {
        appState.clearCapturedImages()
    }
    
    /// Processes captured screenshots with Gemini API
    func processScreenshots() {
        guard !appState.capturedImages.isEmpty else { return }
        
        // Set processing state
        appState.isProcessing = true
        appState.isStreaming = true
        appState.showResults = true
        
        // Clear previous result before streaming new content
        appState.resultContent = ""
        structuredContent = StreamContent()
        
        // Extract NSImages from CapturedImage objects
        let images = appState.capturedImages.map { $0.image }
        
        // Determine the prompt to use for the API request
        var prompt = "These are screenshots from my screen. Please analyze what you see and describe the content in detail. and provide implementation to the problem in the language of the code specified in the screenshot."
        
        // Check for custom prompt
        if let selectedPrompt = AppPreferences.shared.selectedPrompt {
            prompt = selectedPrompt.prompt
        }
        
        // Check for available text inputs (prioritize chat text, then transcript)
        if appState.isChatActive && !appState.chatText.isEmpty {
            // Combine custom prompt with chat text
            prompt = AppPreferences.shared.selectedPrompt != nil ? "\(prompt)\n\nUser input: \(appState.chatText)" : appState.chatText
        } else if !appState.transcriptText.isEmpty {
            // Combine custom prompt with transcription text
            let transcriptPrompt = AppPreferences.shared.selectedPrompt != nil ? "\(prompt)\n\nTranscription: \(appState.transcriptText)" : "Here's a transcription of audio along with screenshots. Please analyze both and respond accordingly:\n\nTranscription: \(appState.transcriptText)\n\nFor the screenshots: \(prompt)"
            prompt = transcriptPrompt
        }
        
        // Add memory context if available
        let enabledMemories = AppPreferences.shared.enabledMemories
        if !enabledMemories.isEmpty {
            var memoryContext = "Important context to remember:\n\n"
            
            for (index, memory) in enabledMemories.enumerated() {
                memoryContext += "Memory \(index+1) - \(memory.name): \(memory.content)"
                
                // Add a separator between memories
                if index < enabledMemories.count - 1 {
                    memoryContext += "\n\n"
                }
            }
            
            // Add memory context to the beginning of the prompt
            prompt = "\(memoryContext)\n\n---\n\n\(prompt)"
        }
        
        if geminiService.isConfigured {
            // Use the structured content streaming API with images
            geminiService.generateStructuredStreamingContent(
                prompt: prompt,
                images: images,
                onUpdate: { [weak self] content in
                    guard let self = self else { return }
                    
                    // Update the structured content
                    self.structuredContent = content
                    
                    // For backward compatibility, also update the plain text result
                    if let firstMarkdown = content.items.first(where: {
                        if case .markdown = $0.value { return true } else { return false }
                    }),
                       case .markdown(let entry) = firstMarkdown.value {
                        self.appState.resultContent = entry.content
                    }
                    
                    // Ensure streaming flag is set during streaming
                    self.appState.isStreaming = !content.finished
                    
                    // Enable auto-scroll only when streaming completes
                    if content.finished && !self.appState.isAutoScrollEnabled {
                        self.appState.isAutoScrollEnabled = true
                        self.startAutoScroll()
                    }
                    
                    // Update processing state when finished
                    if content.finished {
                        self.appState.isProcessing = false
                        
                        // Clear inputs after processing
                        if self.appState.isChatActive {
                            self.appState.chatText = ""
                        }
                    }
                },
                onError: { [weak self] error in
                    guard let self = self else { return }
                    // Show error in the results
                    self.appState.resultContent = "Error: \(error.localizedDescription)"
                    self.appState.isProcessing = false
                    self.appState.isStreaming = false
                    
                    // Also update structured content with error
                    var errorContent = StreamContent()
                    errorContent.errors.append(IdentifiableError(error))
                    errorContent.finished = true
                    self.structuredContent = errorContent
                }
            )
        } else {
            // If API not configured, show error message
            let apiKeyMessage = """
            # ⚠️ API Key Not Configured
            
            Please add your Gemini API key in the settings (⌘,) to use AI features.
            
            1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey) to get your API key
            2. Open Settings → API tab
            3. Enter your API key and save
            """
            
            appState.resultContent = apiKeyMessage
            
            // Update structured content with the error message
            var errorContent = StreamContent()
            var ids: any IdentifierGenerator = IncrementalIdentifierGenerator.create()
            errorContent.items.append(.init(ids: &ids, value: .markdown(MarkdownEntry(content: apiKeyMessage))))
            errorContent.finished = true
            structuredContent = errorContent
            
            // Complete processing and streaming
            appState.isProcessing = false
            appState.isStreaming = false
        }
    }
    
    /// Determines if there is content to process
    /// - Returns: Whether processing can be performed
    func canProcess() -> Bool {
        return appState.isRecording || 
              (!appState.chatText.isEmpty && appState.isChatActive) || 
              !appState.transcriptText.isEmpty // Check for transcript text regardless of viewer visibility
    }
    
    /// Processes current recording or text input
    func processRecording() {
        // Only process if there's something to process
        guard canProcess() else { return }
        
        // Process recording action
        appState.isProcessing = true
        
        // Reset auto-scroll to default state for new results
        stopAutoScroll()
        appState.isAutoScrollEnabled = false
        appState.autoScrollSpeed = Constants.UI.AutoScroll.defaultSpeed
        
        if appState.isRecording {
            // Handle recording processing (for now just use sample content)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.appState.loadSampleContent()
                self.appState.showResults = true
                self.appState.isProcessing = false
            }
        } else if !appState.chatText.isEmpty {
            // Process chat text using AI service
            processTextWithAI(appState.chatText)
        } else if !appState.transcriptText.isEmpty {
            // Check if we should process with screenshots
            if !appState.capturedImages.isEmpty {
                processScreenshots() // This will now include transcript text
            } else {
                // Process transcript text using AI service
                processTextWithAI(appState.transcriptText)
            }
        }
    }
    
    /// Submits the current message text
    func sendMessage() {
        if !appState.chatText.isEmpty {
            if !appState.capturedImages.isEmpty {
                // If there are screenshots, process them with the text prompt
                processScreenshots()
            } else {
                // Process text only
            processTextWithAI(appState.chatText)
            }
        }
    }
    
    // MARK: - AI Processing
    
    /// Processes text input with the AI service
    /// - Parameter text: The text to process
    private func processTextWithAI(_ text: String) {
        // Set processing and streaming state
        appState.isProcessing = true
        appState.isStreaming = true
        appState.showResults = true
        
        // Clear previous result before streaming new content
        appState.resultContent = ""
        structuredContent = StreamContent()
        
        // Store if this was called from transcript to avoid clearing it
        let isFromTranscript = text == appState.transcriptText
        
        // Build the prompt with custom prompt if selected
        var finalPrompt = text
        if let selectedPrompt = AppPreferences.shared.selectedPrompt {
            finalPrompt = "\(selectedPrompt.prompt)\n\nUser input: \(text)"
        }
        
        // Add memory context if available
        let enabledMemories = AppPreferences.shared.enabledMemories
        if !enabledMemories.isEmpty {
            var memoryContext = "Important context to remember:\n\n"
            
            for (index, memory) in enabledMemories.enumerated() {
                memoryContext += "Memory \(index+1) - \(memory.name): \(memory.content)"
                
                // Add a separator between memories
                if index < enabledMemories.count - 1 {
                    memoryContext += "\n\n"
                }
            }
            
            // Add memory context to the beginning of the prompt
            finalPrompt = "\(memoryContext)\n\n---\n\n\(finalPrompt)"
        }
        
        if geminiService.isConfigured {
            // Use the structured content streaming API
            geminiService.generateStructuredStreamingContent(
                prompt: finalPrompt,
                onUpdate: { [weak self] content in
                    guard let self = self else { return }
                    
                    // Update the structured content
                    self.structuredContent = content
                    
                    // For backward compatibility, also update the plain text result
                    if let firstMarkdown = content.items.first(where: {
                        if case .markdown = $0.value { return true } else { return false }
                    }),
                       case .markdown(let entry) = firstMarkdown.value {
                        self.appState.resultContent = entry.content
                    }
                    
                    // Ensure streaming flag is set during streaming
                    self.appState.isStreaming = !content.finished
                    
                    // Enable auto-scroll only when streaming completes
                    if content.finished && !self.appState.isAutoScrollEnabled {
                        self.appState.isAutoScrollEnabled = true
                        self.startAutoScroll()
                    }
                    
                    // Update processing state when finished
                    if content.finished {
                    self.appState.isProcessing = false
                    
                        // Clear the input field when complete, but only if from chat
                        if !isFromTranscript {
                    self.appState.chatText = ""
                        }
                    }
                },
                onError: { [weak self] error in
                    guard let self = self else { return }
                    // Show error in the results
                    self.appState.resultContent = "Error: \(error.localizedDescription)"
                    self.appState.isProcessing = false
                    self.appState.isStreaming = false
                    
                    // Also update structured content with error
                    var errorContent = StreamContent()
                    errorContent.errors.append(IdentifiableError(error))
                    errorContent.finished = true
                    self.structuredContent = errorContent
                }
            )
        } else {
            // If API not configured, show error message
            let apiKeyMessage = """
            # ⚠️ API Key Not Configured
            
            Please add your Gemini API key in the settings (⌘,) to use AI features.
            
            1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey) to get your API key
            2. Open Settings → API tab
            3. Enter your API key and save
            """
            
            appState.resultContent = apiKeyMessage
            
            // Update structured content with the error message
            var errorContent = StreamContent()
            var ids: any IdentifierGenerator = IncrementalIdentifierGenerator.create()
            errorContent.items.append(.init(ids: &ids, value: .markdown(MarkdownEntry(content: apiKeyMessage))))
            errorContent.finished = true
            structuredContent = errorContent
            
            // Complete processing and streaming
            appState.isProcessing = false
            appState.isStreaming = false
        }
    }
    
    // MARK: - Auto-Scroll Methods
    
    /// Toggles auto-scrolling functionality
    func toggleAutoScroll() {
        appState.isAutoScrollEnabled.toggle()
        
        if appState.isAutoScrollEnabled {
            startAutoScroll()
        } else {
            stopAutoScroll()
        }
        
        // Print debug info
        print("Auto-scroll toggled: \(appState.isAutoScrollEnabled)")
    }
    
    /// Adjusts auto-scroll speed
    /// - Parameter faster: Whether to increase or decrease speed
    func adjustAutoScrollSpeed(faster: Bool) {
        if faster {
            appState.autoScrollSpeed = min(
                Constants.UI.AutoScroll.maxSpeed,
                appState.autoScrollSpeed + Constants.UI.AutoScroll.speedIncrement
            )
            print("Increased scroll speed to \(appState.autoScrollSpeed)")
        } else {
            appState.autoScrollSpeed = max(
                Constants.UI.AutoScroll.minSpeed,
                appState.autoScrollSpeed - Constants.UI.AutoScroll.speedDecrement
            )
            print("Decreased scroll speed to \(appState.autoScrollSpeed)")
        }
        
        // If auto-scroll was disabled, enable it
        if !appState.isAutoScrollEnabled && appState.showResults {
            appState.isAutoScrollEnabled = true
            startAutoScroll()
        }
    }
    
    /// Starts the auto-scroll timer
    private func startAutoScroll() {
        // Only start auto-scroll if NOT streaming
        if appState.isStreaming {
            return
        }
        
        // Cancel existing timer if any
        stopAutoScroll()
        
        // Create a new timer that fires frequently on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.autoScrollTimer = Timer.scheduledTimer(
                withTimeInterval: Constants.UI.AutoScroll.timerInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performAutoScroll()
            }
            
            // Make sure the timer doesn't get invalidated when the run loop is busy
            RunLoop.current.add(self.autoScrollTimer!, forMode: .common)
            
            print("Auto-scroll timer started")
        }
    }
    
    /// Stops the auto-scroll timer
    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    /// Performs auto-scrolling action
    private func performAutoScroll() {
        guard appState.isAutoScrollEnabled && appState.showResults else { return }
        
        // Get current window to find the scroll view
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        
        // Try to find the results scroll view
        if let scrollView = findResultsScrollView(in: window) {
            // Current position
            let currentPosition = scrollView.documentVisibleRect.origin
            
            // Calculate new position for continuous scrolling
            var newPosition = currentPosition
            newPosition.y += appState.autoScrollSpeed
            
            // Check if we've reached the bottom
            let maxScroll = scrollView.documentView?.frame.height ?? 0
            let visibleHeight = scrollView.frame.height
            
            if newPosition.y > maxScroll - visibleHeight {
                newPosition.y = maxScroll - visibleHeight
                
                // We've reached the bottom, so stop auto-scrolling
                if newPosition.y <= currentPosition.y + 0.1 {
                    return
                }
            }
            
            // Use animator for smoother scrolling effect
            DispatchQueue.main.async {
                // No animation for smoother scrolling
                scrollView.documentView?.scroll(newPosition)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
    
    /// Finds the results scroll view with multiple fallback mechanisms
    /// - Parameter window: The window to search in
    /// - Returns: The results scroll view, or nil if none exists
    private func findResultsScrollView(in window: NSWindow) -> NSScrollView? {
        // First try to find by accessibility identifier
        if let scrollView = ScrollViewFinder.findScrollView(in: window.contentView, withIdentifier: "resultsScrollView") {
            return scrollView
        }
        
        // If that fails, get all scroll views
        let allScrollViews = ScrollViewFinder.findAllScrollViews(in: window.contentView)
        
        // Early return if no scroll views found
        if allScrollViews.isEmpty {
            return nil
        }
        
        // Count visible components to determine which scroll view is the results view
        var visibleSections = 0
        
        // Add 1 if transcript is visible
        if appState.showTranscript {
            visibleSections += 1
        }
        
        // Add 1 if chat is active
        if appState.isChatActive {
            visibleSections += 1
        }
        
        // Add 1 if screenshots are visible
        if !appState.capturedImages.isEmpty {
            visibleSections += 1
        }
        
        // Add 1 if results are visible
        if appState.showResults {
            visibleSections += 1
        }
        
        // If we have transcript and results visible, the results view should be after the transcript view
        if appState.showTranscript && appState.showResults {
            // Calculate index based on visible components
            // The last scroll view should be the results view, accounting for transcript
            if allScrollViews.count >= 2 {
            return allScrollViews.last
        }
        }
        
        // If we have screenshots visible but no transcript
        if !appState.capturedImages.isEmpty && !appState.showTranscript && appState.showResults {
            // The results view should be after the screenshots
            if allScrollViews.count >= 2 {
                return allScrollViews.last
            }
        }
        
        // If just transcript or just results (but not both) or other simple case
        if visibleSections == 1 && allScrollViews.count == 1 {
        return allScrollViews.first
        }
        
        // Default to the last scroll view if we can't determine with certainty
        return allScrollViews.last
    }
    
    // MARK: - Content Navigation Methods
    
    /// Scrolls results view in specified direction
    /// - Parameter direction: Direction to scroll
    func scrollResults(direction: ArrowDirection) {
        guard appState.showResults else { return }
        
        // Get current window to find the scroll view
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        
        // Try to find the results scroll view
        if let scrollView = findResultsScrollView(in: window) {
            // Use ScrollViewFinder utility to scroll without animation
            let amount = Constants.UI.Movement.scrollAmount
            
            // Current position
            let currentPosition = scrollView.documentVisibleRect.origin
            var newPosition = currentPosition
            
            // Adjust position based on direction
            switch direction {
            case .up:
                newPosition.y = max(0, currentPosition.y - amount)
                print("Scrolling up to y=\(newPosition.y)")
            case .down:
                let maxScroll = scrollView.documentView?.frame.height ?? 0
                let visibleHeight = scrollView.frame.height
                newPosition.y = min(maxScroll - visibleHeight, currentPosition.y + amount)
                print("Scrolling down to y=\(newPosition.y), max=\(maxScroll - visibleHeight)")
            default:
                break // Left/right not applicable for this scroll view
            }
            
            // Apply scroll - disable auto-scroll if manual scrolling is performed
            if newPosition != currentPosition {
                if appState.isAutoScrollEnabled {
                    appState.isAutoScrollEnabled = false
                    stopAutoScroll()
                }
                
                // Scroll with dispatching to main thread
                DispatchQueue.main.async {
            // Scroll without animation
            scrollView.documentView?.scroll(newPosition)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
        }
    }
    
    /// Copies the results content to the clipboard
    func copyResultsToClipboard() {
        guard !appState.resultContent.isEmpty else { return }
        
        // Copy to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.resultContent, forType: .string)
    }
    
    // MARK: - Window Management Methods
    
    /// Moves the window in the specified direction
    /// - Parameters:
    ///   - direction: Direction to move window
    ///   - distance: Distance to move in points
    func moveWindowInDirection(_ direction: ArrowDirection, distance: CGFloat) {
        // Get current window
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        
        // Make window movable by user during this operation
        window.isMovableByWindowBackground = true
        
        // Get current position
        var currentPosition = window.frame.origin
        
        // Move based on direction
        switch direction {
        case .up:
            currentPosition.y += distance
        case .down:
            currentPosition.y -= distance
        case .left:
            currentPosition.x -= distance
        case .right:
            currentPosition.x += distance
        }
        
        // Set new position without animation
        window.setFrameOrigin(currentPosition)
    }
    
    /// Toggles window opacity between full and semi-transparent
    func toggleOpacity() {
        // Toggle between full opacity and semi-transparent
        appState.windowOpacity = appState.windowOpacity > 0.9 ? 
            Constants.UI.Opacity.semitransparent : 
            Constants.UI.Opacity.full
        
        // Get current window
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        
        // Set window alpha
        window.alphaValue = appState.windowOpacity
    }
    
    /// Resets window position to default location
    func resetWindowPosition() {
        // Get current window
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        // Reset to initial position
        let xPos = screenFrame.midX - (Constants.UI.windowWidth / 2)
        // Use the same offset value (120px) as defined in window creation
        let yPos = screen.frame.maxY - Constants.UI.toolbarHeight - 120
        
        // If the window size was changed, also reset the height and ensure correct width
        if windowFrame.height != Constants.UI.toolbarHeight || windowFrame.width != Constants.UI.windowWidth {
            let newFrame = NSRect(
                x: xPos,
                y: yPos,
                width: Constants.UI.windowWidth,
                height: Constants.UI.toolbarHeight
            )
            
            // First update the app state with animation
            // The state change will trigger the UI transitions with proper animations
            withAnimation(Constants.Animation.simpleCurve) {
                // Update app state to ensure UI is consistent
                appState.isChatActive = false
                appState.showResults = false
                appState.clearCapturedImages()
            }
            
            // Disable mouse events as we're going back to initial state
            window.ignoresMouseEvents = !appState.isChatActive
            
            // Then animate the window resize
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.Animation.standard
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            // Just move the window without resizing
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
    }
    
    // MARK: - App Management Methods
    
    /// Hides the application
    /// - Note: Actual implementation handled in HotKeyManager.toggleAppVisibility()
    func hideApp() {
        NSApp.hide(nil)
    }
    
    /// Quits the application
    func quitApp() {
        NSApp.terminate(nil)
    }
    
    /// Shows keyboard shortcuts help dialog
    func showKeyboardShortcutsHelp() {
        shortcutsHelpController.toggleShortcutsHelp()
    }
    
    /// Deletes the most recently captured screenshot
    func deleteLatestScreenshot() {
        appState.deleteLatestScreenshot()
    }
    
    /// Deletes the selected screenshot
    func deleteSelectedScreenshot() {
        appState.deleteSelectedScreenshot()
        }
    
    /// Navigates to the next screenshot
    func navigateToNextScreenshot() {
        appState.selectNextScreenshot()
    }
    
    /// Navigates to the previous screenshot
    func navigateToPreviousScreenshot() {
        appState.selectPreviousScreenshot()
    }
    
    /// Selects an image by its ID
    /// - Parameter imageId: The UUID of the image to select
    func selectImage(withId imageId: UUID) {
        if let index = appState.capturedImages.firstIndex(where: { $0.id == imageId }) {
            appState.selectScreenshot(at: index)
        }
    }
        
    // MARK: - Transcription Methods
    
    /// Starts audio recording and transcription
    private func startTranscription() {
        do {
            // Request authorization first
            transcriptionService.requestAuthorization()
            
            // Reset and start transcription
            transcriptionService.resetTranscript()
            try transcriptionService.startRecording()
            
            // Update UI state - only show transcript view if enabled in preferences
            appState.showTranscript = AppPreferences.shared.showTranscriptionViewer
        } catch {
            print("Error starting transcription: \(error.localizedDescription)")
            
            // Show error in the transcript if the viewer is enabled
            appState.transcriptText = "Error: Unable to start recording. \(error.localizedDescription)"
            appState.showTranscript = AppPreferences.shared.showTranscriptionViewer
        }
    }
    
    /// Stops audio recording and transcription
    private func stopTranscription() {
        transcriptionService.stopRecording()
    }
    
    /// Toggles the live mode
    func toggleLive() {
        // Based on the current audio source, toggle appropriate recording
        switch appState.audioSource {
        case .microphone:
            // Toggle microphone recording (existing live mode)
        appState.isLiveMode.toggle()
        
        if appState.isLiveMode {
            // If previous transcription exists, reset it when starting a new session
            if !appState.transcriptText.isEmpty && !appState.isTranscribing {
                appState.transcriptText = ""
            }
            
            // Start recording and transcription
            startTranscription()
        } else {
            // Stop recording and transcription
            stopTranscription()
            }
            
        case .systemAudio:
            // Toggle system audio recording
            SystemAudioRecorder.shared.toggleRecording()
        }
    }
    
    /// Toggles the transcript viewer visibility
    func toggleTranscriptViewer() {
        // Toggle transcript viewer regardless of settings
        appState.showTranscript.toggle()
    }
    
    // MARK: - HotKeyActionHandler Implementation
    
    /// Toggles between microphone and system audio sources
    func toggleAudioSource() {
        // Check if we're currently recording and save current source
        let isRecording = appState.isLiveMode || SystemAudioRecorder.shared.isRecording
        let currentSource = appState.audioSource
        
        // Stop ALL recording with minimal state updates
        if SystemAudioRecorder.shared.isRecording {
            SystemAudioRecorder.shared.stopRecording()
        }
        
        if appState.isLiveMode {
            // Stop without triggering UI updates
            transcriptionService.stopRecording()
            appState.isLiveMode = false
        }
        
        // Switch source without starting recording yet
        appState.audioSource = currentSource == .microphone ? .systemAudio : .microphone
        
        // Start new recording with a delay if needed
        if isRecording {
            // Use a longer delay to prevent rapid state changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.toggleLive()
            }
        }
    }
} 