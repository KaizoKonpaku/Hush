import SwiftUI

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: $isOn)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let description: String
    @Binding var selection: SelectionValue
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(title, selection: $selection) {
                content
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

extension View {
    func settingsPageLayout() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .settingsScrollEdgeEffect()
    }

    func settingsToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        SettingsToggleRow(title: title, description: description, isOn: isOn)
    }

    func settingsPicker<SelectionValue: Hashable, Content: View>(
        _ title: String,
        description: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsPickerRow(
            title: title,
            description: description,
            selection: selection,
            content: content()
        )
    }

    @ViewBuilder
    private func settingsScrollEdgeEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

extension MainWindowView {
    var stealthHideFromOverviewSurfacesBinding: Binding<Bool> {
        Binding(
            get: { stealthHideFromMissionControl || stealthHideFromStageManager },
            set: { value in
                stealthHideFromMissionControl = value
                stealthHideFromStageManager = value
            }
        )
    }

    func stealthToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        explainedToggle(title, description: description, isOn: isOn)
    }

    func explainedToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        settingsToggle(title, description: description, isOn: isOn)
    }

    func explainedPicker<SelectionValue: Hashable, Content: View>(
        _ title: String,
        description: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsPicker(title, description: description, selection: selection, content: content)
    }
}
