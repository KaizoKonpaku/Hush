import Foundation
import SwiftUI

/// Simplified content model for text-only display
struct StreamContent {
    /// List of renderable items with stable IDs
    var items: [Item] = []
    
    /// Whether the stream has completed
    var finished: Bool = false
    
    /// Errors collected during processing
    var errors: [IdentifiableError] = []
    
    /// A renderable item with stable identity
    struct Item: Identifiable {
        /// Stable identifier across rebuilds
        let id: ID
        
        /// The actual content value
        let value: StreamItemValue
        
        /// Creates a new item with an automatically generated ID
        init(ids: inout IdentifierGenerator, value: StreamItemValue) {
            self.id = ids()
            self.value = value
        }
    }
    
    /// The type of content an item can represent (simplified to markdown only)
    enum StreamItemValue {
        /// Text content
        case markdown(MarkdownEntry)
    }
}

/// An error with an identity for stable rendering
struct IdentifiableError: Identifiable {
    /// Stable identifier
    let id: UUID
    
    /// The underlying error
    let error: Error
    
    /// Creates a new identifiable error
    init(_ error: Error) {
        self.id = UUID()
        self.error = error
    }
}

/// A string-based ID
typealias ID = String

/// Protocol for generating stable, predictable identifiers
protocol IdentifierGenerator {
    /// Generate the next identifier
    mutating func callAsFunction() -> ID
    
    /// Create a new nested identifier generator
    mutating func nested() -> IdentifierGenerator
}

/// An implementation of IdentifierGenerator that generates incremental hierarchical identifiers
struct IncrementalIdentifierGenerator: IdentifierGenerator {
    /// The prefix for all identifiers from this generator
    private var prefix: String
    
    /// The current ID counter
    private var id: Int = 0
    
    /// The current nested ID counter
    private var nestedId: Int = 0
    
    /// Create a new root identifier generator
    static func create() -> IncrementalIdentifierGenerator {
        return Self(prefix: "")
    }
    
    /// Initialize with a prefix
    private init(prefix: String) {
        self.prefix = prefix
    }
    
    /// Generates the next identifier in the sequence
    /// - Returns: A unique identifier string
    mutating func callAsFunction() -> ID {
        nestedId = 0
        id += 1
        return "\(prefix)\(id)"
    }
    
    /// Creates a new nested identifier generator
    /// - Returns: A new generator instance for creating hierarchical identifiers
    mutating func nested() -> IdentifierGenerator {
        nestedId += 1
        return Self(prefix: "\(prefix).\(id)-\(nestedId).")
    }
}

/// Entry for plain text content
struct MarkdownEntry {
    /// The full content
    let content: String
    
    /// A collapsed (shortened) version if available
    var collapsed: String?
    
    /// Whether this entry can be collapsed
    var collapsible: Bool { collapsed != nil }
} 