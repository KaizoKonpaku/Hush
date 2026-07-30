import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum AssistantControlFeedback: String {
    case newSession
    case settings
    case appWindow
    case live
    case text
    case capture
    case process
}

@MainActor
final class AssistantWorkspace: ObservableObject {
    static let shared = AssistantWorkspace()

    @Published var textInput = ""
    @Published var capturePhotos: [OverlayCapture] = []
    @Published var focusedCaptureIndex: Int?
    @Published var showTranscript = false
    @Published var showText = false
    @Published var showCapture = false
    @Published var isProcessing = false
    @Published var processEntries: [OverlayProcessEntry] = []
    @Published var selectedProcessEntryID: UUID?
    @Published var autoScrollResults = false
    @Published var resultScrollCommand: OverlayResultScrollCommand?
    @Published var overlayNotification: OverlayNotificationState?
    @Published private(set) var activePulsedControl: AssistantControlFeedback?

    let liveTranscriptionService = LiveTranscriptionService()
    private let defaults = UserDefaults.standard
    private let intelligenceRuntime = IntelligenceRuntime.shared
    private let openAIService = OpenAIService.shared
    private let appNotificationManager = AppNotificationManager.shared
    private let sessionStore = SessionHistoryStore.shared

    private var notificationDismissWorkItem: DispatchWorkItem?
    private var lastLiveServiceStatusMessage: String?
    private var activeOpenAIConversationID: String?
    private var controlPulseGeneration: UInt64 = 0
    private var processingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        bindLiveTranscriptionCallbacks()
        observeLiveTranscriptionStatus()
        applyDefaultMode(resetExisting: true)
        restoreCurrentSessionState()
    }

    func startNewSession() {
        resetWorkspaceState()
        sessionStore.startNewSession()
    }

    func startNewSessionWithFeedback() {
        pulseControl(.newSession)
        startNewSession()
    }

    func openSession(_ session: SessionRecord, isCurrentSession: Bool) {
        resetWorkspaceState()

        if isCurrentSession {
            sessionStore.selectCurrentSession()
        } else {
            sessionStore.selectSession(id: session.id)
        }

        restoreDisplayedSessionState()
    }

    func pulseSettingsControl() {
        pulseControl(.settings)
    }

    func applyDefaultMode(resetExisting: Bool = false) {
        if resetExisting {
            showTranscript = false
            showText = false
            showCapture = false
            liveTranscriptionService.stop()
        } else if showTranscript || showText || showCapture {
            return
        }

        switch string(forKey: "behaviours.defaultMode", default: "none") {
        case "live":
            showTranscript = true
        case "text":
            showText = true
        case "capture":
            showCapture = true
        case "none":
            break
        default:
            break
        }

        updateLiveTranscriptionState(whenTranscriptVisible: showTranscript)
    }

    func toggleTranscript() {
        showTranscript.toggle()
        updateLiveTranscriptionState(whenTranscriptVisible: showTranscript)
    }

    func toggleTranscriptWithFeedback() {
        pulseControl(.live)
        toggleTranscript()
    }

    func toggleText() {
        showText.toggle()
    }

    func toggleTextWithFeedback() {
        pulseControl(.text)
        toggleText()
    }

    func cycleLiveAudioSource() {
        let modeLabel: String

        switch resolvedLiveInputMode() {
        case .both:
            defaults.set("mic", forKey: "behaviours.live.audioSource")
            modeLabel = "Mic"
        case .mic:
            defaults.set("system", forKey: "behaviours.live.audioSource")
            modeLabel = "System"
        case .system:
            defaults.set("both", forKey: "behaviours.live.audioSource")
            modeLabel = "Both"
        }

        presentNotification(
            kind: .info,
            title: "Live Source Updated",
            message: "Now using \(modeLabel).",
            accent: liveModeAccentColor
        )

        restartLiveTranscriptionIfActive()
    }

    func cycleLiveAudioSourceWithFeedback() {
        pulseControl(.live)
        cycleLiveAudioSource()
    }

    func liveAudioSourceDidChange() {
        restartLiveTranscriptionIfActive()
    }

    func liveLanguageDidChange() {
        restartLiveTranscriptionIfActive()
    }

    func liveAutoListenDidChange() {
        if showTranscript {
            if bool(forKey: "behaviours.live.autoListen", default: true) {
                startLiveTranscription()
            } else {
                liveTranscriptionService.stop()
            }
        }
    }

    func handleCaptureAction(mode: CaptureMode = .selection) {
        let added = appendCapturePhoto(mode: mode)
        if added {
            showCapture = true
        } else if capturePhotos.isEmpty {
            showCapture = false
        }
    }

    func handleCaptureActionWithFeedback(mode: CaptureMode = .selection) {
        pulseControl(.capture)
        handleCaptureAction(mode: mode)
    }

    func handleQuickCaptureAction() {
        handleCaptureAction(mode: resolvedQuickCaptureMode())
    }

    func handleQuickCaptureActionWithFeedback() {
        pulseControl(.capture)
        handleQuickCaptureAction()
    }

    func addPhotoAttachments() {
        addAttachments(
            allowedContentTypes: [.image],
            source: .photo,
            title: "Add Photos"
        )
    }

    func addFileAttachments() {
        addAttachments(
            allowedContentTypes: nil,
            source: .file,
            title: "Add Files"
        )
    }

    func deleteFocusedCapture() {
        guard !capturePhotos.isEmpty else { return }

        let indexToDelete = focusedCaptureIndex ?? (capturePhotos.count - 1)
        guard capturePhotos.indices.contains(indexToDelete) else { return }
        capturePhotos.remove(at: indexToDelete)

        if capturePhotos.isEmpty {
            showCapture = false
            focusedCaptureIndex = nil
        } else {
            focusedCaptureIndex = min(indexToDelete, capturePhotos.count - 1)
        }
    }

    func focusPreviousCapture() {
        guard !capturePhotos.isEmpty else { return }
        if let focusedCaptureIndex {
            self.focusedCaptureIndex = max(0, focusedCaptureIndex - 1)
        } else {
            focusedCaptureIndex = capturePhotos.count - 1
        }
    }

    func focusNextCapture() {
        guard !capturePhotos.isEmpty else { return }
        if let focusedCaptureIndex {
            self.focusedCaptureIndex = min(capturePhotos.count - 1, focusedCaptureIndex + 1)
        } else {
            focusedCaptureIndex = 0
        }
    }

    func toggleAutoScrollResults() {
        autoScrollResults.toggle()
        if autoScrollResults {
            scrollResults(to: .bottom)
        }
    }

    func scrollResults(to command: OverlayResultScrollCommand) {
        resultScrollCommand = nil
        DispatchQueue.main.async { [weak self] in
            self?.resultScrollCommand = command
        }
    }

    func selectProcessEntry(_ entryID: UUID, shouldScroll: Bool = false) {
        if selectedProcessEntryID != entryID {
            selectedProcessEntryID = entryID
        }

        guard shouldScroll else { return }
        scrollResults(to: .entry(entryID))
    }

    func branchConversation(from entryID: UUID) {
        guard let branch = branchContext(for: entryID, includeSelectedInteraction: true) else {
            return
        }

        startSeededSession(branch.seedSession)
        presentNotification(
            kind: .info,
            title: "Conversation Branched",
            message: "Started a new session from this point in the conversation."
        )
    }

    func regenerateResponse(from entryID: UUID) {
        guard let entry = processEntries.first(where: { $0.id == entryID }) else { return }
        guard !entry.normalizedPrompt.isEmpty || !entry.captures.isEmpty else {
            presentNotification(
                kind: .error,
                title: "Nothing to Regenerate",
                message: "This turn does not have reusable prompt or attachment content."
            )
            return
        }
        guard let branch = branchContext(for: entryID, includeSelectedInteraction: false) else {
            return
        }

        startSeededSession(branch.seedSession)
        restoreResendInput(from: entry)
        runProcess()
    }

    func resendEditedPrompt(from entryID: UUID, prompt: String) {
        guard let entry = processEntries.first(where: { $0.id == entryID }) else { return }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !entry.captures.isEmpty else {
            presentNotification(
                kind: .error,
                title: "Prompt Required",
                message: "Enter a prompt before resending this request."
            )
            return
        }
        guard let branch = branchContext(for: entryID, includeSelectedInteraction: false) else {
            return
        }

        startSeededSession(branch.seedSession)
        restoreResendInput(from: entry, promptOverride: prompt)
        runProcess()
    }

    func loadPromptIntoComposer(from entryID: UUID) {
        guard let entry = processEntries.first(where: { $0.id == entryID }) else { return }

        textInput = entry.prompt
        showText = true
        selectedProcessEntryID = entry.id
        capturePhotos = entry.captures
        focusedCaptureIndex = capturePhotos.indices.last
        showCapture = !capturePhotos.isEmpty

        if entry.hasStoredAttachmentSummary {
            presentNotification(
                kind: .info,
                title: "Attachments Not Restored",
                message: "HUSH keeps counts for past attachments, but only currently loaded files can be resent."
            )
        }
    }

    func runProcess() {
        let trimmedPrompt = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInput = !trimmedPrompt.isEmpty || !capturePhotos.isEmpty
        guard hasInput else {
            presentError(.missingInput)
            return
        }
        guard !isProcessing else {
            presentError(.alreadyProcessing)
            return
        }

        if capturePhotos.isEmpty,
           showTranscript,
           liveTranscriptionService.isListening,
           liveTranscriptionService.submitRealtimeChatTurn(trimmedPrompt) {
            dismissNotification()
            textInput = ""
            showText = true
            return
        }

        guard hasResolvedModelSelection else {
            presentNotification(
                kind: .error,
                title: "Choose a Model",
                message: "Validate a provider in Accounts and choose a model first."
            )
            return
        }

        dismissNotification()

        let shouldResumeLiveAfterProcess = showTranscript && liveTranscriptionService.isListening
        if shouldResumeLiveAfterProcess {
            liveTranscriptionService.stop()
        }

        let processStartedAt = Date()
        let pendingEntry = OverlayProcessEntry(
            prompt: trimmedPrompt,
            captures: capturePhotos,
            captureCount: capturePhotos.count,
            createdAt: processStartedAt,
            response: nil,
            isProcessing: true
        )

        processEntries.append(pendingEntry)
        selectedProcessEntryID = pendingEntry.id
        textInput = ""
        capturePhotos = []
        focusedCaptureIndex = nil
        showCapture = false
        isProcessing = true

        if autoScrollResults {
            scrollResults(to: .bottom)
        }

        let currentEntryID = pendingEntry.id
        let conversationHandle = makeConversationHandle()
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.streamProcess(
                entryID: currentEntryID,
                startedAt: processStartedAt,
                conversationHandle: conversationHandle,
                resumeLiveAfterCompletion: shouldResumeLiveAfterProcess
            )
        }
    }

    func runProcessWithFeedback() {
        pulseControl(.process)
        runProcess()
    }

    func dismissNotification() {
        notificationDismissWorkItem?.cancel()
        notificationDismissWorkItem = nil
        overlayNotification = nil
    }

    func resolvedLiveInputMode() -> LiveAudioInputMode {
        LiveAudioInputMode(rawValue: string(forKey: "behaviours.live.audioSource", default: "both")) ?? .both
    }

    func resolvedLiveLocaleIdentifier() -> String {
        switch string(forKey: "behaviours.live.language", default: "system") {
        case "system":
            return Locale.current.identifier(.bcp47)
        case "en":
            return "en-US"
        case "ja":
            return "ja-JP"
        default:
            return string(forKey: "behaviours.live.language", default: "system")
        }
    }

    var hasPendingProcessInput: Bool {
        !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !capturePhotos.isEmpty
    }

    var hasResolvedModelSelection: Bool {
        let selectedMode = AssistantModelMode(
            rawValue: string(forKey: "assistant.selectedModelMode", default: AssistantModelMode.defaultMode.rawValue)
        ) ?? .defaultMode
        let storedSelection = AssistantModelCatalog.storedModelValue(for: selectedMode, defaults: defaults)
        let availableOptions = ProviderAccountStore.shared.availableModels
        return AssistantModelCatalog.hasAvailableOption(for: storedSelection, availableOptions: availableOptions)
    }

    var canSubmitProcess: Bool {
        hasPendingProcessInput && hasResolvedModelSelection && !isProcessing
    }

    func resolvedQuickCaptureMode() -> CaptureMode {
        CaptureMode(rawValue: string(forKey: "behaviours.capture.quickMode", default: "selection")) ?? .selection
    }

    var liveModeAccentColor: Color {
        switch resolvedLiveInputMode() {
        case .both:
            return .red
        case .mic:
            return .orange
        case .system:
            return Color(red: 0.56, green: 0.33, blue: 0.92)
        }
    }

    private func observeLiveTranscriptionStatus() {
        liveTranscriptionService.$statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.handleLiveTranscriptionStatus(status)
                }
            }
            .store(in: &cancellables)
    }

    private func bindLiveTranscriptionCallbacks() {
        liveTranscriptionService.onCompletedTurn = { [weak self] turn in
            Task { @MainActor [weak self] in
                self?.handleCompletedLiveTurn(turn)
            }
        }
    }

    private func updateLiveTranscriptionState(whenTranscriptVisible isVisible: Bool) {
        guard isVisible else {
            liveTranscriptionService.stop()
            return
        }

        if bool(forKey: "behaviours.live.autoListen", default: true) {
            startLiveTranscription()
        }
    }

    private func restartLiveTranscriptionIfActive() {
        guard showTranscript, liveTranscriptionService.isListening else { return }
        startLiveTranscription()
    }

    private func startLiveTranscription() {
        liveTranscriptionService.start(
            mode: resolvedLiveInputMode(),
            localeIdentifier: resolvedLiveLocaleIdentifier(),
            seedItems: makeRealtimeSeedItems(from: sessionStore.displayedSession)
        )
    }

    private func pulseControl(_ control: AssistantControlFeedback) {
        controlPulseGeneration &+= 1
        let generation = controlPulseGeneration
        activePulsedControl = control

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, self.controlPulseGeneration == generation else { return }
            self.activePulsedControl = nil
        }
    }

    private func appendCapturePhoto(mode: CaptureMode = .selection) -> Bool {
        guard capturePhotos.count < 6 else {
            presentError(.captureLimitReached)
            return false
        }
        guard screenCapturePermissionGranted() else {
            presentError(.screenCapturePermissionDenied)
            return false
        }

        switch captureImage(mode: mode, includeCursor: bool(forKey: "behaviours.capture.includeCursor", default: true)) {
        case let .image(image):
            capturePhotos.append(
                OverlayCapture(
                    image: image,
                    title: captureTitle(for: mode),
                    subtitle: "Capture",
                    source: .screenshot
                )
            )
            focusedCaptureIndex = capturePhotos.indices.last
            dismissNotification()
            sessionStore.recordCaptureAdded()
            return true
        case .cancelled:
            return false
        case .failed:
            presentError(.captureFailed)
            return false
        }
    }

    private func addAttachments(
        allowedContentTypes: [UTType]?,
        source: OverlayCaptureSource,
        title: String
    ) {
        let remainingSlots = max(0, 6 - capturePhotos.count)
        guard remainingSlots > 0 else {
            presentError(.captureLimitReached)
            return
        }

        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = remainingSlots > 1

        if let allowedContentTypes {
            panel.allowedContentTypes = allowedContentTypes
        }

        guard panel.runModal() == .OK else { return }

        let selectedURLs = Array(panel.urls.prefix(remainingSlots))
        let importedCount = importAttachments(from: selectedURLs, source: source)

        guard importedCount > 0 else {
            presentError(.attachmentImportFailed)
            return
        }

        showCapture = true
        dismissNotification()
        focusedCaptureIndex = capturePhotos.indices.last
        sessionStore.recordCaptureAdded(count: importedCount)

        if panel.urls.count > selectedURLs.count {
            presentNotification(
                kind: .info,
                title: "Attachment Limit Reached",
                message: "Only the first \(remainingSlots) items were added."
            )
        }
    }

    private func importAttachments(from urls: [URL], source: OverlayCaptureSource) -> Int {
        var addedCount = 0

        for url in urls {
            guard let attachment = attachment(for: url, source: source) else { continue }
            capturePhotos.append(attachment)
            addedCount += 1
        }

        return addedCount
    }

    private func attachment(for url: URL, source: OverlayCaptureSource) -> OverlayCapture? {
        switch source {
        case .photo:
            guard let image = NSImage(contentsOf: url) else { return nil }
            return OverlayCapture(
                image: image,
                title: url.lastPathComponent,
                subtitle: "Photo",
                source: .photo,
                fileURL: url
            )
        case .file:
            return OverlayCapture(
                image: NSWorkspace.shared.icon(forFile: url.path),
                title: url.lastPathComponent,
                subtitle: attachmentSubtitle(for: url),
                source: .file,
                fileURL: url
            )
        case .screenshot:
            return nil
        }
    }

    private func captureTitle(for mode: CaptureMode) -> String {
        switch mode {
        case .full:
            return "Full Screen"
        case .selection:
            return "Selection"
        case .window:
            return "Window"
        }
    }

    private func attachmentSubtitle(for url: URL) -> String {
        guard !url.pathExtension.isEmpty else {
            return "File"
        }

        return "\(url.pathExtension.uppercased()) File"
    }

    private func streamProcess(
        entryID: UUID,
        startedAt: Date,
        conversationHandle: IntelligenceConversationHandle,
        resumeLiveAfterCompletion: Bool
    ) async {
        defer {
            isProcessing = false
            processingTask = nil
            if autoScrollResults {
                scrollResults(to: .bottom)
            }
            if resumeLiveAfterCompletion, showTranscript, !Task.isCancelled {
                startLiveTranscription()
            }
        }

        guard let index = processEntries.firstIndex(where: { $0.id == entryID }) else { return }
        var streamedResponse = ""
        processEntries[index].response = ""
        processEntries[index].errorMessage = nil

        do {
            let selectedMode = AssistantModelMode(
                rawValue: string(forKey: "assistant.selectedModelMode", default: AssistantModelMode.defaultMode.rawValue)
            ) ?? .defaultMode

            var resolvedConversationHandle = conversationHandle
            if resolvedConversationHandle.conversationID == nil,
               let accountContext = await openAIAccountContext() {
                let (account, secrets) = accountContext
                let conversationID = try await openAIService.ensureConversationID(
                    existingConversationID: nil,
                    seedItems: resolvedConversationHandle.seedItems,
                    record: account,
                    secrets: secrets
                )
                activeOpenAIConversationID = conversationID
                sessionStore.setRemoteConversationID(conversationID)
                resolvedConversationHandle = IntelligenceConversationHandle(
                    conversationID: conversationID,
                    seedItems: resolvedConversationHandle.seedItems,
                    existingAssets: resolvedConversationHandle.existingAssets
                )
            }

            let stream = try await intelligenceRuntime.responseStream(
                prompt: processEntries[index].prompt,
                captures: processEntries[index].captures,
                modelMode: selectedMode,
                conversationHandle: resolvedConversationHandle
            )

            for try await event in stream.stream {
                guard !Task.isCancelled else { return }
                streamedResponse += event
                processEntries[index].response = streamedResponse

                if autoScrollResults {
                    scrollResults(to: .bottom)
                }
            }

            processEntries[index].isProcessing = false
            processEntries[index].errorMessage = nil
            activeOpenAIConversationID = normalizedConversationID(stream.conversationID)
            let latestResponseID = normalizedResponseID(stream.responseID)
            processEntries[index].openAIResponseID = latestResponseID

            sessionStore.recordTypedTurn(
                interactionID: processEntries[index].id,
                prompt: processEntries[index].prompt,
                response: streamedResponse,
                assets: stream.assets,
                captureCountOverride: processEntries[index].captureCount,
                startedAt: startedAt,
                finishedAt: Date(),
                openAIConversationID: activeOpenAIConversationID,
                openAIResponseID: latestResponseID,
                assistantRemoteItemID: stream.assistantItemID
            )

            appNotificationManager.postBackgroundCompletion(
                title: "Response Ready",
                message: streamedResponse.isEmpty
                    ? "Your latest request finished processing."
                    : streamedResponse
            )
        } catch {
            processEntries[index].isProcessing = false
            processEntries[index].response = nil
            processEntries[index].errorMessage = error.localizedDescription
            presentNotification(
                kind: .error,
                title: "Model Request Failed",
                message: error.localizedDescription
            )
            sessionStore.recordError(title: "Model Request Failed", message: error.localizedDescription)
        }
    }

    private func handleCompletedLiveTurn(_ turn: LiveCompletedTurn) {
        let normalizedPrompt = turn.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedResponse = turn.response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPrompt.isEmpty, !normalizedResponse.isEmpty else {
            return
        }

        let completedEntry = OverlayProcessEntry(
            prompt: normalizedPrompt,
            captures: [],
            captureCount: 0,
            createdAt: turn.startedAt,
            response: normalizedResponse,
            isProcessing: false,
            openAIResponseID: normalizedResponseID(turn.assistantResponseID)
        )

        processEntries.append(completedEntry)
        selectedProcessEntryID = completedEntry.id

        if autoScrollResults {
            scrollResults(to: .bottom)
        }

        let sessionSnapshot = sessionStore.displayedSession
        let existingConversationID = normalizedConversationID(
            activeOpenAIConversationID ?? sessionSnapshot.openAIConversationID
        )
        let seedItems = existingConversationID == nil
            ? makeConversationSeedItems(from: sessionSnapshot)
            : []

        Task { [weak self] in
            guard let self else { return }

            var resolvedConversationID = existingConversationID

            do {
                if let accountContext = await self.openAIAccountContext() {
                    let (account, secrets) = accountContext

                    if resolvedConversationID == nil {
                        resolvedConversationID = try await self.openAIService.ensureConversationID(
                            existingConversationID: nil,
                            seedItems: seedItems,
                            record: account,
                            secrets: secrets
                        )
                    }

                    if let resolvedConversationID {
                        _ = try await self.openAIService.appendConversationItems(
                            conversationID: resolvedConversationID,
                            items: [
                                OpenAIConversationSeedItem(
                                    role: .user,
                                    contents: [.inputText(normalizedPrompt)],
                                    metadata: [
                                        "source": "hush_live_transcript",
                                        "realtime_session_id": turn.realtimeSessionID ?? "",
                                    ]
                                ),
                                OpenAIConversationSeedItem(
                                    role: .assistant,
                                    contents: [.outputText(normalizedResponse)],
                                    metadata: [
                                        "source": "hush_live_transcript",
                                        "realtime_session_id": turn.realtimeSessionID ?? "",
                                    ]
                                ),
                            ],
                            record: account,
                            secrets: secrets
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.presentNotification(
                        kind: .error,
                        title: "Live Sync Delayed",
                        message: "HUSH saved the transcript locally, but syncing it to the shared OpenAI conversation failed: \(error.localizedDescription)"
                    )
                    self.sessionStore.recordError(
                        title: "Live Sync Delayed",
                        message: error.localizedDescription
                    )
                }
            }

            await MainActor.run {
                self.activeOpenAIConversationID = resolvedConversationID
                self.sessionStore.recordLiveTurn(
                    interactionID: completedEntry.id,
                    prompt: normalizedPrompt,
                    response: normalizedResponse,
                    startedAt: turn.startedAt,
                    finishedAt: turn.finishedAt,
                    openAIConversationID: resolvedConversationID,
                    realtimeSessionID: turn.realtimeSessionID,
                    assistantResponseID: turn.assistantResponseID,
                    userRemoteItemID: turn.userItemID,
                    assistantRemoteItemID: turn.assistantItemID,
                    wasInterrupted: turn.wasInterrupted,
                    wasTruncated: turn.wasTruncated
                )
            }
        }
    }

    private func handleLiveTranscriptionStatus(_ status: String?) {
        guard let status, !status.isEmpty else {
            lastLiveServiceStatusMessage = nil
            return
        }
        guard status != lastLiveServiceStatusMessage else { return }
        lastLiveServiceStatusMessage = status

        presentNotification(
            kind: .error,
            title: "Live Transcription",
            message: status,
            accent: liveModeAccentColor
        )
    }

    private func presentError(_ error: OverlayRuntimeError) {
        let descriptor = error.descriptor
        presentNotification(
            kind: .error,
            title: descriptor.title,
            message: descriptor.message
        )
        sessionStore.recordError(title: descriptor.title, message: descriptor.message)
    }

    private func presentNotification(
        kind: OverlayNotificationKind,
        title: String,
        message: String,
        accent: Color? = nil
    ) {
        if kind == .error {
            appNotificationManager.postError(title: title, message: message)
        }

        guard shouldShowInAppNotification(for: kind) else { return }

        notificationDismissWorkItem?.cancel()
        overlayNotification = OverlayNotificationState(
            kind: kind,
            title: title,
            message: message,
            accent: accent
        )

        guard shouldAutoDismiss(kind: kind) else { return }
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.overlayNotification = nil
            }
        }
        notificationDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + inAppNotificationDuration, execute: workItem)
    }

    private func shouldShowInAppNotification(for kind: OverlayNotificationKind) -> Bool {
        guard bool(forKey: "notif.inAppEnabled", default: true) else { return false }

        switch kind {
        case .error:
            return bool(forKey: "notif.errors", default: true)
        case .info:
            return bool(forKey: "notif.inAppShowInfo", default: true)
        case .success:
            return true
        }
    }

    private func shouldAutoDismiss(kind: OverlayNotificationKind) -> Bool {
        bool(forKey: "notif.inAppAutoDismiss", default: true)
    }

    private var inAppNotificationDuration: TimeInterval {
        switch string(forKey: "notif.inAppDuration", default: "normal") {
        case "short":
            return 1.8
        case "long":
            return 4.0
        default:
            return 2.7
        }
    }

    private func screenCapturePermissionGranted() -> Bool {
        AppPermissionAccess.requestScreenCaptureAccess()
    }

    private func restoreCurrentSessionState() {
        sessionStore.selectCurrentSession()
        restoreDisplayedSessionState()
    }

    private func restoreDisplayedSessionState() {
        let session = sessionStore.displayedSession
        guard !session.interactions.isEmpty else {
            processEntries = []
            selectedProcessEntryID = nil
            activeOpenAIConversationID = normalizedConversationID(session.openAIConversationID)
            return
        }

        processEntries = session.interactions.map {
            OverlayProcessEntry(
                id: $0.id,
                prompt: $0.prompt,
                captures: restoredCaptures(for: $0.id, in: session),
                captureCount: $0.captureCount,
                createdAt: $0.startedAt,
                response: $0.response,
                isProcessing: false,
                openAIResponseID: $0.openAIResponseID
            )
        }
        selectedProcessEntryID = processEntries.last?.id
        activeOpenAIConversationID = normalizedConversationID(session.openAIConversationID)
    }

    private func resetWorkspaceState() {
        processingTask?.cancel()
        processingTask = nil
        liveTranscriptionService.stop()
        liveTranscriptionService.clearTranscript()
        dismissNotification()

        showTranscript = false
        showText = false
        showCapture = false
        isProcessing = false
        processEntries = []
        selectedProcessEntryID = nil
        autoScrollResults = false
        resultScrollCommand = nil
        textInput = ""
        capturePhotos = []
        focusedCaptureIndex = nil
        lastLiveServiceStatusMessage = nil
        activeOpenAIConversationID = nil
    }

    private func branchContext(
        for entryID: UUID,
        includeSelectedInteraction: Bool
    ) -> AssistantBranchContext? {
        let displayedSession = sessionStore.displayedSession
        guard let seedInteractions = displayedSession.interactions(
            upTo: entryID,
            includeSelectedInteraction: includeSelectedInteraction
        ) else {
            presentNotification(
                kind: .error,
                title: "Unable to Branch",
                message: "HUSH could not find that point in the session history."
            )
            return nil
        }

        return AssistantBranchContext(
            seedSession: displayedSession.seedCopy(with: seedInteractions)
        )
    }

    private func startSeededSession(_ seedSession: SessionRecord) {
        resetWorkspaceState()
        sessionStore.startNewSession(seedSession: seedSession)
        restoreCurrentSessionState()
        activeOpenAIConversationID = normalizedConversationID(seedSession.openAIConversationID)
        showText = true
    }

    private func restoreResendInput(from entry: OverlayProcessEntry, promptOverride: String? = nil) {
        textInput = promptOverride ?? entry.prompt
        capturePhotos = entry.captures
        focusedCaptureIndex = capturePhotos.indices.last
        showText = true
        showCapture = !capturePhotos.isEmpty

        if entry.hasStoredAttachmentSummary {
            presentNotification(
                kind: .info,
                title: "Some Attachments Weren't Restored",
                message: "HUSH resent the prompt with any files still loaded locally. Past attachment files are not stored with session history."
            )
        }
    }

    private func normalizedResponseID(_ responseID: String?) -> String? {
        guard let responseID else { return nil }
        let trimmed = responseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedConversationID(_ conversationID: String?) -> String? {
        guard let conversationID else { return nil }
        let trimmed = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeConversationHandle() -> IntelligenceConversationHandle {
        let session = sessionStore.displayedSession
        let conversationID = normalizedConversationID(activeOpenAIConversationID ?? session.openAIConversationID)
        let seedItems = conversationID == nil ? makeConversationSeedItems(from: session) : []
        return IntelligenceConversationHandle(
            conversationID: conversationID,
            seedItems: seedItems,
            existingAssets: session.assets
        )
    }

    private func makeConversationSeedItems(from session: SessionRecord) -> [OpenAIConversationSeedItem] {
        makeConversationSeedItems(from: session.items, in: session, preferRealtimeCompatibleFiles: false)
    }

    private func makeRealtimeSeedItems(from session: SessionRecord) -> [OpenAIConversationSeedItem] {
        let eligibleItems = session.items
            .filter { $0.role != .system && $0.status != .failed && !$0.parts.isEmpty }

        guard !eligibleItems.isEmpty else { return [] }

        let maxItemCount = 20
        let maxEstimatedCharacters = 96_000
        var selectedItems: [ConversationItemRecord] = []
        var accumulatedCharacters = 0

        for item in eligibleItems.reversed() {
            let estimatedCharacters = estimatedSeedCharacters(for: item, in: session)
            if selectedItems.count >= maxItemCount || accumulatedCharacters + estimatedCharacters > maxEstimatedCharacters {
                break
            }

            selectedItems.append(item)
            accumulatedCharacters += estimatedCharacters
        }

        selectedItems.reverse()
        let selectedIDs = Set(selectedItems.map(\.id))
        let olderItems = eligibleItems.filter { !selectedIDs.contains($0.id) }

        var seedItems: [OpenAIConversationSeedItem] = []
        if let summaryItem = makeRealtimeSummaryItem(from: olderItems, in: session) {
            seedItems.append(summaryItem)
        }

        seedItems.append(
            contentsOf: makeConversationSeedItems(
                from: selectedItems,
                in: session,
                preferRealtimeCompatibleFiles: true
            )
        )

        return seedItems
    }

    private func makeConversationSeedItems(
        from items: [ConversationItemRecord],
        in session: SessionRecord,
        preferRealtimeCompatibleFiles: Bool
    ) -> [OpenAIConversationSeedItem] {
        items.compactMap { item in
            let contents = item.parts.compactMap { part in
                seedContent(
                    for: part,
                    role: item.role,
                    session: session,
                    preferRealtimeCompatibleFiles: preferRealtimeCompatibleFiles
                )
            }

            guard !contents.isEmpty else { return nil }

            var metadata = item.metadata
            metadata["origin"] = item.origin.rawValue
            metadata["status"] = item.status.rawValue
            if let realtimeSessionID = item.realtimeSessionID {
                metadata["realtime_session_id"] = realtimeSessionID
            }
            if item.kind == .summary {
                metadata["summary"] = "true"
            }

            return OpenAIConversationSeedItem(
                role: item.role,
                contents: contents,
                metadata: metadata
            )
        }
    }

    private func seedContent(
        for part: ConversationPartRecord,
        role: ConversationItemRole,
        session: SessionRecord,
        preferRealtimeCompatibleFiles: Bool
    ) -> OpenAIConversationSeedContent? {
        switch part.kind {
        case .inputText:
            guard let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return .inputText(text)
        case .outputText:
            guard let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return .outputText(text)
        case .transcriptText:
            guard let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return role == .assistant ? .outputText(text) : .inputText(text)
        case .inputImage:
            guard let assetID = part.assetID, let asset = session.asset(with: assetID) else { return nil }
            return .imageAsset(asset)
        case .inputFile:
            guard let assetID = part.assetID, let asset = session.asset(with: assetID) else { return nil }
            if preferRealtimeCompatibleFiles,
               let digest = asset.extractedTextDigest ?? asset.degradedSummary {
                return .inputText(digest)
            }
            return .fileAsset(asset)
        case .attachmentReference:
            guard let assetID = part.assetID, let asset = session.asset(with: assetID) else { return nil }
            if asset.source == .file {
                if preferRealtimeCompatibleFiles,
                   let digest = asset.extractedTextDigest ?? asset.degradedSummary {
                    return .inputText(digest)
                }
                return .fileAsset(asset)
            }
            return .imageAsset(asset)
        }
    }

    private func makeRealtimeSummaryItem(
        from items: [ConversationItemRecord],
        in session: SessionRecord
    ) -> OpenAIConversationSeedItem? {
        guard !items.isEmpty else { return nil }

        var sections: [String] = []
        for item in items {
            let label = item.role.rawValue.uppercased()
            let text = item.preferredDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sections.append("\(label): \(text)")
            }

            for assetID in item.assetIDs {
                guard let asset = session.asset(with: assetID) else { continue }
                if asset.source == .file,
                   let digest = asset.extractedTextDigest ?? asset.degradedSummary {
                    sections.append("FILE: \(digest)")
                } else {
                    sections.append("IMAGE: \(asset.title)")
                }
            }
        }

        let summary = sections
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summary.isEmpty else { return nil }

        return OpenAIConversationSeedItem(
            role: .system,
            contents: [
                .inputText(
                    "Summary of earlier conversation context before the current live session:\n\(String(summary.prefix(12_000)))"
                )
            ],
            metadata: [
                "source": "hush_realtime_seed_summary",
                "kind": ConversationItemKind.summary.rawValue,
            ]
        )
    }

    private func estimatedSeedCharacters(for item: ConversationItemRecord, in session: SessionRecord) -> Int {
        var total = item.preferredDisplayText.count

        for assetID in item.assetIDs {
            guard let asset = session.asset(with: assetID) else { continue }
            total += asset.title.count
            total += (asset.extractedTextDigest ?? asset.degradedSummary ?? "").count
        }

        return max(1, total)
    }

    private func restoredCaptures(for interactionID: UUID, in session: SessionRecord) -> [OverlayCapture] {
        session.assets(for: interactionID).compactMap(restoredCapture(for:))
    }

    private func restoredCapture(for asset: AttachmentAssetRecord) -> OverlayCapture? {
        switch asset.source {
        case .screenshot, .photo:
            if let fileURL = asset.resolvedLocalURL,
               let image = NSImage(contentsOf: fileURL) {
                return OverlayCapture(
                    image: image,
                    title: asset.title,
                    subtitle: asset.subtitle,
                    source: asset.source,
                    fileURL: fileURL
                )
            }

            if let previewPNGData = asset.previewPNGData,
               let image = NSImage(data: previewPNGData) {
                return OverlayCapture(
                    image: image,
                    title: asset.title,
                    subtitle: asset.subtitle,
                    source: asset.source,
                    fileURL: asset.resolvedLocalURL
                )
            }

            return nil

        case .file:
            let fileURL = asset.resolvedLocalURL
            let icon: NSImage
            if let fileURL {
                icon = NSWorkspace.shared.icon(forFile: fileURL.path)
            } else {
                icon = NSWorkspace.shared.icon(for: .data)
            }

            return OverlayCapture(
                image: icon,
                title: asset.title,
                subtitle: asset.subtitle,
                source: .file,
                fileURL: fileURL
            )
        }
    }

    private func openAIAccountContext() async -> (ProviderAccountRecord, ProviderAccountLocalSecrets)? {
        await MainActor.run { () -> (ProviderAccountRecord, ProviderAccountLocalSecrets)? in
            guard let account = ProviderAccountStore.shared.primaryAccount(for: .openAI) else {
                return nil
            }

            return (account, ProviderAccountStore.shared.secrets(for: account))
        }
    }

    private func captureImage(mode: CaptureMode, includeCursor: Bool) -> CaptureAttemptResult {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush-capture-\(UUID().uuidString).png")

        var args: [String] = []
        if includeCursor {
            args.append("-C")
        }

        switch mode {
        case .full:
            args.append("-x")
        case .selection:
            args.append(contentsOf: ["-i", "-s"])
        case .window:
            args.append(contentsOf: ["-i", "-W"])
        }

        args.append(tempURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = args

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .failed
        }

        guard task.terminationStatus == 0 else {
            return .cancelled
        }

        guard FileManager.default.fileExists(atPath: tempURL.path),
              let image = NSImage(contentsOf: tempURL) else {
            return .failed
        }

        try? FileManager.default.removeItem(at: tempURL)
        return .image(image)
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func string(forKey key: String, default defaultValue: String) -> String {
        defaults.string(forKey: key) ?? defaultValue
    }
}

private struct AssistantBranchContext {
    let seedSession: SessionRecord
}
