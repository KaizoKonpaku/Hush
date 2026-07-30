import SwiftUI

extension MainWindowView {
    var intelligenceSettings: some View {
        IntelligenceSettingsPage(
            providerStore: providerStore,
            intelDefaultModel: $intelDefaultModel,
            intelFastModel: $intelFastModel,
            intelAdvancedModel: $intelAdvancedModel,
            intelRealtimeModel: $intelRealtimeModel
        )
    }
}

private struct IntelligenceSettingsPage: View {
    @ObservedObject var providerStore: ProviderAccountStore
    @ObservedObject private var promptPresetStore = AssistantPromptPresetStore.shared
    @Binding var intelDefaultModel: String
    @Binding var intelFastModel: String
    @Binding var intelAdvancedModel: String
    @Binding var intelRealtimeModel: String
    @State private var promptPresetEditorDraft: AssistantPromptPresetEditorDraft?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live runtime")
                    Text("When OpenAI is connected and selected, HUSH routes requests through the Responses API. If no live provider is configured, requests stay unavailable until you connect one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Runtime")
            } footer: {
                Text("HUSH no longer uses a built-in mock assistant. Connect a live provider before sending requests.")
            }

            Section {
                explainedPicker(
                    "Live model",
                    description: "Used for OpenAI Realtime conversations with microphone and system audio.",
                    selection: $intelRealtimeModel
                ) {
                    modelPickerOptions(
                        for: intelRealtimeModel,
                        availableModels: providerStore.availableRealtimeModels,
                        emptyLabel: "No live models"
                    )
                }
                .disabled(providerStore.availableRealtimeModels.isEmpty)
            } header: {
                Text("Live")
            } footer: {
                Text("Live uses a dedicated OpenAI Realtime conversation model. Typed and capture requests keep using your selected text model profiles.")
            }

            Section {
                explainedPicker(
                    "Default profile",
                    description: "Used for standard requests.",
                    selection: $intelDefaultModel
                ) {
                    modelPickerOptions(
                        for: intelDefaultModel,
                        availableModels: providerStore.availableModels,
                        emptyLabel: "No connected models"
                    )
                }
                .disabled(providerStore.availableModels.isEmpty)

                explainedPicker(
                    "Fast profile",
                    description: "Used when speed is preferred.",
                    selection: $intelFastModel
                ) {
                    modelPickerOptions(
                        for: intelFastModel,
                        availableModels: providerStore.availableModels,
                        emptyLabel: "No connected models"
                    )
                }
                .disabled(providerStore.availableModels.isEmpty)

                explainedPicker(
                    "Advanced profile",
                    description: "Used for deeper reasoning tasks.",
                    selection: $intelAdvancedModel
                ) {
                    modelPickerOptions(
                        for: intelAdvancedModel,
                        availableModels: providerStore.availableModels,
                        emptyLabel: "No connected models"
                    )
                }
                .disabled(providerStore.availableModels.isEmpty)
            } header: {
                Text("Profiles")
            } footer: {
                Text("Validated provider accounts unlock the available assistant profiles here.")
            }

            Section {
                explainedPicker(
                    "Default prompt",
                    description: "Pick the instructions HUSH sends before each request.",
                    selection: defaultPromptBinding
                ) {
                    Text(AssistantPromptPresetCatalog.builtInPresetName).tag("")

                    ForEach(promptPresetStore.presets) { preset in
                        Text(preset.trimmedName).tag(preset.id.uuidString)
                    }
                }

                Button("New Prompt…") {
                    promptPresetEditorDraft = AssistantPromptPresetEditorDraft()
                }

                if promptPresetStore.presets.isEmpty {
                    Text("Create prompt presets for recurring working styles, tone, or output structure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(promptPresetStore.presets) { preset in
                        promptPresetRow(for: preset)
                    }
                }
            } header: {
                Text("Prompt Defaults")
            } footer: {
                Text("The selected default prompt becomes the base instructions used by both the overlay and the full Assistant.")
            }
        }
        .settingsPageLayout()
        .sheet(item: $promptPresetEditorDraft) { draft in
            AssistantPromptPresetEditorSheet(draft: draft) { name, instructions in
                promptPresetStore.savePreset(id: draft.presetID, name: name, instructions: instructions)
            }
        }
        .onAppear {
            IntelligencePreferencesMigration.migrateIfNeeded()
        }
    }

    @ViewBuilder
    private func modelPickerOptions(
        for selection: String,
        availableModels: [AssistantModelOption],
        emptyLabel: String
    ) -> some View {
        let savedOption = AssistantModelCatalog.option(for: selection, availableOptions: availableModels)
        let isSavedOptionUnavailable = savedOption != nil
            && !AssistantModelCatalog.hasAvailableOption(for: selection, availableOptions: availableModels)

        if let savedOption, isSavedOptionUnavailable {
            Text("\(savedOption.title) (Saved)")
                .tag(selection)
        }

        if availableModels.isEmpty {
            Text(emptyLabel)
                .tag("")
        } else {
            ForEach(availableModels) { option in
                Text(option.title)
                    .tag(option.storageValue)
            }
        }
    }

    private var defaultPromptBinding: Binding<String> {
        Binding(
            get: { promptPresetStore.selectedPreset?.id.uuidString ?? "" },
            set: { newValue in
                let presetID = UUID(uuidString: newValue)
                promptPresetStore.selectPreset(id: presetID)
            }
        )
    }

    private func promptPresetRow(for preset: AssistantPromptPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(preset.trimmedName)
                    .font(.body.weight(.medium))

                if promptPresetStore.selectedPreset?.id == preset.id {
                    Text("Default")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Edit") {
                    promptPresetEditorDraft = AssistantPromptPresetEditorDraft(preset: preset)
                }
                .buttonStyle(.borderless)

                Button("Delete", role: .destructive) {
                    promptPresetStore.deletePreset(id: preset.id)
                }
                .buttonStyle(.borderless)
            }

            Text(preset.previewText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if promptPresetStore.selectedPreset?.id != preset.id {
                Button("Use as Default") {
                    promptPresetStore.selectPreset(id: preset.id)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension IntelligenceSettingsPage {
    func explainedPicker<SelectionValue: Hashable, Content: View>(
        _ title: String,
        description: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsPicker(title, description: description, selection: selection, content: content)
    }
}
