import SwiftUI

/// Represents a captured screenshot image with a unique identifier
struct CapturedImage: Identifiable, Hashable {
    /// Unique identifier for the image
    let id = UUID()
    
    /// The captured NSImage
    let image: NSImage
    
    /// Date when the image was captured
    let captureDate = Date()
    
    /// Whether this image is currently selected
    var isSelected: Bool = false
    
    /// Compares two CapturedImage instances
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// Equality check based on id
    static func == (lhs: CapturedImage, rhs: CapturedImage) -> Bool {
        lhs.id == rhs.id
    }
} 