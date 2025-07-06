import SwiftUI
import MarkdownUI
import Highlightr

/// Custom syntax highlighter using Highlightr
struct HighlightrCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let highlightr: Highlightr
    private let theme: String
    
    init(theme: String = "xcode") {
        self.highlightr = Highlightr()!
        self.theme = theme
        self.highlightr.setTheme(to: theme)
    }
    
    func highlightCode(_ content: String, language: String?) -> Text {
        guard let language = language,
              let highlightedCode = highlightr.highlight(content, as: language.lowercased()) else {
            return Text(content)
        }
        
        return Text(AttributedString(highlightedCode))
    }
    
    /// Get all supported languages
    static func supportedLanguages() -> [String] {
        let highlightr = Highlightr()!
        return highlightr.supportedLanguages()
    }
    
    /// Get all available themes
    static func availableThemes() -> [String] {
        let highlightr = Highlightr()!
        return highlightr.availableThemes()
    }
}

extension CodeSyntaxHighlighter where Self == HighlightrCodeSyntaxHighlighter {
    static func highlightr(theme: String = "xcode") -> HighlightrCodeSyntaxHighlighter {
        HighlightrCodeSyntaxHighlighter(theme: theme)
    }
}

/// View for displaying formatted content with markdown and code highlighting
struct StreamContentView: View {
    /// The content to render
    let content: StreamContent
    
    /// Current color scheme for theming
    @Environment(\.colorScheme) private var colorScheme
    
    /// App preferences for theme settings
    private let preferences = AppPreferences.shared
    
    /// Highlightr instance for theme colors
    private let highlightr: Highlightr?
    
    init(content: StreamContent) {
        self.content = content
        self.highlightr = Highlightr()
        if let highlightr = self.highlightr {
            highlightr.setTheme(to: AppPreferences.shared.darkTheme)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(content.items) { item in
                if case .markdown(let entry) = item.value {
                    Markdown(entry.content)
                        .markdownBlockStyle(\.codeBlock) { config in
                            codeBlock(config)
                        }
                        .markdownCodeSyntaxHighlighter(HighlightrCodeSyntaxHighlighter(theme: currentTheme))
                        .markdownTextStyle {
                            FontSize(.em(1.0))
                        }
                        .markdownTextStyle(\.code) {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                        .markdownTextStyle(\.strong) {
                            FontWeight(.semibold)
                        }
                        .markdownTextStyle(\.link) {
                            ForegroundColor(.blue)
                        }
                        .id(item.id)
                }
            }
            
            // Display errors if any
            ForEach(content.errors) { error in
                Text(error.error.localizedDescription)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    /// Get the current theme based on color scheme
    private var currentTheme: String {
        colorScheme == .dark ? preferences.darkTheme : preferences.lightTheme
    }
    
    /// Code block styling
    @ViewBuilder
    private func codeBlock(_ configuration: CodeBlockConfiguration) -> some View {
        VStack(spacing: 0) {
            // Language indicator
            Text(configuration.language?.uppercased() ?? "PLAIN TEXT")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Code content
            configuration.label
                .relativeLineSpacing(.em(0.25))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }
} 
