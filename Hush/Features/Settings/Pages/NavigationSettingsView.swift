import SwiftUI

extension MainWindowView {
    var navigationSettings: some View {
        Form {
            Section {
                explainedPicker(
                    "Start position",
                    description: "Choose how the floating window starts on screen.",
                    selection: $navPosition
                ) {
                    Text("Remember last position").tag("remember")
                    Text("Top right").tag("topRight")
                    Text("Top left").tag("topLeft")
                    Text("Bottom right").tag("bottomRight")
                    Text("Bottom left").tag("bottomLeft")
                    Text("Top middle").tag("topMiddle")
                    Text("Bottom middle").tag("bottomMiddle")
                    Text("Center").tag("center")
                }
                explainedPicker(
                    "Screen",
                    description: "Choose which display gets the floating window.",
                    selection: $navMultiMonitor
                ) {
                    Text("Active screen").tag("active")
                    Text("Primary screen").tag("primary")
                }
                explainedToggle(
                    "Snap to screen edges",
                    description: "Snaps the floating window to nearby edges.",
                    isOn: $navSnapToEdges
                )
            } header: {
                Text("Placement")
            } footer: {
                Text("Keep placement controls here and avoid repeating stealth-specific visibility options.")
            }
            Section {
                explainedPicker(
                    "Auto-hide",
                    description: "Hide the overlay after it has been inactive for a while.",
                    selection: $navAutoHide
                ) {
                    Text("Never").tag("never")
                    Text("10 seconds").tag("10s")
                    Text("30 seconds").tag("30s")
                    Text("1 minute").tag("60s")
                }
                explainedToggle(
                    "Focus input on open",
                    description: "Places the cursor in the text field when the window opens.",
                    isOn: $navFocusInputOnOpen
                )
            } header: {
                Text("Interaction")
            }
            Section {
                explainedToggle(
                    "Trackpad Gestures",
                    description: "Uses trackpad gestures for moving through the window.",
                    isOn: $navTrackpadGestures
                )
                explainedToggle(
                    "Keyboard Navigation",
                    description: "Lets you move through the window without the mouse.",
                    isOn: $navKeyboardNavigation
                )
            } header: {
                Text("Advanced")
            }
        }
        .settingsPageLayout()
    }
}
