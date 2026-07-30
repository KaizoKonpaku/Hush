import AppKit
import SwiftUI

struct MainWindowTrackpadNavigationMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPrevious: onPrevious, onNext: onNext)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(isEnabled: isEnabled, onPrevious: onPrevious, onNext: onNext)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(isEnabled: isEnabled, onPrevious: onPrevious, onNext: onNext)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var hostView: NSView?
        private var monitor: Any?
        private var isEnabled = false
        private var accumulatedHorizontalDelta: CGFloat = 0
        private var onPrevious: () -> Void
        private var onNext: () -> Void

        init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
            self.onPrevious = onPrevious
            self.onNext = onNext
        }

        func attach(to view: NSView) {
            hostView = view
            installMonitorIfNeeded()
        }

        func update(
            isEnabled: Bool,
            onPrevious: @escaping () -> Void,
            onNext: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.onPrevious = onPrevious
            self.onNext = onNext

            if !isEnabled {
                accumulatedHorizontalDelta = 0
            }

            installMonitorIfNeeded()
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            monitor = nil
            hostView = nil
            accumulatedHorizontalDelta = 0
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  event.hasPreciseScrollingDeltas,
                  let hostView,
                  hostView.window?.isKeyWindow == true else {
                accumulatedHorizontalDelta = 0
                return event
            }

            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY

            guard abs(horizontal) > abs(vertical), abs(horizontal) > 0 else {
                if event.phase == .ended || event.momentumPhase == .ended {
                    accumulatedHorizontalDelta = 0
                }
                return event
            }

            accumulatedHorizontalDelta += horizontal

            if accumulatedHorizontalDelta >= 45 {
                accumulatedHorizontalDelta = 0
                onPrevious()
                return nil
            }

            if accumulatedHorizontalDelta <= -45 {
                accumulatedHorizontalDelta = 0
                onNext()
                return nil
            }

            if event.phase == .ended || event.momentumPhase == .ended {
                accumulatedHorizontalDelta = 0
            }

            return event
        }
    }
}
