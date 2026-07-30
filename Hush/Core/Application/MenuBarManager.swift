import AppKit

final class MenuBarManager: NSObject {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private var toggleOverlayAction: (@MainActor () -> Void)?

    func start(toggleOverlay: @escaping @MainActor () -> Void) {
        toggleOverlayAction = toggleOverlay
        sync()
    }

    func stop() {
        toggleOverlayAction = nil
        removeStatusItem()
    }

    func sync() {
        let showInMenuBar = defaults.object(forKey: "general.showInMenuBar") as? Bool ?? true
        let stealthEnabled = defaults.bool(forKey: "stealth.enabled")
        let stealthMenuBarVisibility = defaults.string(forKey: "stealth.menuBarVisibility") ?? "default"

        if stealthEnabled && stealthMenuBarVisibility == "hidden" {
            removeStatusItem()
            return
        }

        guard showInMenuBar else {
            removeStatusItem()
            return
        }

        createStatusItemIfNeeded()
        applyButtonStyle(visibility: stealthMenuBarVisibility)
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "HUSH"
        item.button?.target = self
        item.button?.action = #selector(toggleOverlay)
        item.button?.toolTip = "Toggle HUSH Overlay"
        statusItem = item
    }

    private func applyButtonStyle(visibility: String) {
        guard let button = statusItem?.button else { return }

        if visibility == "neutral" {
            button.image = nil
            button.title = "•"
            button.toolTip = "Toggle HUSH Overlay"
            return
        }

        if visibility == "icon" {
            button.image = nil
            button.title = "^-^"
            button.toolTip = "Toggle HUSH Overlay"
            return
        }

        button.image = nil
        button.title = "HUSH"
        button.toolTip = "Toggle HUSH Overlay"
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc
    private func toggleOverlay() {
        Task { @MainActor in
            toggleOverlayAction?()
        }
    }
}
