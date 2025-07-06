import Foundation
import SwiftUI

/// Central location for application constants
enum Constants {
    /// UI-related constants for dimensions, sizes, and visual properties
    enum UI {
        /// Default toolbar height
        static let toolbarHeight: CGFloat = 36
        
        /// Chat input area height
        static let chatInputHeight: CGFloat = 40
        
        /// Results view height
        static let resultsViewHeight: CGFloat = 300
        
        /// Transcript view height
        static let transcriptViewHeight: CGFloat = 60
        
        /// Screenshot grid view height
        static let screenshotViewHeight: CGFloat = 80
        
        /// Default window width
        static let windowWidth: CGFloat = 800
        
        /// Height for section dividers (the see-through gaps)
        static let dividerHeight: CGFloat = 2
        
        /// Window opacity configuration values
        enum Opacity {
            /// Full opacity value (completely opaque)
            static let full: Double = 1.0
            
            /// Semi-transparent opacity value
            static let semitransparent: Double = 0.7
            
            /// Range for opacity slider in settings
            static let range: ClosedRange<Double> = 0.5...1.0
        }
        
        /// Auto-scroll feature configuration values
        enum AutoScroll {
            /// Minimum auto-scroll speed in pixels per tick
            static let minSpeed: Double = 0.2
            
            /// Maximum auto-scroll speed in pixels per tick
            static let maxSpeed: Double = 5.0
            
            /// Default auto-scroll speed in pixels per tick
            static let defaultSpeed: Double = 1.0
            
            /// Speed increment value for increasing scroll speed
            static let speedIncrement: Double = 0.5
            
            /// Speed decrement value for decreasing scroll speed
            static let speedDecrement: Double = 0.25
            
            /// Auto-scroll timer interval in seconds
            static let timerInterval: TimeInterval = 0.05
        }
        
        /// Window and content movement constants
        enum Movement {
            /// Standard window movement distance in points
            static let standardDistance: CGFloat = 27
            
            /// Standard scroll amount in points
            static let scrollAmount: CGFloat = 50
        }
    }
    
    /// Keys for application settings
    enum SettingKeys {
        /// Keys for keyboard shortcut settings
        enum Shortcuts {
            /// Settings shortcut key
            static let settings = "settings"
            
            /// New session shortcut key
            static let newSession = "newSession"
            
            /// Text mode shortcut key
            static let textMode = "textMode"
            
            /// Capture shortcut key
            static let capture = "capture"
            
            /// Delete shortcut key
            static let delete = "delete"
            
            /// Process shortcut key
            static let process = "process"
            
            /// Live mode shortcut key
            static let liveMode = "liveMode"
            
            /// Show transcript viewer shortcut key
            static let showTranscriptViewer = "showTranscriptViewer"
            
            /// Auto-scroll toggle shortcut key
            static let autoScroll = "autoScroll"
            
            /// Scroll up shortcut key
            static let scrollUp = "scrollUp"
            
            /// Scroll down shortcut key
            static let scrollDown = "scrollDown"
            
            /// Scroll speed up shortcut key
            static let scrollSpeedUp = "scrollSpeedUp"
            
            /// Scroll speed down shortcut key
            static let scrollSpeedDown = "scrollSpeedDown"
            
            /// Move window shortcut key
            static let moveWindow = "moveWindow"
            
            /// Copy results shortcut key
            static let copyResults = "copyResults"
            
            /// Toggle opacity shortcut key
            static let toggleOpacity = "toggleOpacity"
            
            /// Reset position shortcut key
            static let resetPosition = "resetPosition"
            
            /// Hide app shortcut key
            static let hideApp = "hideApp"
            
            /// Quit app shortcut key
            static let quitApp = "quitApp"
            
            /// App activation shortcut key
            static let activation = "activation"
            
            /// Toggle audio source shortcut key (between mic and system audio)
            static let toggleAudioSource = "toggleAudioSource"
        }
    }
    
    /// Animation constants for UI transitions
    enum Animation {
        /// Standard animation duration in seconds
        static let standard: TimeInterval = 0.2
        
        /// Simple ease-out animation curve
        static let simpleCurve: SwiftUI.Animation = .easeOut(duration: standard)
    }
}
