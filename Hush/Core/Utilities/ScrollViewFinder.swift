import AppKit
import SwiftUI

/// Utility for finding and manipulating NSScrollView instances in the view hierarchy
struct ScrollViewFinder {
    /// Finds the first NSScrollView in the view hierarchy
    /// - Parameter view: The parent view to search within
    /// - Returns: The first NSScrollView found, or nil if none exists
    static func findScrollView(in view: NSView?) -> NSScrollView? {
        // Base case: view is nil
        guard let view = view else { return nil }
        
        // Check if this view is a scroll view
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        
        // Recursive case: check subviews
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        
        return nil
    }
    
    /// Finds a ScrollView with a specific accessibility identifier
    /// - Parameters:
    ///   - view: The parent view to search within
    ///   - identifier: The accessibility identifier to match
    /// - Returns: The matching NSScrollView, or nil if none exists
    static func findScrollView(in view: NSView?, withIdentifier identifier: String) -> NSScrollView? {
        // Base case: view is nil
        guard let view = view else { return nil }
        
        // Check if this view is a scroll view with matching identifier
        if let scrollView = view as? NSScrollView {
            // Check the scroll view's identifier
            if view.accessibilityIdentifier() == identifier {
                return scrollView
            }
            
            // In SwiftUI, the identifier might be on a parent or child view
            // Check parent view's identifier if available
            if let parentView = view.superview, 
               parentView.accessibilityIdentifier() == identifier {
                return scrollView
            }
            
            // Check if any of the scroll view's document view or contentView has the identifier
            if scrollView.documentView?.accessibilityIdentifier() == identifier ||
               scrollView.contentView.accessibilityIdentifier() == identifier {
                return scrollView
            }
        }
        
        // Recursive case: check subviews
        for subview in view.subviews {
            if let found = findScrollView(in: subview, withIdentifier: identifier) {
                return found
            }
        }
        
        return nil
    }
    
    /// Finds all ScrollViews in the view hierarchy
    /// - Parameter view: The parent view to search within
    /// - Returns: Array of all NSScrollViews found
    static func findAllScrollViews(in view: NSView?) -> [NSScrollView] {
        var scrollViews: [NSScrollView] = []
        findAllScrollViews(in: view, result: &scrollViews)
        return scrollViews
    }
    
    /// Helper method to recursively find all scroll views
    /// - Parameters:
    ///   - view: The parent view to search within
    ///   - result: Array to collect found scroll views
    private static func findAllScrollViews(in view: NSView?, result: inout [NSScrollView]) {
        // Base case: view is nil
        guard let view = view else { return }
        
        // Check if this view is a scroll view
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        
        // Recursive case: check subviews
        for subview in view.subviews {
            findAllScrollViews(in: subview, result: &result)
        }
    }
}
