import Foundation
import SwiftUI
import Combine

/// Simple processor for stream content
class StreamContentBuilder {
    // MARK: - Properties
    
    /// Raw text buffer containing the current streaming content
    private var buffer: String
    
    // MARK: - Initialization
    
    /// Create a new builder with the provided buffer
    init(buffer: String = "") {
        self.buffer = buffer
    }
    
    // MARK: - Public Methods
    
    /// Process raw input into structured content
    func build() -> StreamContent {
        print("🔄 Processing \(buffer.count) characters of content")
        
        // Create a hierarchical ID generator
        var ids: any IdentifierGenerator = IncrementalIdentifierGenerator.create()
        
        // Simple processing - just create a single text item
        var content = StreamContent()
        
        if !buffer.isEmpty {
            content.items.append(.init(ids: &ids, value: .markdown(MarkdownEntry(content: buffer))))
        }
        
        return content
    }
} 
