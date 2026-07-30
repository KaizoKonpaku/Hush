import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SubmitShortcutMonitor: NSViewRepresentable {
    let isFocused: Bool
    let requiresCommandReturn: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(
            isFocused: isFocused,
            requiresCommandReturn: requiresCommandReturn,
            onSubmit: onSubmit
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(
            isFocused: isFocused,
            requiresCommandReturn: requiresCommandReturn,
            onSubmit: onSubmit
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var hostView: NSView?
        private var monitor: Any?
        private var isFocused = false
        private var requiresCommandReturn = false
        private var onSubmit: () -> Void

        init(onSubmit: @escaping () -> Void) {
            self.onSubmit = onSubmit
        }

        func attach(to view: NSView) {
            hostView = view
            installMonitorIfNeeded()
        }

        func update(
            isFocused: Bool,
            requiresCommandReturn: Bool,
            onSubmit: @escaping () -> Void
        ) {
            self.isFocused = isFocused
            self.requiresCommandReturn = requiresCommandReturn
            self.onSubmit = onSubmit
            installMonitorIfNeeded()
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            hostView = nil
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isFocused,
                  event.keyCode == UInt16(kVK_Return),
                  let hostView,
                  let window = hostView.window,
                  window.firstResponder is NSTextView else {
                return event
            }

            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let shouldSubmit: Bool

            if requiresCommandReturn {
                shouldSubmit = modifiers == [.command]
            } else {
                shouldSubmit = modifiers.isEmpty
            }

            guard shouldSubmit else { return event }

            onSubmit()
            return nil
        }
    }
}
