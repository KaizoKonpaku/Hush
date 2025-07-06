import SwiftUI
import AppKit

/// Visual Effect View for glass effect background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 0 // Ensure no rounded corners
        
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Results display area for processed content
struct ResultsView: View {
    // MARK: - Properties
    let content: String
    @Binding var isAutoScrollEnabled: Bool
    let toggleAutoScroll: () -> Void
    var isStreaming: Bool = false
    
    // Optional structured content
    var structuredContent: StreamContent? = nil
    
    // Environment values to check other UI states
    @Environment(\.appShowTranscript) private var showTranscript
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Glass background for results
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            // Content area
            ScrollViewReader { proxy in
                ScrollView {
                    if let structured = structuredContent {
                        // Use the structured content view when available
                        StreamContentView(content: structured)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("structuredResults")
                    } else {
                        // Fall back to plain text for backward compatibility
                        Text(LocalizedStringKey(content))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, Constants.UI.dividerHeight / 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("resultsText")
                    }
                }
                .accessibilityIdentifier("resultsScrollView")
                .onChange(of: structuredContent?.items.count) { oldCount, newCount in
                    if isAutoScrollEnabled {
                        withAnimation {
                            proxy.scrollTo(structuredContent?.items.last?.id ?? "resultsText", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Indicators (positioned in bottom right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    // Streaming indicator (shows only when streaming)
                    if isStreaming {
                        StreamingIndicator()
                            .padding(.trailing, 8)
                    }
                    
                    // Auto-scroll indicator
                    ResultsScrollIndicator(isEnabled: isAutoScrollEnabled, action: toggleAutoScroll)
                }
                .padding([.trailing, .bottom], Constants.UI.dividerHeight / 2)
            }
        }
        // Use flexible height when transcript is visible to allow proper scrolling
        .frame(maxHeight: .infinity)
    }
}

/// Enhanced Results View that supports structured content
struct EnhancedResultsView: View {
    // MARK: - Properties
    let content: String
    let structuredContent: StreamContent
    @Binding var isAutoScrollEnabled: Bool
    let toggleAutoScroll: () -> Void
    var isStreaming: Bool = false
    
    // MARK: - Body
    var body: some View {
        ResultsView(
            content: content,
            isAutoScrollEnabled: $isAutoScrollEnabled,
            toggleAutoScroll: toggleAutoScroll,
            isStreaming: isStreaming,
            structuredContent: structuredContent
        )
    }
}

/// Auto-scroll indicator button for results view
struct ResultsScrollIndicator: View {
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 10))
                
                Text(isEnabled ? "AUTO" : "MANUAL")
                    .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(4)
            .foregroundColor(isEnabled ? .blue : .gray)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Streaming indicator that shows while content is streaming
struct StreamingIndicator: View {
    // Animation state
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Animated dots
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 4, height: 4)
                        .opacity(isAnimating ? 1.0 : 0.3)
                        .animation(
                            Animation.easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(0.2 * Double(i)),
                            value: isAnimating
                        )
                }
            }
            
            Text("STREAMING")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(4)
        .onAppear {
            // Slight delay before starting animation to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
            }
        }
    }
}

/// Compact processing indicator for button
struct ProcessingIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle())
            
            Text("PROCESSING")
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

/// Processing button that displays the loading state
struct ProcessButton: View {
    let isProcessing: Bool
    let canProcess: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isProcessing {
                    // Show processing indicator
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 16, height: 16)
                    
                    Text("PROCESSING")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                } else {
                    // Normal state (icon removed)
                    Text("PROCESS")
                        .fontWeight(.medium)
                        .foregroundColor(canProcess ? .primary : .gray.opacity(0.5))
                    
                    // Return key symbol
                    ShortcutKey(key: "↩")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canProcess || isProcessing)
        .animation(nil, value: isProcessing) // Explicitly disable animation
        .animation(nil, value: canProcess)   // Explicitly disable animation
    }
}

// MARK: - Environment Values

// Environment key for transcript visibility state
struct AppShowTranscriptKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appShowTranscript: Bool {
        get { self[AppShowTranscriptKey.self] }
        set { self[AppShowTranscriptKey.self] = newValue }
    }
} 
