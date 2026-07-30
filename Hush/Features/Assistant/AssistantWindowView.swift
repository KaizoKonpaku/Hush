import AppKit
import SwiftUI

struct AssistantWindowView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var workspace: AssistantWorkspace
    @ObservedObject private var liveTranscriptionService = AssistantWorkspace.shared.liveTranscriptionService
    @ObservedObject private var providerStore = ProviderAccountStore.shared
    @ObservedObject private var promptPresetStore = AssistantPromptPresetStore.shared
    let theme: InterfaceThemeSnapshot
    @FocusState private var isTextFieldFocused: Bool
    @State private var promptEditorDraft: AssistantPromptEditorDraft?
    @State private var promptPresetEditorDraft: AssistantPromptPresetEditorDraft?
    @AppStorage("assistant.selectedModelMode") private var selectedModelMode = "default"
    @AppStorage("behaviours.text.sendOnCmdEnter") private var textSendOnCmdEnter = false
    @AppStorage("nav.focusInputOnOpen") private var navFocusInputOnOpen = true
    @AppStorage("intel.defaultModel") private var intelDefaultModel = ""
    @AppStorage("intel.fastModel") private var intelFastModel = ""
    @AppStorage("intel.advancedModel") private var intelAdvancedModel = ""

    private var themeAccentColor: Color { theme.accentColor }

    private var themeFontDesign: Font.Design {
        switch theme.fontFamily {
        case "mono":
            return .monospaced
        case "custom":
            return .rounded
        default:
            return .default
        }
    }

    private var themeBaseFontSize: CGFloat {
        InterfaceFontSize.resolved(rawValue: theme.fontSize).pointSize
    }

    private var themeLineSpacing: CGFloat {
        switch theme.lineHeight {
        case "tight":
            return 1
        case "relaxed":
            return 4
        default:
            return 2.5
        }
    }

    private var densityVerticalPadding: CGFloat {
        switch theme.density {
        case "compact":
            return 8
        case "spacious":
            return 16
        default:
            return 12
        }
    }

    private var densityHorizontalPadding: CGFloat {
        switch theme.density {
        case "compact":
            return 14
        case "spacious":
            return 24
        default:
            return 18
        }
    }

    private var liveModePickerTintColor: Color {
        workspace.liveModeAccentColor
    }

    private var assistantColumnMaxWidth: CGFloat {
        760
    }

    private var fieldFillColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.96)
    }

    private var panelFillColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.9)
    }

    private var assistantBubbleFillColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.96)
    }

    private var userBubbleFillColor: Color {
        themeAccentColor.opacity(0.13)
    }

    private var surfaceStrokeColor: Color {
        Color.primary.opacity(0.08)
    }

    private var surfaceShadowColor: Color {
        Color.black.opacity(0.06)
    }

    private var composerBottomPadding: CGFloat {
        densityVerticalPadding + 8
    }

    private var composerReservedHeight: CGFloat {
        let composerHeight: CGFloat = 56
        let attachmentHeight: CGFloat = workspace.capturePhotos.isEmpty ? 0 : 54
        let attachmentSpacing: CGFloat = workspace.capturePhotos.isEmpty ? 0 : 10
        return composerHeight + attachmentHeight + attachmentSpacing + composerBottomPadding
    }

    private var notificationBottomPadding: CGFloat {
        composerReservedHeight + 12
    }

    private func notificationAccent(for notification: OverlayNotificationState) -> Color {
        notification.accent ?? {
            switch notification.kind {
            case .info:
                return .blue
            case .success:
                return .green
            case .error:
                return .red
            }
        }()
    }

    private func notificationFill(for notification: OverlayNotificationState) -> Color {
        notificationAccent(for: notification).opacity(notification.kind == .error ? 0.09 : 0.07)
    }

    private func notificationStroke(for notification: OverlayNotificationState) -> Color {
        notificationAccent(for: notification).opacity(notification.kind == .error ? 0.28 : 0.2)
    }

    private func entryHasError(_ entry: OverlayProcessEntry) -> Bool {
        entry.state == .failed
    }

    private func entryIsSelected(_ entry: OverlayProcessEntry) -> Bool {
        workspace.selectedProcessEntryID == entry.id
    }

    private func resultCardFill(for entry: OverlayProcessEntry) -> Color {
        if entryHasError(entry) {
            return Color.red.opacity(0.08)
        }

        return .clear
    }

    private func resultCardStroke(for entry: OverlayProcessEntry) -> Color {
        if entryHasError(entry) {
            return Color.red.opacity(0.28)
        }

        return .clear
    }

    private func performOnMainActor(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    private func syncTextFieldFocus(with isTextModeVisible: Bool) {
        guard isTextModeVisible else {
            isTextFieldFocused = false
            return
        }

        requestTextFieldFocus()
    }

    private func requestTextFieldFocus() {
        guard navFocusInputOnOpen, workspace.showText else { return }

        Task { @MainActor in
            isTextFieldFocused = false
            await Task.yield()
            isTextFieldFocused = true
        }
    }

    var body: some View {
        mainContent
            .lineSpacing(themeLineSpacing)
            .tint(themeAccentColor)
            .textSelection(.enabled)
            .background(assistantBackground)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if let notification = workspace.overlayNotification {
                        assistantNotificationBar(notification)
                            .frame(maxWidth: assistantColumnMaxWidth, alignment: .leading)
                            .padding(.horizontal, densityHorizontalPadding + 6)
                            .padding(.bottom, notificationBottomPadding)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    composerArea
                }
            }
            .animation(.easeInOut(duration: 0.18), value: workspace.overlayNotification?.id)
            .onAppear {
                requestTextFieldFocus()
            }
            .onChange(of: workspace.showText) { _, isShowing in
                syncTextFieldFocus(with: isShowing)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                requestTextFieldFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                requestTextFieldFocus()
            }
            .sheet(item: $promptEditorDraft) { draft in
                AssistantPromptEditorSheet(draft: draft) { updatedPrompt in
                    performOnMainActor {
                        workspace.resendEditedPrompt(from: draft.entryID, prompt: updatedPrompt)
                    }
                }
            }
            .sheet(item: $promptPresetEditorDraft) { draft in
                AssistantPromptPresetEditorSheet(draft: draft) { name, instructions in
                    promptPresetStore.savePreset(id: draft.presetID, name: name, instructions: instructions)
                }
            }
    }

    private var assistantBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    if workspace.showTranscript {
                        transcriptSection
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("results-top")

                    if workspace.processEntries.isEmpty && !workspace.isProcessing {
                        emptyStateView
                    } else {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(workspace.processEntries) { entry in
                                resultEntryView(entry: entry)
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("results-bottom")
                }
                .frame(maxWidth: assistantColumnMaxWidth, alignment: .leading)
                .padding(.horizontal, densityHorizontalPadding + 8)
                .padding(.top, densityVerticalPadding + 18)
                .padding(.bottom, composerReservedHeight + densityVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if workspace.autoScrollResults {
                    proxy.scrollTo("results-bottom", anchor: .bottom)
                }
            }
            .onChange(of: workspace.resultScrollCommand) { _, command in
                guard let command else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch command {
                    case .top:
                        proxy.scrollTo("results-top", anchor: .top)
                    case .bottom:
                        proxy.scrollTo("results-bottom", anchor: .bottom)
                    case let .entry(id):
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Label("Live Context", systemImage: "waveform")
                    .font(.system(size: themeBaseFontSize - 1, weight: .semibold, design: themeFontDesign))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(liveTranscriptionService.isListening ? "Listening" : "Idle")
                    .font(.system(size: themeBaseFontSize - 2, weight: .medium, design: themeFontDesign))
                    .foregroundStyle(liveTranscriptionService.isListening ? liveModePickerTintColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(liveModePickerTintColor.opacity(liveTranscriptionService.isListening ? 0.14 : 0.08))
                    )
            }

            if liveTranscriptionService.transcriptLines.isEmpty {
                Text(liveTranscriptionService.isListening ? "Listening..." : "Live transcription is idle.")
                    .font(themedFont(size: themeBaseFontSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(liveTranscriptionService.transcriptLines.suffix(6))) { line in
                        Text(line.text)
                            .font(themedFont(size: themeBaseFontSize))
                            .foregroundStyle(Color.primary.opacity(0.76))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(panelFillColor)
        )
        .shadow(color: surfaceShadowColor.opacity(0.8), radius: 18, x: 0, y: 10)
    }

    private var emptyStateView: some View {
        Text("^-^")
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.88))
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
    }

    private var composerArea: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                if !workspace.capturePhotos.isEmpty {
                    attachmentStrip
                }

                composerBar
            }
            .frame(maxWidth: assistantColumnMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, densityHorizontalPadding + 8)
        .padding(.bottom, composerBottomPadding)
    }

    private func assistantNotificationBar(_ notification: OverlayNotificationState) -> some View {
        let accent = notificationAccent(for: notification)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.kind.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .font(.system(size: themeBaseFontSize - 1, weight: .semibold, design: themeFontDesign))
                    .foregroundStyle(Color.primary.opacity(0.92))

                Text(notification.message)
                    .font(themedFont(size: themeBaseFontSize - 1))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                performOnMainActor {
                    workspace.dismissNotification()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .hoverCursor(.pointingHand)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(notificationFill(for: notification))
        )
        .shadow(color: accent.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    private var composerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            attachMenu
            composerField
            promptPresetMenu
            modelMenu
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(fieldFillColor)
        )
        .shadow(color: surfaceShadowColor, radius: 20, x: 0, y: 12)
        .background(
            SubmitShortcutMonitor(
                isFocused: isTextFieldFocused,
                requiresCommandReturn: textSendOnCmdEnter
            ) {
                performOnMainActor {
                    workspace.runProcessWithFeedback()
                }
            }
        )
    }

    private var attachMenu: some View {
        Menu {
            Button("Capture Screen") {
                performOnMainActor {
                    workspace.handleQuickCaptureActionWithFeedback()
                }
            }

            Divider()

            Button("Add Photos…") {
                performOnMainActor {
                    workspace.addPhotoAttachments()
                }
            }

            Button("Add Files…") {
                performOnMainActor {
                    workspace.addFileAttachments()
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverCursor(.pointingHand)
        .help("Attach")
    }

    private var modelMenu: some View {
        Menu {
            Button {
                selectedModelMode = "default"
            } label: {
                modelMenuRow(
                    title: "Default",
                    subtitle: resolvedModelName(for: intelDefaultModel),
                    isSelected: selectedModelMode == "default"
                )
            }

            Button {
                selectedModelMode = "fast"
            } label: {
                modelMenuRow(
                    title: "Fast",
                    subtitle: resolvedModelName(for: intelFastModel),
                    isSelected: selectedModelMode == "fast"
                )
            }

            Button {
                selectedModelMode = "advanced"
            } label: {
                modelMenuRow(
                    title: "Advanced",
                    subtitle: resolvedModelName(for: intelAdvancedModel),
                    isSelected: selectedModelMode == "advanced"
                )
            }
        } label: {
            HStack(spacing: 5) {
                Text(activeModelTitle)
                    .font(.system(size: 11, weight: .medium, design: themeFontDesign))
                    .lineLimit(1)
                Text(activeModelDisplayName)
                    .font(.system(size: 11, weight: .regular, design: themeFontDesign))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 132, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverCursor(.pointingHand)
        .help("Switch model")
    }

    private var promptPresetMenu: some View {
        Menu {
            Button {
                promptPresetStore.selectPreset(id: nil)
            } label: {
                promptPresetMenuRow(
                    title: AssistantPromptPresetCatalog.builtInPresetName,
                    subtitle: "Built in",
                    isSelected: promptPresetStore.selectedPreset == nil
                )
            }

            if !promptPresetStore.presets.isEmpty {
                Divider()

                ForEach(promptPresetStore.presets) { preset in
                    Button {
                        promptPresetStore.selectPreset(id: preset.id)
                    } label: {
                        promptPresetMenuRow(
                            title: preset.trimmedName,
                            subtitle: preset.previewText,
                            isSelected: promptPresetStore.selectedPreset?.id == preset.id
                        )
                    }
                }
            }

            Divider()

            Button("New Prompt…") {
                promptPresetEditorDraft = AssistantPromptPresetEditorDraft()
            }

            if let selectedPreset = promptPresetStore.selectedPreset {
                Button("Edit Selected Prompt…") {
                    promptPresetEditorDraft = AssistantPromptPresetEditorDraft(preset: selectedPreset)
                }

                Button("Delete Selected Prompt", role: .destructive) {
                    promptPresetStore.deletePreset(id: selectedPreset.id)
                }
            }

            Divider()

            Button("Open Prompt Settings") {
                performOnMainActor {
                    appModel.showMainWindow(.section(.intelligence))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "text.badge.star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeAccentColor)
                Text(promptPresetStore.selectedPresetTitle)
                    .font(.system(size: 11, weight: .medium, design: themeFontDesign))
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverCursor(.pointingHand)
        .help("Choose prompt")
    }

    private var composerField: some View {
        TextField("Ask or search…", text: $workspace.textInput, axis: .vertical)
            .textFieldStyle(.plain)
            .focused($isTextFieldFocused)
            .hoverCursor(.iBeam)
            .font(themedFont(size: themeBaseFontSize))
            .lineLimit(1...5)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendButton: some View {
        Button {
            performOnMainActor {
                workspace.runProcessWithFeedback()
            }
        } label: {
            Group {
                if workspace.isProcessing {
                    ProgressView()
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(workspace.canSubmitProcess ? themeAccentColor : Color.secondary.opacity(0.16))
            )
            .foregroundStyle(workspace.canSubmitProcess ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .hoverCursor(.pointingHand)
        .disabled(!workspace.canSubmitProcess)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(workspace.capturePhotos.enumerated()), id: \.element.id) { index, capture in
                    Button {
                        performOnMainActor {
                            workspace.focusedCaptureIndex = index
                        }
                    } label: {
                        HStack(spacing: 8) {
                            attachmentThumbnail(capture, width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(capture.title)
                                    .font(.system(size: themeBaseFontSize - 1, weight: .medium, design: themeFontDesign))
                                    .lineLimit(1)
                                Text(capture.subtitle)
                                    .font(.system(size: themeBaseFontSize - 3, weight: .regular, design: themeFontDesign))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    workspace.focusedCaptureIndex == index
                                        ? themeAccentColor.opacity(0.14)
                                        : fieldFillColor
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverCursor(.pointingHand)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func resultEntryView(entry: OverlayProcessEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !entry.prompt.isEmpty || !entry.captures.isEmpty {
                conversationBubble(role: .user, timestamp: nil) {
                    if !entry.prompt.isEmpty {
                        Text(entry.prompt)
                            .font(themedFont(size: themeBaseFontSize))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Captured context")
                            .font(themedFont(size: themeBaseFontSize, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.82))
                    }

                    if !entry.captures.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(entry.captures) { capture in
                                    attachmentThumbnail(capture, width: 72, height: 48)
                                        .help(capture.title)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if entry.hasStoredAttachmentSummary {
                        Text(storedAttachmentSummary(for: entry))
                            .font(.system(size: themeBaseFontSize - 2, weight: .medium, design: themeFontDesign))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            conversationBubble(
                role: .assistant,
                timestamp: entry.createdAt.formatted(date: .omitted, time: .shortened),
                emphasis: entryHasError(entry) ? .error : (entryIsSelected(entry) ? .selected : .normal)
            ) {
                if let response = entry.response, !response.isEmpty {
                    Text(response)
                        .font(themedFont(size: themeBaseFontSize + 0.5))
                        .foregroundStyle(Color.primary.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                } else if entry.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Thinking…")
                            .font(themedFont(size: themeBaseFontSize))
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = entry.errorMessage, !errorMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)

                        Text("Request failed")
                            .font(themedFont(size: themeBaseFontSize, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Text(errorMessage)
                        .font(themedFont(size: themeBaseFontSize))
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !entry.isProcessing {
                    assistantEntryMenu(entry: entry)
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                }
            }
        }
        .padding(.vertical, 4)
        .id(entry.id)
    }

    private func storedAttachmentSummary(for entry: OverlayProcessEntry) -> String {
        let totalCount = entry.captureCount
        let unavailableCount = entry.storedAttachmentCount

        if unavailableCount == totalCount {
            return "\(totalCount) attachment\(totalCount == 1 ? "" : "s") were part of this request, but HUSH does not keep the files themselves in session history."
        }

        return "\(unavailableCount) earlier attachment\(unavailableCount == 1 ? "" : "s") from this request are no longer loaded locally."
    }

    private func assistantEntryMenu(entry: OverlayProcessEntry) -> some View {
        Menu {
            Button("Copy Response") {
                copyResponse(for: entry)
            }

            Button("Copy Prompt") {
                copyPrompt(for: entry)
            }

            Button("Load Into Composer") {
                performOnMainActor {
                    workspace.loadPromptIntoComposer(from: entry.id)
                }
            }

            Divider()

            Button("Edit & Resend") {
                promptEditorDraft = AssistantPromptEditorDraft(entry: entry)
            }

            Button("Regenerate") {
                performOnMainActor {
                    workspace.regenerateResponse(from: entry.id)
                }
            }

            Button("Branch Conversation") {
                performOnMainActor {
                    workspace.branchConversation(from: entry.id)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverCursor(.pointingHand)
    }

    private func copyPrompt(for entry: OverlayProcessEntry) {
        copyToPasteboard(entry.prompt)
    }

    private func copyResponse(for entry: OverlayProcessEntry) {
        if let response = entry.response, !response.isEmpty {
            copyToPasteboard(response)
            return
        }

        if let errorMessage = entry.errorMessage, !errorMessage.isEmpty {
            copyToPasteboard(errorMessage)
        }
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var liveModeInputLabel: String {
        switch workspace.resolvedLiveInputMode() {
        case .both:
            return "Mic + System"
        case .mic:
            return "Microphone"
        case .system:
            return "System Audio"
        }
    }

    private func assistantHeaderChip(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeAccentColor)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(themeAccentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: themeBaseFontSize - 2, weight: .semibold, design: themeFontDesign))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: themeBaseFontSize - 3, weight: .regular, design: themeFontDesign))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func assistantPromptSuggestion(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeAccentColor)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(themeAccentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: themeBaseFontSize - 1, weight: .semibold, design: themeFontDesign))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: themeBaseFontSize - 3, weight: .regular, design: themeFontDesign))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func assistantSuggestionCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(themeAccentColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(themeAccentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: themeBaseFontSize + 0.5, weight: .semibold, design: themeFontDesign))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(themedFont(size: themeBaseFontSize - 0.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func conversationBubble<Content: View>(
        role: AssistantConversationRole,
        timestamp: String?,
        emphasis: AssistantConversationBubbleEmphasis = .normal,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if role == .assistant {
                if theme.showAvatars {
                    assistantConversationAvatar(for: role, emphasis: emphasis)
                }

                conversationBubbleBody(role: role, timestamp: timestamp, emphasis: emphasis, content: content)

                Spacer(minLength: 52)
            } else {
                Spacer(minLength: 52)

                conversationBubbleBody(role: role, timestamp: timestamp, emphasis: emphasis, content: content)

                if theme.showAvatars {
                    assistantConversationAvatar(for: role, emphasis: emphasis)
                }
            }
        }
    }

    private func conversationBubbleBody<Content: View>(
        role: AssistantConversationRole,
        timestamp: String?,
        emphasis: AssistantConversationBubbleEmphasis,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(role.title)
                    .font(.system(size: themeBaseFontSize - 2, weight: .semibold, design: themeFontDesign))
                    .foregroundStyle(role == .user ? themeAccentColor : .secondary)

                if let timestamp, !timestamp.isEmpty {
                    Text(timestamp)
                        .font(.system(size: themeBaseFontSize - 3, weight: .medium, design: themeFontDesign))
                        .foregroundStyle(.tertiary)
                }
            }

            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: 560, alignment: .leading)
        .hoverCursor(.iBeam)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(bubbleFillColor(for: role, emphasis: emphasis))
        )
        .shadow(color: bubbleShadowColor(for: role, emphasis: emphasis), radius: 18, x: 0, y: 10)
        .overlay(alignment: .leading) {
            if role == .assistant && emphasis == .selected {
                Capsule()
                    .fill(themeAccentColor.opacity(0.82))
                    .frame(width: 4, height: 26)
                    .padding(.leading, 10)
            }
        }
    }

    private func assistantConversationAvatar(
        for role: AssistantConversationRole,
        emphasis: AssistantConversationBubbleEmphasis
    ) -> some View {
        let fillColor: Color = {
            switch role {
            case .user:
                return themeAccentColor.opacity(0.18)
            case .assistant:
                switch emphasis {
                case .error:
                    return Color.red.opacity(0.16)
                case .selected:
                    return themeAccentColor.opacity(0.18)
                case .normal:
                    return Color.primary.opacity(0.08)
                }
            }
        }()

        return Text(role.avatarText)
            .font(.system(size: themeBaseFontSize - 2, weight: .semibold, design: themeFontDesign))
            .foregroundStyle(role == .user ? themeAccentColor : Color.primary.opacity(0.82))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(fillColor)
            )
    }

    private func bubbleFillColor(
        for role: AssistantConversationRole,
        emphasis: AssistantConversationBubbleEmphasis
    ) -> Color {
        switch (role, emphasis) {
        case (.user, _):
            return userBubbleFillColor
        case (.assistant, .error):
            return Color.red.opacity(0.1)
        case (.assistant, .selected):
            return themeAccentColor.opacity(0.1)
        case (.assistant, .normal):
            return assistantBubbleFillColor
        }
    }

    private func bubbleShadowColor(
        for role: AssistantConversationRole,
        emphasis: AssistantConversationBubbleEmphasis
    ) -> Color {
        switch (role, emphasis) {
        case (.user, _):
            return themeAccentColor.opacity(0.12)
        case (.assistant, .error):
            return Color.red.opacity(0.08)
        case (.assistant, .selected):
            return themeAccentColor.opacity(0.12)
        case (.assistant, .normal):
            return surfaceShadowColor.opacity(0.9)
        }
    }

    @ViewBuilder
    private func attachmentThumbnail(_ capture: OverlayCapture, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(capture.usesImageFill ? 0.03 : 0.08))
            .frame(width: width, height: height)
            .overlay {
                if capture.usesImageFill {
                    Image(nsImage: capture.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(nsImage: capture.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(24, width - 12), height: min(24, height - 12))
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func themedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: themeFontDesign)
    }

    private var activeModelTitle: String {
        switch selectedModelMode {
        case "fast":
            return "Fast"
        case "advanced":
            return "Advanced"
        default:
            return "Default"
        }
    }

    private var activeModelDisplayName: String {
        switch selectedModelMode {
        case "fast":
            return resolvedModelName(for: intelFastModel)
        case "advanced":
            return resolvedModelName(for: intelAdvancedModel)
        default:
            return resolvedModelName(for: intelDefaultModel)
        }
    }

    private func resolvedModelName(for value: String) -> String {
        AssistantModelCatalog.option(for: value, availableOptions: providerStore.availableModels)?.title ?? "No model"
    }

    private func modelMenuRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(themeAccentColor)
            }
        }
    }

    private func promptPresetMenuRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(themeAccentColor)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }
}

private enum AssistantConversationRole {
    case user
    case assistant

    var title: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "HUSH"
        }
    }

    var avatarText: String {
        switch self {
        case .user:
            return "Y"
        case .assistant:
            return "H"
        }
    }
}

private enum AssistantConversationBubbleEmphasis {
    case normal
    case selected
    case error
}

private struct AssistantPromptEditorDraft: Identifiable {
    let id: UUID
    let entryID: UUID
    let prompt: String
    let loadedAttachmentCount: Int
    let missingAttachmentCount: Int

    init(entry: OverlayProcessEntry) {
        id = entry.id
        entryID = entry.id
        prompt = entry.prompt
        loadedAttachmentCount = entry.captures.count
        missingAttachmentCount = entry.storedAttachmentCount
    }
}

struct AssistantPromptPresetEditorDraft: Identifiable {
    let id: UUID
    let presetID: UUID?
    let title: String
    let initialName: String
    let initialInstructions: String

    init() {
        id = UUID()
        presetID = nil
        title = "New Prompt"
        initialName = ""
        initialInstructions = ""
    }

    init(preset: AssistantPromptPreset) {
        id = preset.id
        presetID = preset.id
        title = "Edit Prompt"
        initialName = preset.name
        initialInstructions = preset.instructions
    }
}

struct AssistantPromptPresetEditorSheet: View {
    let draft: AssistantPromptPresetEditorDraft
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var instructions: String

    init(
        draft: AssistantPromptPresetEditorDraft,
        onSave: @escaping (String, String) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.initialName)
        _instructions = State(initialValue: draft.initialInstructions)
    }

    private var canSave: Bool {
        !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Prompt presets replace the default HUSH instructions sent with each request. Use them for tone, structure, or recurring working styles.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("Prompt name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .hoverCursor(.iBeam)

                TextEditor(text: $instructions)
                    .font(.body)
                    .hoverCursor(.iBeam)
                    .frame(minHeight: 220)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }
            .padding(20)
            .navigationTitle(draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, instructions)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}

private struct AssistantPromptEditorSheet: View {
    let draft: AssistantPromptEditorDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String

    init(draft: AssistantPromptEditorDraft, onSave: @escaping (String) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _prompt = State(initialValue: draft.prompt)
    }

    private var canResend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.loadedAttachmentCount > 0
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Adjust the prompt and resend it from the conversation state right before this turn.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.body)
                    .hoverCursor(.iBeam)
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    if draft.loadedAttachmentCount > 0 {
                        Text("\(draft.loadedAttachmentCount) loaded attachment\(draft.loadedAttachmentCount == 1 ? "" : "s") will be resent.")
                    }

                    if draft.missingAttachmentCount > 0 {
                        Text("\(draft.missingAttachmentCount) past attachment\(draft.missingAttachmentCount == 1 ? "" : "s") are not stored locally and cannot be resent.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .navigationTitle("Edit & Resend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Resend") {
                        onSave(prompt)
                        dismiss()
                    }
                    .disabled(!canResend)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 340)
    }
}

private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                guard isHovering != self.isHovering else { return }
                self.isHovering = isHovering

                if isHovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard isHovering else { return }
                isHovering = false
                NSCursor.pop()
            }
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
    }
}

#Preview {
    AssistantWindowView(
        theme: InterfaceThemeSnapshot(
            accentRed: 0.0,
            accentGreen: 0.48,
            accentBlue: 1.0,
            accentActionPills: false,
            materialStyle: InterfaceMaterialStyle.medium.rawValue,
            density: "comfortable",
            fontFamily: "system",
            fontSize: InterfaceFontSize.defaultRawValue,
            lineHeight: "normal",
            messageLayout: "bubbles",
            showAvatars: true
        )
    )
        .environment(AppModel.shared)
        .environmentObject(AssistantWorkspace.shared)
}
