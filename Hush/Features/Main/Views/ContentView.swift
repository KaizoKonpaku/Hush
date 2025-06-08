import SwiftUI
import AppKit

/// Main content view of the application
struct ContentView: View {
    // MARK: - Properties
    
    /// The view model responsible for business logic
    @StateObject private var viewModel: MainViewModel
    
    /// The shared app state
    @ObservedObject private var appState: AppState
    
    // MARK: - Initialization
    
    /// Initializes the content view with optional app state
    /// - Parameter appState: The shared app state (will create new if not provided)
    init(appState: AppState = AppState.shared) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._viewModel = StateObject(wrappedValue: MainViewModel(appState: appState))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Global background - transparent to allow see-through
            Color.clear
            
            VStack(spacing: 0) {
                // Main toolbar with app controls
                toolbar
                    .animation(nil, value: appState.isRecording)
                    .animation(nil, value: appState.isChatActive)
                    .animation(nil, value: appState.isProcessing)
                
                // Divider after toolbar (always present if any content below)
                if appState.isChatActive || appState.showResults || !appState.capturedImages.isEmpty || appState.showTranscript {
                    SectionDivider()
                }
                
                // Transcript View (appears when transcription is active)
                if appState.showTranscript {
                    TranscriptView(
                        transcript: appState.transcriptText,
                        isRecording: appState.isTranscribing,
                        hasScreenshots: !appState.capturedImages.isEmpty
                    )
                    .transition(.opacity)
                    
                    // Divider after transcript (if anything follows)
                    if appState.isChatActive || !appState.capturedImages.isEmpty || appState.showResults {
                        SectionDivider()
                    }
                }
                
                // Chat area (appears when chat is active)
                if appState.isChatActive {
                    chatArea
                        .transition(.opacity)
                
                    // Divider after chat (if anything follows)
                    if !appState.capturedImages.isEmpty || appState.showResults {
                        SectionDivider()
                    }
                }
                
                // Screenshots grid (appears when there are screenshots)
                if !appState.capturedImages.isEmpty {
                    ScreenshotGridView(
                        images: appState.capturedImages,
                        onImageSelected: { imageId in
                            viewModel.selectImage(withId: imageId)
                        }
                    )
                    .transition(.opacity)
                    
                    // Divider after screenshots (if results follow)
                    if appState.showResults {
                    SectionDivider()
                    }
                }
                
                // Results display
                if appState.showResults {
                    EnhancedResultsView(
                        content: appState.resultContent, 
                        structuredContent: viewModel.structuredContent,
                        isAutoScrollEnabled: $appState.isAutoScrollEnabled,
                        toggleAutoScroll: viewModel.toggleAutoScroll,
                        isStreaming: appState.isStreaming
                    )
                    .environment(\.appShowTranscript, appState.showTranscript)
                    .transition(.opacity)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .configureWindow(
            isChatActive: $appState.isChatActive, 
            showResults: $appState.showResults, 
            hasScreenshots: !appState.capturedImages.isEmpty,
            showTranscript: $appState.showTranscript
        )
        .onAppear {
            viewModel.setupHotKeys()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        // Simple smooth animations for content transitions
        .animation(Constants.Animation.simpleCurve, value: appState.isChatActive)
        .animation(Constants.Animation.simpleCurve, value: appState.showResults)
        .animation(Constants.Animation.simpleCurve, value: !appState.capturedImages.isEmpty)
        .animation(Constants.Animation.simpleCurve, value: appState.showTranscript)
    }
    
    // MARK: - Subviews
    
    /// Main toolbar view
    private var toolbar: some View {
        ZStack {
            // Background with glass effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .frame(height: Constants.UI.toolbarHeight)
            
            // Toolbar content with center alignment
            HStack {
                Spacer()
                
                HStack(spacing: 0) {
                    // App title/logo
                    Text("HUSH")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                    
                    ToolbarDivider()
                    
                    // Settings button
                    HStack(spacing: 4) {
                        Text("⌘")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 15, height: 15)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(3)
                        
                        Text(",")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 15, height: 15)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(3)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.openSettings()
                    }
                    
                    ToolbarDivider()
                    
                    // New session button
                    ToolbarButton(title: "NEW", shortcutKey: "N") {
                        viewModel.newSession()
                    }
                    
                    ToolbarDivider()
                    
                    // Audio recording button with source selection
                    AudioSourceButton(appState: appState) {
                        viewModel.toggleLive()
                    }
                    
                    ToolbarDivider()
                    
                    // Text mode button
                    ToolbarButton(title: "TEXT", shortcutKey: "T") {
                        viewModel.toggleChat()
                    }
                    
                    ToolbarDivider()
                    
                    // Capture/Stop button (state dependent)
                    if !appState.isRecording {
                        // Ready state without indicator
                        ToolbarButton(title: "SCREENSHOT", shortcutKey: "C") {
                            viewModel.captureScreenshot()
                        }
                    } else {
                        // Recording state without indicator
                        ToolbarButton(title: "STOP", shortcutKey: "C", systemImage: "stop.circle") {
                                viewModel.toggleRecording()
                            }
                        }
                    
                    // Add delete button when there are screenshots
                    if !appState.capturedImages.isEmpty {
                        ToolbarDivider()
                        
                        // Replace Button with ToolbarButton for consistency
                        ToolbarButton(title: "DELETE", shortcutKey: "D") {
                            viewModel.deleteLatestScreenshot()
                        }
                    }
                    
                    // Add process button at the end
                    if !appState.capturedImages.isEmpty || appState.isRecording || appState.isChatActive || 
                       !appState.transcriptText.isEmpty {
                        ToolbarDivider()
                        
                        // Process button for screenshots
                        if !appState.capturedImages.isEmpty {
                            ProcessButton(
                                isProcessing: appState.isProcessing,
                                canProcess: true
                            ) {
                                viewModel.processScreenshots()
                            }
                        }
                        // Process button for recording, chat, or transcription
                        else if appState.isRecording || appState.isChatActive || !appState.transcriptText.isEmpty {
                            // Process button with state awareness
                        ProcessButton(
                            isProcessing: appState.isProcessing,
                            canProcess: viewModel.canProcess()
                        ) {
                            viewModel.processRecording()
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .frame(height: Constants.UI.toolbarHeight)
        }
    }
    
    /// Chat input area
    private var chatArea: some View {
        ZStack {
            // Glass background effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            BorderlessTextField(
                text: $appState.chatText, 
                placeholder: appState.capturedImages.isEmpty 
                    ? "Type your message..." 
                    : "Type prompt for screenshot analysis...",
                onSubmit: viewModel.sendMessage
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: Constants.UI.chatInputHeight)
    }
}

// MARK: - Window Configuration

extension View {
    /// Configures the window based on the current state
    /// - Parameters:
    ///   - isChatActive: Whether chat is active
    ///   - showResults: Whether results are shown
    ///   - hasScreenshots: Whether screenshots are being displayed
    ///   - showTranscript: Whether the transcript is being shown
    /// - Returns: Modified view
    func configureWindow(
        isChatActive: Binding<Bool>,
        showResults: Binding<Bool>,
        hasScreenshots: Bool = false,
        showTranscript: Binding<Bool>
    ) -> some View {
        self.onChange(of: isChatActive.wrappedValue) {
            configureWindowSize(isChatActive: isChatActive.wrappedValue, showResults: showResults.wrappedValue, hasScreenshots: hasScreenshots, showTranscript: showTranscript.wrappedValue)
        }
        .onChange(of: showResults.wrappedValue) {
            configureWindowSize(isChatActive: isChatActive.wrappedValue, showResults: showResults.wrappedValue, hasScreenshots: hasScreenshots, showTranscript: showTranscript.wrappedValue)
        }
        .onChange(of: showTranscript.wrappedValue) {
            configureWindowSize(isChatActive: isChatActive.wrappedValue, showResults: showResults.wrappedValue, hasScreenshots: hasScreenshots, showTranscript: showTranscript.wrappedValue)
        }
        .onAppear {
            configureWindowSize(isChatActive: isChatActive.wrappedValue, showResults: showResults.wrappedValue, hasScreenshots: hasScreenshots, showTranscript: showTranscript.wrappedValue)
        }
    }
    
    /// Helper to calculate and set the window size
    /// - Parameters:
    ///   - isChatActive: Whether chat is active
    ///   - showResults: Whether results are shown
    ///   - hasScreenshots: Whether screenshots are being displayed
    ///   - showTranscript: Whether the transcript is being shown
    private func configureWindowSize(isChatActive: Bool, showResults: Bool, hasScreenshots: Bool, showTranscript: Bool) {
        // Get the main window
        guard let window = NSApp.windows.first else { return }
        
        // Calculate total height based on visible components
        var totalHeight = Constants.UI.toolbarHeight
        
        // Count how many visible components we have for divider calculation
        var visibleComponents = 0
        
        if isChatActive {
            totalHeight += Constants.UI.chatInputHeight
            visibleComponents += 1
        }
        
        if hasScreenshots {
            // Fixed height for horizontal screenshot row
            totalHeight += Constants.UI.screenshotViewHeight // Image height + vertical padding
            visibleComponents += 1
        }
        
        if showTranscript {
            totalHeight += Constants.UI.transcriptViewHeight
            visibleComponents += 1
        }
        
        if showResults {
            // Adjust results view height if transcript is visible to maintain proper scroll area
            var resultsHeight = Constants.UI.resultsViewHeight
            
            // If transcript is visible, adjust results height to maintain proper scroll area
            // but make sure window doesn't get too tall
            if showTranscript {
                let maxScreenHeight = NSScreen.main?.frame.height ?? 1000
                let maxResultsHeight = maxScreenHeight * 0.6 // Limit to 60% of screen height
                
                // Calculate how much space is left after accounting for other components
                let _ = Constants.UI.toolbarHeight + 
                      (isChatActive ? Constants.UI.chatInputHeight : 0) +
                      (hasScreenshots ? Constants.UI.screenshotViewHeight : 0) +
                      Constants.UI.transcriptViewHeight +
                      (CGFloat(visibleComponents) * Constants.UI.dividerHeight)
                
                // Use at least the default height, but don't exceed max height
                resultsHeight = min(maxResultsHeight, Constants.UI.resultsViewHeight)
            }
            
            totalHeight += resultsHeight
            visibleComponents += 1
        }
        
        // Add divider heights - we need (visibleComponents - 1) dividers between components,
        // plus 1 divider after the toolbar if any components are visible
        let dividerCount = visibleComponents > 0 ? visibleComponents : 0
        totalHeight += CGFloat(dividerCount) * Constants.UI.dividerHeight
        
        // Get the current window frame
        let currentFrame = window.frame
        
        // Calculate the y-coordinate to maintain top position of window
        // This is the most critical part to ensure window grows/shrinks from bottom
        let topEdgeY = currentFrame.maxY
        let newY = topEdgeY - totalHeight
        
        // Create the new frame maintaining the same top position
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newY,
            width: Constants.UI.windowWidth,
            height: totalHeight
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.Animation.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(newFrame, display: true)
        }
        
        // Set mouse event handling based on chat state
        window.ignoresMouseEvents = !isChatActive
    }
}

// MARK: - Preview Provider

#Preview {
    ContentView()
} 
