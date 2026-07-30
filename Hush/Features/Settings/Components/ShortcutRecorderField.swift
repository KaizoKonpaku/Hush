import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut
    var isConflicted = false

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.onShortcutCaptured = { newShortcut in
            shortcut = newShortcut
        }
        control.shortcut = shortcut
        control.isConflicted = isConflicted
        return control
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.shortcut = shortcut
        nsView.isConflicted = isConflicted
    }
}

final class ShortcutRecorderControl: NSView {
    var onShortcutCaptured: ((GlobalShortcut) -> Void)?
    var shortcut: GlobalShortcut = .fallbackToggleOverlay {
        didSet { updateDisplay() }
    }
    var isConflicted = false {
        didSet { updateVisualState() }
    }

    private let stackView = NSStackView()
    private var isRecording = false {
        didSet {
            if isRecording != oldValue {
                NotificationCenter.default.post(
                    name: isRecording ? .hushShortcutRecorderDidBegin : .hushShortcutRecorderDidEnd,
                    object: nil
                )
            }
            updateVisualState()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let carbonMods = carbonModifiers(from: flags)

        guard carbonMods != 0 else { return }

        let captured = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: UInt(carbonMods))
        onShortcutCaptured?(captured)
        isRecording = false
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        updateDisplay()
        updateVisualState()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 170, height: 28)
    }

    private func updateDisplay() {
        let tokens = isRecording ? ["Press keys..."] : shortcut.displayTokens

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        tokens.forEach { token in
            stackView.addArrangedSubview(
                makeTokenView(text: token, isRecording: isRecording, isConflicted: isConflicted)
            )
        }
    }

    private func updateVisualState() {
        layer?.backgroundColor = NSColor.clear.cgColor
        updateDisplay()
    }

    private func makeTokenView(text: String, isRecording: Bool, isConflicted: Bool) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = {
            if isRecording { return .controlAccentColor }
            if isConflicted { return .systemRed }
            return .labelColor
        }()
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 7
        let backgroundColor: NSColor
        if isRecording {
            backgroundColor = .controlAccentColor.withAlphaComponent(0.12)
        } else if isConflicted {
            backgroundColor = .systemRed.withAlphaComponent(0.12)
            container.layer?.borderWidth = 1
            container.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.22).cgColor
        } else {
            backgroundColor = .controlBackgroundColor
            container.layer?.borderWidth = 0
            container.layer?.borderColor = NSColor.clear.cgColor
        }
        container.layer?.backgroundColor = backgroundColor.cgColor

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
        ])

        return container
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}
