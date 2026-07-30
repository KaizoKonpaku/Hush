import SwiftUI

protocol NativeIntegrationBridge {
    associatedtype NativeView

    func makeView() -> NativeView
    func updateView(_ view: NativeView)
}

#if canImport(AppKit)
import AppKit

struct AppKitIntegrationBridge: NativeIntegrationBridge {
    func makeView() -> NSView {
        NSView(frame: .zero)
    }

    func updateView(_ view: NSView) {
        // Integration hook for AppKit-backed features.
    }
}
#endif

#if canImport(UIKit)
import UIKit

struct UIKitIntegrationBridge: NativeIntegrationBridge {
    func makeView() -> UIView {
        UIView(frame: .zero)
    }

    func updateView(_ view: UIView) {
        // Integration hook for UIKit-backed features.
    }
}
#endif
