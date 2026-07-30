import SwiftUI

enum AssistantInspectorSection: String, CaseIterable {
    case queries
    case info

    var title: String {
        switch self {
        case .queries:
            return "Queries"
        case .info:
            return "Info"
        }
    }
}

extension MainWindowView {
    @ViewBuilder
    var mainWindowDetail: some View {
        switch currentRoute {
        case .hush:
            hushOverviewView
                .tint(themesAccentColor)
                .navigationTitle(currentRoute.title)
        case .assistant:
            assistantDetailView
        case .sessions:
            SessionsWindowView()
                .formStyle(.grouped)
                .padding(.bottom, 8)
                .tint(themesAccentColor)
                .navigationTitle(currentRoute.title)
        default:
            settingsDetailView(for: currentRoute)
                .formStyle(.grouped)
                .padding(.bottom, 8)
                .tint(themesAccentColor)
                .navigationTitle(currentRoute.title)
        }
    }

    var hushOverviewView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Hush")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.9))
            Text("While you are in the moment, it sees it listens, it remembers")
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var assistantDetailView: some View {
        AssistantWindowView(theme: assistantTheme)
            .tint(themesAccentColor)
            .navigationTitle(sessionStore.displayedSession.displayTitle)
    }

    var assistantInspector: some View {
        VStack(spacing: 12) {
            assistantInspectorSwitcher
                .padding(.horizontal, 12)

            Group {
                switch assistantInspectorSection {
                case .queries:
                    assistantInspectorQueriesView
                case .info:
                    assistantInspectorInfoView
                }
            }
        }
        .padding(.top, 12)
        .navigationTitle("Inspector")
    }

    var assistantInspectorSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(AssistantInspectorSection.allCases, id: \.rawValue) { section in
                Button {
                    assistantInspectorSection = section
                } label: {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            assistantInspectorSection == section ? Color.white : Color.primary.opacity(0.72)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    assistantInspectorSection == section
                                        ? themesAccentColor
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var assistantInspectorQueriesView: some View {
        Group {
            if appModel.assistantWorkspace.processEntries.isEmpty {
                Text("No queries yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(appModel.assistantWorkspace.processEntries.enumerated()), id: \.element.id) { index, entry in
                            assistantInspectorQueryCard(entry: entry, index: index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var assistantInspectorInfoView: some View {
        Form {
            Section {
                LabeledContent("Title") {
                    Text(sessionStore.displayedSession.displayTitle)
                        .lineLimit(1)
                }

                LabeledContent("Started") {
                    Text(sessionStore.displayedSession.startedAt.formatted(date: .abbreviated, time: .shortened))
                }

                LabeledContent("Duration") {
                    Text(assistantSessionDurationText(sessionStore.displayedSession))
                }

                LabeledContent("Messages") {
                    Text("\(sessionStore.displayedSession.interactionCount)")
                }

                LabeledContent("Captures") {
                    Text("\(sessionStore.displayedSession.captureCount)")
                }

                LabeledContent("Errors") {
                    Text("\(sessionStore.displayedSession.errorCount)")
                }
            } header: {
                Text("Session")
            }

            Section {
                Toggle("Live transcript", isOn: assistantTranscriptBinding)
                Toggle("Text composer", isOn: assistantTextBinding)
                Toggle("Auto-scroll responses", isOn: assistantAutoScrollBinding)
            } header: {
                Text("Workspace")
            }

            Section {
                Picker("Profile", selection: $assistantSelectedModelMode) {
                    Text("Default").tag(AssistantModelMode.defaultMode.rawValue)
                    Text("Fast").tag(AssistantModelMode.fast.rawValue)
                    Text("Advanced").tag(AssistantModelMode.advanced.rawValue)
                }
                .pickerStyle(.segmented)

                LabeledContent("Selected model") {
                    Text(assistantSelectedModelTitle)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Provider") {
                    Text(assistantSelectedModelProviderTitle)
                }
            } header: {
                Text("Model")
            }

            if assistantHasPendingInput {
                Section {
                    if !assistantPendingPromptPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Draft prompt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(assistantPendingPromptPreview)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }

                    if !appModel.assistantWorkspace.capturePhotos.isEmpty {
                        ForEach(Array(appModel.assistantWorkspace.capturePhotos.enumerated()), id: \.element.id) { index, capture in
                            Button {
                                performOnMainActor {
                                    appModel.assistantWorkspace.focusedCaptureIndex = index
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(capture.title)
                                            .lineLimit(1)
                                        Text(capture.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    if appModel.assistantWorkspace.focusedCaptureIndex == index {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(themesAccentColor)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Pending Input")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func assistantQueryTitle(for entry: OverlayProcessEntry, index: Int) -> String {
        if !entry.normalizedPrompt.isEmpty {
            return entry.normalizedPrompt
        }

        if let firstCaptureTitle = entry.captures.first?.title, !firstCaptureTitle.isEmpty {
            return firstCaptureTitle
        }

        return "Query \(index + 1)"
    }

    @ViewBuilder
    func assistantInspectorQueryCard(entry: OverlayProcessEntry, index: Int) -> some View {
        let isSelected = appModel.assistantWorkspace.selectedProcessEntryID == entry.id

        Button {
            performOnMainActor {
                appModel.assistantWorkspace.selectProcessEntry(entry.id, shouldScroll: true)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(assistantQueryTitle(for: entry, index: index))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(entry.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? themesAccentColor.opacity(0.08)
                            : Color(nsColor: .controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? themesAccentColor.opacity(0.28)
                            : Color(nsColor: .separatorColor).opacity(0.12),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    var assistantTranscriptBinding: Binding<Bool> {
        Binding(
            get: { appModel.assistantWorkspace.showTranscript },
            set: { isOn in
                if isOn != appModel.assistantWorkspace.showTranscript {
                    performOnMainActor {
                        appModel.assistantWorkspace.toggleTranscript()
                    }
                }
            }
        )
    }

    var assistantTextBinding: Binding<Bool> {
        Binding(
            get: { appModel.assistantWorkspace.showText },
            set: { isOn in
                if isOn != appModel.assistantWorkspace.showText {
                    performOnMainActor {
                        appModel.assistantWorkspace.toggleText()
                    }
                }
            }
        )
    }

    var assistantAutoScrollBinding: Binding<Bool> {
        Binding(
            get: { appModel.assistantWorkspace.autoScrollResults },
            set: { isOn in
                if isOn != appModel.assistantWorkspace.autoScrollResults {
                    performOnMainActor {
                        appModel.assistantWorkspace.toggleAutoScrollResults()
                    }
                }
            }
        )
    }

    var assistantHasPendingInput: Bool {
        appModel.assistantWorkspace.hasPendingProcessInput
    }

    var assistantPendingPromptPreview: String {
        let trimmed = appModel.assistantWorkspace.textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 160 {
            return trimmed
        }

        let cutoffIndex = trimmed.index(trimmed.startIndex, offsetBy: 160)
        return String(trimmed[..<cutoffIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    var assistantSelectedModelModeValue: AssistantModelMode {
        AssistantModelMode(rawValue: assistantSelectedModelMode) ?? .defaultMode
    }

    var assistantSelectedModelTitle: String {
        let storedValue = AssistantModelCatalog.storedModelValue(
            for: assistantSelectedModelModeValue,
            defaults: .standard
        )
        return AssistantModelCatalog.option(
            for: storedValue,
            availableOptions: providerStore.availableModels
        )?.title ?? "No model"
    }

    var assistantSelectedModelProviderTitle: String {
        let storedValue = AssistantModelCatalog.storedModelValue(
            for: assistantSelectedModelModeValue,
            defaults: .standard
        )

        guard let providerID = AssistantModelCatalog.option(
            for: storedValue,
            availableOptions: providerStore.availableModels
        )?.providerID else {
            return "Unavailable"
        }

        return providerID.title
    }

    func assistantSessionDurationText(_ session: SessionRecord) -> String {
        let duration = max(0, Int(session.duration))
        let minutes = duration / 60
        let seconds = duration % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }
}
