import SwiftUI
import CoreGraphics
import AppKit

private enum OverlayLayout {
    static let panelWidth: CGFloat = 540
    static let headerHeight: CGFloat = 56
    static let dividerHeight: CGFloat = 1
    static let transcriptSectionHeight: CGFloat = 54
    static let transcriptViewportHeight: CGFloat = 48
    static let transcriptDebugPanelHeight: CGFloat = 176
    static let transcriptDebugSectionHeight: CGFloat =
        transcriptViewportHeight + transcriptDebugPanelHeight + 14
    static let transcriptDebugEventLimit = 4
    static let resultSectionHeight: CGFloat = 220
    static let resultSectionBlockHeight: CGFloat = resultSectionHeight + 16
    static let textSectionHeight: CGFloat = 56
    static let captureSectionHeight: CGFloat = 60
    static let notificationSectionHeight: CGFloat = 94
    static let minimumScrollableBodyHeight: CGFloat = 96
    static let defaultMaximumPanelHeight: CGFloat = 680
    static let maximumPanelScreenRatio: CGFloat = 0.82
    static var edgeCornerRadius: CGFloat { OverlayCornerMetrics.defaultRadius }

    static var maximumPanelHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? defaultMaximumPanelHeight
        return min(
            defaultMaximumPanelHeight,
            max(360, floor(visibleHeight * maximumPanelScreenRatio))
        )
    }
}

private enum OverlayCornerMetrics {
    static let fallbackRadius: CGFloat = 8

    static var defaultRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return NativeGlassDefaults.cornerRadius
        }

        return fallbackRadius
    }
}

@available(macOS 26.0, *)
private enum NativeGlassDefaults {
    static let cornerRadius = NSGlassEffectView().cornerRadius
}

struct OverlayView: View {
    @AppStorage("behaviours.live.autoListen") private var liveAutoListen = true
    @AppStorage("behaviours.live.language") private var liveLanguage = "system"
    @AppStorage("behaviours.live.audioSource") private var liveAudioSource = "both"
    @AppStorage("settings.appearance") private var appearanceMode = "system"
    @AppStorage("themes.accent.red") private var themesAccentRed = 0.0
    @AppStorage("themes.accent.green") private var themesAccentGreen = 0.48
    @AppStorage("themes.accent.blue") private var themesAccentBlue = 1.0
    @AppStorage("themes.accentActionPills") private var themesAccentActionPills = false
    @AppStorage("themes.materialStyle") private var themesMaterialStyle = InterfaceMaterialStyle.medium.rawValue
    @AppStorage("themes.density") private var themesDensity = "comfortable"
    @AppStorage("themes.fontFamily") private var themesFontFamily = "system"
    @AppStorage("themes.fontSize") private var themesFontSize = InterfaceFontSize.defaultRawValue
    @AppStorage("themes.lineHeight") private var themesLineHeight = "normal"
    @AppStorage("themes.messageLayout") private var themesMessageLayout = "bubbles"
    @AppStorage("themes.showAvatars") private var themesShowAvatars = true

    private var settings: OverlaySettingsSnapshot {
        OverlaySettingsSnapshot(
            appearanceMode: appearanceMode,
            liveAutoListen: liveAutoListen,
            liveLanguage: liveLanguage,
            liveAudioSource: liveAudioSource,
            theme: InterfaceThemeSnapshot(
                accentRed: themesAccentRed,
                accentGreen: themesAccentGreen,
                accentBlue: themesAccentBlue,
                accentActionPills: themesAccentActionPills,
                materialStyle: InterfaceMaterialStyle.normalizedRawValue(themesMaterialStyle),
                density: themesDensity,
                fontFamily: themesFontFamily,
                fontSize: themesFontSize,
                lineHeight: themesLineHeight,
                messageLayout: themesMessageLayout,
                showAvatars: themesShowAvatars
            )
        )
    }

    var body: some View {
        OverlayContentView(settings: settings)
    }
}

private struct OverlayContentView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var workspace: AssistantWorkspace
    @ObservedObject private var liveTranscriptionService = AssistantWorkspace.shared.liveTranscriptionService
    @AppStorage("behaviours.text.sendOnCmdEnter") private var textSendOnCmdEnter = false
    @AppStorage("debug.liveVoiceSurface") private var liveVoiceDebugVisible = false
    @AppStorage("nav.focusInputOnOpen") private var navFocusInputOnOpen = true
    let settings: OverlaySettingsSnapshot
    @State private var hoveredOption: String?
    @State private var isMascotPressed = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var preferredColorSchemeOverride: ColorScheme? {
        InterfaceAppearanceMode.preferredColorScheme(for: settings.appearanceMode)
    }

    private var themeFontDesign: Font.Design {
        switch settings.theme.fontFamily {
        case "mono": return .monospaced
        case "custom": return .rounded
        default: return .default
        }
    }

    private var themeBaseFontSize: CGFloat {
        InterfaceFontSize.resolved(rawValue: settings.theme.fontSize).pointSize
    }

    private var themeLineSpacing: CGFloat {
        switch settings.theme.lineHeight {
        case "tight": return 1
        case "relaxed": return 4
        default: return 2.5
        }
    }

    private var densityVerticalPadding: CGFloat {
        switch settings.theme.density {
        case "compact": return 6
        case "spacious": return 10
        default: return 8
        }
    }

    private var densityHorizontalPadding: CGFloat {
        switch settings.theme.density {
        case "compact": return 10
        case "spacious": return 14
        default: return 12
        }
    }

    private var messageCornerRadius: CGFloat {
        settings.theme.messageLayout == "flat" ? 0 : 8
    }

    private var messageFillOpacity: CGFloat {
        settings.theme.messageLayout == "flat" ? 0 : 0.06
    }

    private var highlightColor: Color {
        themeAccentColor
    }

    private var themeAccentColor: Color { settings.theme.accentColor }

    private var actionPillSelectedFill: AnyShapeStyle {
        if settings.theme.accentActionPills {
            return AnyShapeStyle(themeAccentColor.opacity(0.18))
        }

        return AnyShapeStyle(Color.primary.opacity(0.2))
    }

    private func themedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: themeFontDesign)
    }

    private func performOnMainActor(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    private var liveModePickerTintColor: Color {
        workspace.liveModeAccentColor
    }

    private var liveModeShortcutFill: AnyShapeStyle {
        switch workspace.resolvedLiveInputMode() {
        case .both:
            return AnyShapeStyle(Color.red.opacity(0.35))
        case .mic:
            return AnyShapeStyle(Color.orange.opacity(0.4))
        case .system:
            return AnyShapeStyle(Color(red: 0.56, green: 0.33, blue: 0.92).opacity(0.35))
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

    private var overlayContentSize: CGSize {
        CGSize(width: OverlayLayout.panelWidth, height: overlayContentHeight)
    }

    private var hasScrollableContent: Bool {
        workspace.showTranscript || !workspace.processEntries.isEmpty
    }

    private var hasComposerContent: Bool {
        workspace.showText || workspace.showCapture
    }

    private var hasOverlayNotification: Bool {
        workspace.overlayNotification != nil
    }

    private var desiredScrollableContentHeight: CGFloat {
        var height: CGFloat = 0

        if workspace.showTranscript {
            height += liveVoiceDebugVisible
                ? OverlayLayout.transcriptDebugSectionHeight
                : OverlayLayout.transcriptSectionHeight
        }

        if workspace.showTranscript && !workspace.processEntries.isEmpty {
            height += OverlayLayout.dividerHeight
        }

        if !workspace.processEntries.isEmpty {
            height += OverlayLayout.resultSectionBlockHeight
        }

        return height
    }

    private var fixedOverlayContentHeight: CGFloat {
        var height = OverlayLayout.headerHeight

        if hasScrollableContent || hasComposerContent || hasOverlayNotification {
            height += OverlayLayout.dividerHeight
        }

        if hasScrollableContent && hasComposerContent {
            height += OverlayLayout.dividerHeight
        }

        if workspace.showText {
            height += OverlayLayout.textSectionHeight
        }

        if workspace.showText && workspace.showCapture {
            height += OverlayLayout.dividerHeight
        }

        if workspace.showCapture {
            height += OverlayLayout.captureSectionHeight
        }

        if (hasScrollableContent || hasComposerContent) && hasOverlayNotification {
            height += OverlayLayout.dividerHeight
        }

        if hasOverlayNotification {
            height += OverlayLayout.notificationSectionHeight
        }

        return height
    }

    private var scrollableBodyHeight: CGFloat {
        guard hasScrollableContent else { return 0 }

        let availableHeight = max(0, OverlayLayout.maximumPanelHeight - fixedOverlayContentHeight)
        let preferredHeight = min(desiredScrollableContentHeight, availableHeight)
        return max(min(preferredHeight, desiredScrollableContentHeight), min(OverlayLayout.minimumScrollableBodyHeight, availableHeight))
    }

    private var overlayContentHeight: CGFloat {
        let height = fixedOverlayContentHeight + scrollableBodyHeight
        return (height * 2).rounded() / 2
    }

    private var visibleLiveTranscriptLines: [LiveTranscriptLine] {
        Array(liveTranscriptionService.transcriptLines.suffix(2))
    }

    private var liveVoiceDebugSnapshot: LiveVoiceDebugSnapshot {
        liveTranscriptionService.voiceDebugSnapshot
    }

    private func liveVoiceDebugResponseLabel(_ snapshot: LiveVoiceDebugSnapshot) -> String {
        let base = snapshot.responseState.label
        if let activeID = shortDebugIdentifier(snapshot.activeResponseID ?? snapshot.activeItemID),
           snapshot.responseState != .idle,
           snapshot.responseState != .completed,
           snapshot.responseState != .cancelled {
            return "\(base) • \(activeID)"
        }

        return base
    }

    private func shortDebugIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 8 ? String(trimmed.suffix(8)) : trimmed
    }

    private func formattedDebugTimestamp(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    var body: some View {
        overlayStyledContent
            .onAppear {
                requestTextFieldFocus()
            }
            .task(id: overlayContentHeight) {
                await Task.yield()
                appModel.updateOverlayContentSize(overlayContentSize)
            }
            .onChange(of: workspace.showText) { _, isShowing in
                syncTextFieldFocus(with: isShowing)
            }
            .onChange(of: settings.liveAudioSource) { _, _ in
                workspace.liveAudioSourceDidChange()
            }
            .onChange(of: settings.liveLanguage) { _, _ in
                workspace.liveLanguageDidChange()
            }
            .onChange(of: settings.liveAutoListen) { _, _ in
                workspace.liveAutoListenDidChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                requestTextFieldFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                requestTextFieldFocus()
            }
    }

    private var overlayCoreContent: some View {
        VStack(spacing: 0) {
            headerBar

            if hasScrollableContent || hasComposerContent || hasOverlayNotification {
                Divider()
                    .padding(.horizontal, 24)
            }

            if hasScrollableContent {
                scrollableOverlayBody
                    .frame(height: scrollableBodyHeight)
            }

            if hasScrollableContent && hasComposerContent {
                Divider()
                    .padding(.horizontal, 24)
            }

            if workspace.showText {
                textInputSection
            }

            if workspace.showText && workspace.showCapture {
                Divider()
                    .padding(.horizontal, 24)
            }

            if workspace.showCapture {
                captureStripSection
            }

            if (hasScrollableContent || hasComposerContent) && hasOverlayNotification {
                Divider()
                    .padding(.horizontal, 24)
            }

            if let overlayNotification = workspace.overlayNotification {
                OverlayNotificationBar(notification: overlayNotification) {
                    workspace.dismissNotification()
                }
                .frame(height: OverlayLayout.notificationSectionHeight)
            }
        }
    }

    private var scrollableOverlayBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if workspace.showTranscript {
                        liveTranscriptSection
                            .frame(
                                height: liveVoiceDebugVisible
                                    ? OverlayLayout.transcriptDebugSectionHeight
                                    : OverlayLayout.transcriptSectionHeight,
                                alignment: .top
                            )
                    }

                    if workspace.showTranscript && !workspace.processEntries.isEmpty {
                        Divider()
                            .padding(.horizontal, 24)
                    }

                    if !workspace.processEntries.isEmpty {
                        resultsListSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .onAppear {
                if workspace.autoScrollResults {
                    proxy.scrollTo("results-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var resultsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .frame(height: 1)
                .id("results-top")

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(workspace.processEntries.enumerated()), id: \.element.id) { index, entry in
                    resultEntryView(entry: entry, index: index)
                }
            }

            Color.clear
                .frame(height: 1)
                .id("results-bottom")
        }
        .frame(maxWidth: 500, alignment: .leading)
        .padding(.horizontal, densityHorizontalPadding)
        .padding(.vertical, max(4, densityVerticalPadding - 2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            Button(action: openAssistantInMainWindow) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .hoverCursor(.pointingHand)
            .padding(8)
        }
    }

    private var textInputSection: some View {
        TextField("Type something…", text: $workspace.textInput)
            .textFieldStyle(.plain)
            .focused($isTextFieldFocused)
            .hoverCursor(.iBeam)
            .font(themedFont(size: themeBaseFontSize))
            .padding(.horizontal, densityHorizontalPadding)
            .padding(.vertical, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                Color.primary.opacity(0.08)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.08),
                                .init(color: .white, location: 0.92),
                                .init(color: .clear, location: 1.0),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(height: OverlayLayout.textSectionHeight)
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

    private var captureStripSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: {
                performOnMainActor {
                    workspace.handleCaptureAction()
                }
            }) {
                VStack(spacing: 0) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(workspace.capturePhotos.count >= 6 ? 0.3 : 0.5))
                        .frame(height: 24)
                    Group {
                        if workspace.capturePhotos.count >= 6 {
                            Text("LIMIT")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.5))
                        } else {
                            Text("\(6 - workspace.capturePhotos.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.12)))
                }
                .frame(width: 48, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundStyle(Color.primary.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .hoverCursor(.pointingHand)
            .disabled(workspace.capturePhotos.count >= 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(workspace.capturePhotos.enumerated()), id: \.element.id) { index, capture in
                        Button {
                            performOnMainActor {
                                workspace.focusedCaptureIndex = index
                            }
                        } label: {
                            overlayCaptureThumbnail(
                                capture,
                                width: 76,
                                height: 46,
                                isSelected: workspace.focusedCaptureIndex == index
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverCursor(.pointingHand)
                        .help(capture.title)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 2)
            .frame(height: 54)
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 4) {
                captureShortcutHintRow(for: .focusCapturePrevious)
                captureShortcutHintRow(for: .deleteCapture)
                captureShortcutHintRow(for: .focusCaptureNext)
            }
            .id(appModel.shortcutConfigurationVersion)
        }
        .padding(.horizontal, densityHorizontalPadding)
        .padding(.vertical, 2)
        .frame(height: OverlayLayout.captureSectionHeight)
        .frame(maxWidth: .infinity)
    }

    private var overlayStyledContent: some View {
        overlayCoreContent
            .lineSpacing(themeLineSpacing)
            .tint(themeAccentColor)
            .frame(
                width: OverlayLayout.panelWidth,
                height: overlayContentHeight,
                alignment: .top
            )
            .background(GlassBackground(materialStyle: settings.theme.materialStyle))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: OverlayLayout.edgeCornerRadius,
                    style: .continuous
                )
            )
            .preferredColorScheme(preferredColorSchemeOverride)
    }

    private var headerBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                performOnMainActor {
                    workspace.startNewSessionWithFeedback()
                }
            }) {
                Text(isMascotPressed ? "-_-" : "^-^")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isDarkMode ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.15))
                    .cornerRadius(6)
            }
            .buttonStyle(OverlayTactileButtonStyle())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { isPressing in
                isMascotPressed = isPressing
            }, perform: {})

            Divider()
                .frame(height: 32)
                .padding(.horizontal, 8)

            ActionButton(
                shortcutTokens: shortcutTokens(for: .openSettings),
                name: "App",
                isSelected: false,
                isHovered: hoveredOption == "app",
                selectedFill: actionPillSelectedFill,
                shortcutFill: AnyShapeStyle(Color.primary.opacity(0.15)),
                fontDesign: themeFontDesign,
                textSize: max(11, themeBaseFontSize - 1),
                control: .appWindow,
                showsProgress: false
            ) {
                appModel.toggleMainWindow(appModel.mainWindowRoute)
            }
            .onHover { hoveredOption = $0 ? "app" : nil }

            Divider()
                .frame(height: 32)
                .padding(.horizontal, 8)

            HStack(spacing: 0) {
                ActionButton(
                    shortcutTokens: shortcutTokens(for: .live),
                    name: "Live",
                    isSelected: workspace.showTranscript,
                    isHovered: hoveredOption == "live",
                    selectedFill: actionPillSelectedFill,
                    shortcutFill: liveModeShortcutFill,
                    fontDesign: themeFontDesign,
                    textSize: max(11, themeBaseFontSize - 1),
                    control: .live,
                    showsProgress: false
                ) {
                    workspace.toggleTranscriptWithFeedback()
                }
                .onHover { hoveredOption = $0 ? "live" : nil }

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                ActionButton(
                    shortcutTokens: shortcutTokens(for: .text),
                    name: "Text",
                    isSelected: workspace.showText,
                    isHovered: hoveredOption == "text",
                    selectedFill: actionPillSelectedFill,
                    shortcutFill: AnyShapeStyle(Color.primary.opacity(0.15)),
                    fontDesign: themeFontDesign,
                    textSize: max(11, themeBaseFontSize - 1),
                    control: .text,
                    showsProgress: false
                ) {
                    workspace.toggleTextWithFeedback()
                }
                .onHover { hoveredOption = $0 ? "text" : nil }

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                ActionButton(
                    shortcutTokens: shortcutTokens(for: .capture),
                    name: "Capture",
                    isSelected: workspace.showCapture,
                    isHovered: hoveredOption == "capture",
                    selectedFill: actionPillSelectedFill,
                    shortcutFill: AnyShapeStyle(Color.primary.opacity(0.15)),
                    fontDesign: themeFontDesign,
                    textSize: max(11, themeBaseFontSize - 1),
                    control: .capture,
                    showsProgress: false
                ) {
                    workspace.handleCaptureActionWithFeedback(mode: .full)
                }
                .onHover { hoveredOption = $0 ? "capture" : nil }

                Divider()
                    .frame(height: 32)
                    .padding(.horizontal, 8)

                ActionButton(
                    shortcutTokens: shortcutTokens(for: .process),
                    name: "Process",
                    isSelected: workspace.hasPendingProcessInput || workspace.isProcessing,
                    isHovered: hoveredOption == "process",
                    selectedFill: actionPillSelectedFill,
                    shortcutFill: AnyShapeStyle(Color.primary.opacity(0.15)),
                    fontDesign: themeFontDesign,
                    textSize: max(11, themeBaseFontSize - 1),
                    control: .process,
                    showsProgress: workspace.isProcessing
                ) {
                    workspace.runProcessWithFeedback()
                }
                .disabled(!workspace.canSubmitProcess)
                .opacity(workspace.canSubmitProcess || workspace.isProcessing ? 1 : 0.5)
                .onHover { hoveredOption = $0 ? "process" : nil }
            }
        }
        .padding(.horizontal, densityHorizontalPadding)
        .padding(.vertical, densityVerticalPadding)
        .frame(height: OverlayLayout.headerHeight)
    }

    private var liveTranscriptSection: some View {
        VStack(alignment: .center, spacing: 8) {
            if liveTranscriptionService.transcriptLines.isEmpty {
                Text(liveTranscriptionService.isListening ? "Listening…" : "Live transcription is idle.")
                    .font(themedFont(size: themeBaseFontSize - 2))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .frame(
                        maxWidth: .infinity,
                        minHeight: OverlayLayout.transcriptViewportHeight,
                        maxHeight: OverlayLayout.transcriptViewportHeight,
                        alignment: .center
                    )
                    .multilineTextAlignment(.center)
            } else {
                VStack(alignment: .center, spacing: 6) {
                    ForEach(visibleLiveTranscriptLines) { line in
                        transcriptLineView(line)
                    }
                }
                .frame(maxWidth: 500, alignment: .center)
                .frame(height: OverlayLayout.transcriptViewportHeight)
            }

            if liveVoiceDebugVisible {
                liveVoiceDebugPanel
                    .frame(height: OverlayLayout.transcriptDebugPanelHeight, alignment: .top)
                    .frame(maxWidth: 500, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, densityHorizontalPadding)
        .padding(.vertical, 3)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Button {
                    liveVoiceDebugVisible.toggle()
                } label: {
                    Image(systemName: liveVoiceDebugVisible ? "ladybug.fill" : "ladybug")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            liveVoiceDebugVisible
                                ? AnyShapeStyle(Color.orange.opacity(0.9))
                                : AnyShapeStyle(Color.primary.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
                .hoverCursor(.pointingHand)
                .help(liveVoiceDebugVisible ? "Hide Live debug" : "Show Live debug")

                Button(action: openAssistantInMainWindow) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .hoverCursor(.pointingHand)
            }
            .padding(8)
        }
    }

    private var liveVoiceDebugPanel: some View {
        let debug = liveVoiceDebugSnapshot
        let recentEvents = Array(debug.events.suffix(OverlayLayout.transcriptDebugEventLimit).reversed())

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                liveVoiceDebugBadge(
                    title: "Backend",
                    value: debug.backendLabel,
                    isHighlighted: debug.backendLabel.contains("Realtime")
                )
                liveVoiceDebugBadge(
                    title: "Model",
                    value: debug.transcriptionModelLabel,
                    isHighlighted: debug.backendLabel.contains("Realtime")
                )
            }

            HStack(spacing: 6) {
                liveVoiceDebugBadge(
                    title: "Mic",
                    value: debug.micCaptureLabel,
                    isHighlighted: debug.micCaptureLabel == "Running"
                )
                liveVoiceDebugBadge(
                    title: "Speech",
                    value: debug.speechLabel,
                    isHighlighted: debug.speechLabel != "No speech"
                )
                liveVoiceDebugBadge(
                    title: "Response",
                    value: liveVoiceDebugResponseLabel(debug),
                    isHighlighted: debug.responseState != .idle
                )
            }

            if let loopHint = debug.loopHint, !loopHint.isEmpty {
                Text(loopHint)
                    .font(themedFont(size: max(10, themeBaseFontSize - 4), weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if recentEvents.isEmpty {
                Text("No live debug events yet.")
                    .font(themedFont(size: max(10, themeBaseFontSize - 4)))
                    .foregroundStyle(Color.primary.opacity(0.55))
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(recentEvents) { event in
                        liveVoiceDebugRow(event)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isDarkMode ? 0.1 : 0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func liveVoiceDebugBadge(title: String, value: String, isHighlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.45))

            Text(value)
                .font(.system(size: max(10, themeBaseFontSize - 4), weight: .medium, design: themeFontDesign))
                .foregroundStyle(
                    isHighlighted
                        ? Color.primary.opacity(0.88)
                        : Color.primary.opacity(0.68)
                )
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isHighlighted
                        ? Color.orange.opacity(isDarkMode ? 0.16 : 0.12)
                        : Color.primary.opacity(isDarkMode ? 0.07 : 0.05)
                )
        )
    }

    private func liveVoiceDebugRow(_ event: LiveVoiceDebugEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedDebugTimestamp(event.occurredAt))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.42))

                Text(event.category.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        event.isHighlighted
                            ? Color.orange.opacity(0.95)
                            : Color.primary.opacity(0.52)
                    )

                Text(event.title)
                    .font(themedFont(size: max(10, themeBaseFontSize - 4), weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .lineLimit(1)

                if event.repeatCount > 1 {
                    Text("×\(event.repeatCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.95))
                }

                Spacer(minLength: 0)
            }

            Text(event.detail)
                .font(themedFont(size: max(9, themeBaseFontSize - 5)))
                .foregroundStyle(Color.primary.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func transcriptLineView(_ line: LiveTranscriptLine) -> some View {
        Text(line.text)
            .font(themedFont(size: themeBaseFontSize - 2))
            .foregroundStyle(Color.primary.opacity(0.8))
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 500, alignment: .trailing)
    }

    @ViewBuilder
    private func resultEntryView(entry: OverlayProcessEntry, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if settings.theme.showAvatars {
                avatarBadge("H")
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.prompt.isEmpty ? "Captured context" : entry.prompt)
                    .font(themedFont(size: themeBaseFontSize - 2, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                if !entry.captures.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(entry.captures.enumerated()), id: \.element.id) { _, capture in
                                overlayCaptureThumbnail(capture, width: 72, height: 44)
                            }
                        }
                    }
                }

                if let response = entry.response, !response.isEmpty {
                    Text(response)
                        .font(themedFont(size: themeBaseFontSize - 2))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let errorMessage = entry.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(themedFont(size: themeBaseFontSize - 2))
                        .foregroundStyle(.red.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: messageCornerRadius)
                    .fill(Color.primary.opacity(messageFillOpacity))
            )
        }
        .frame(maxWidth: 500, alignment: .leading)
        .id(entry.id)
    }

    @ViewBuilder
    private func avatarBadge(_ text: String) -> some View {
        Text(text)
            .font(themedFont(size: max(9, themeBaseFontSize - 4), weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.7))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.primary.opacity(0.14)))
    }

    private func openAssistantInMainWindow() {
        performOnMainActor {
            appModel.showMainWindow(.assistant)
        }
    }

    @ViewBuilder
    private func overlayCaptureThumbnail(
        _ capture: OverlayCapture,
        width: CGFloat,
        height: CGFloat,
        isSelected: Bool = false
    ) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(capture.usesImageFill ? 0.02 : 0.08))
            .frame(width: width, height: height)
            .overlay {
                if capture.usesImageFill {
                    Image(nsImage: capture.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 4) {
                        Image(nsImage: capture.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(22, width - 18), height: min(22, height - 18))
                        Text(capture.subtitle)
                            .font(.system(size: 7, weight: .medium, design: themeFontDesign))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? highlightColor : Color.clear, lineWidth: 2)
            }
    }

    private func captureShortcutHintRow(for action: GlobalShortcutAction) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcutTokens(for: action).enumerated()), id: \.offset) { _, token in
                Text(token)
                    .font(.system(size: 8, weight: .medium, design: themeFontDesign))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.15)))
            }
        }
    }

    private func shortcutTokens(for action: GlobalShortcutAction) -> [String] {
        let shortcut = GlobalShortcut.fromDefaults(action.defaultsKey, fallback: action.defaultShortcut)
        return shortcut.displayTokens
    }
}

struct ActionButton: View {
    @EnvironmentObject private var workspace: AssistantWorkspace
    let shortcutTokens: [String]
    let name: String
    let isSelected: Bool
    let isHovered: Bool
    let selectedFill: AnyShapeStyle
    let shortcutFill: AnyShapeStyle
    let fontDesign: Font.Design
    let textSize: CGFloat
    let control: AssistantControlFeedback
    let showsProgress: Bool
    let action: @MainActor () -> Void

    private var isPulseActive: Bool {
        workspace.activePulsedControl == control
    }

    var body: some View {
        Button(action: {
            Task { @MainActor in
                action()
            }
        }) {
            HStack(spacing: 0) {
                Group {
                    if showsProgress {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(minWidth: 32, minHeight: 20, alignment: .leading)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(shortcutTokens.enumerated()), id: \.offset) { _, token in
                                Text(token)
                                    .font(.system(size: max(9, textSize - 2), weight: .medium, design: fontDesign))
                                    .foregroundStyle(Color.primary.opacity(0.7))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(shortcutFill))
                            }
                        }
                    }
                }
                Spacer()
                    .frame(width: 8)
                Text(name.uppercased())
                    .font(.system(size: textSize, weight: .semibold, design: fontDesign))
                    .foregroundStyle(Color.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                        ? selectedFill
                        : AnyShapeStyle((isHovered || isPulseActive) ? Color.primary.opacity(0.1) : Color.clear)
                    )
            )
        }
        .buttonStyle(OverlayTactileButtonStyle())
        .hoverCursor(.pointingHand)
    }
}

private struct OverlayTactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
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

private struct GlassBackground: NSViewRepresentable {
    let materialStyle: String

    func makeNSView(context: Context) -> OverlayMaterialBackgroundView {
        let view = OverlayMaterialBackgroundView()
        view.update(materialStyle: materialStyle)
        return view
    }

    func updateNSView(_ nsView: OverlayMaterialBackgroundView, context: Context) {
        nsView.update(materialStyle: materialStyle)
    }
}

private final class OverlayMaterialBackgroundView: NSView {
    private var materialStyle = ""
    private var backgroundView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(materialStyle: String) {
        if self.materialStyle == materialStyle, let backgroundView {
            update(backgroundView: backgroundView, materialStyle: materialStyle)
            return
        }

        backgroundView?.removeFromSuperview()

        let view = makeBackgroundView(for: materialStyle)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)

        self.materialStyle = materialStyle
        backgroundView = view
    }

    private func makeBackgroundView(for materialStyle: String) -> NSView {
        switch InterfaceMaterialStyle.resolved(rawValue: materialStyle) {
        case .solid:
            return OverlaySolidBackgroundView()
        case .medium:
            let view = NSVisualEffectView()
            update(backgroundView: view, materialStyle: materialStyle)
            return view
        case .liquid:
            if #available(macOS 26.0, *) {
                let view = NSGlassEffectView()
                view.style = .regular
                return view
            }

            let view = NSVisualEffectView()
            update(backgroundView: view, materialStyle: InterfaceMaterialStyle.medium.rawValue)
            return view
        }
    }

    private func update(backgroundView: NSView, materialStyle: String) {
        let resolvedStyle = InterfaceMaterialStyle.resolved(rawValue: materialStyle)

        if let solidBackgroundView = backgroundView as? OverlaySolidBackgroundView {
            solidBackgroundView.updateAppearance()
            return
        }

        if #available(macOS 26.0, *), let glassEffectView = backgroundView as? NSGlassEffectView {
            glassEffectView.style = .regular
            return
        }

        guard let visualEffectView = backgroundView as? NSVisualEffectView else { return }
        visualEffectView.material = material(for: resolvedStyle)
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.isEmphasized = false
    }

    private func material(for style: InterfaceMaterialStyle) -> NSVisualEffectView.Material {
        switch style {
        case .solid:
            return .windowBackground
        case .medium, .liquid:
            return .hudWindow
        }
    }
}

private final class OverlaySolidBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

#Preview {
    OverlayView()
        .environment(AppModel.shared)
        .environmentObject(AssistantWorkspace.shared)
}
