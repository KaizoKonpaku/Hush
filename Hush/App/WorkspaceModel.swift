import Foundation
import FoundationModels
import Observation

enum WorkspacePage: String, CaseIterable, Identifiable {
    case chat, discover, library, runtime, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .chat: "Chat"; case .discover: "Discover"; case .library: "My models"; case .runtime: "Runtime"; case .settings: "Settings" }
    }
    var symbol: String {
        switch self { case .chat: "bubble.left.and.bubble.right"; case .discover: "square.grid.2x2"; case .library: "square.stack.3d.up"; case .runtime: "cpu"; case .settings: "slider.horizontal.3" }
    }
}

@MainActor @Observable
final class WorkspaceModel {
    var page: WorkspacePage = .chat
    var conversations: [Conversation] = []
    var selectedConversationID: UUID?
    var conversationSearch = ""
    var draft = ""
    var attachments: [ChatAttachment] = []
    var composerFocusID = UUID()
    var installedModels: [ModelRecord] = []
    var settings = HushSettings()
    var notice: HushNotice?
    var isReady = false
    var isImporting = false
    var isRemovingModel = false
    var generationStatus = "Ready on this device"
    var activeConversationID: UUID?
    var lastMetrics: GenerationMetrics?
    var loadedModelName: String?
    var isStopping = false
    var download: ModelDownload?
    var catalog: [ModelRecord] = []
    var catalogError: String?
    var isSearching = false
    var modelSearch = ""
    var modelSort = "downloads"
    let hardware = HardwareMonitor()
    let voice: VoiceCapture
    let speech = SpeechOutput()
    let liveVoice: LiveVoiceSession
    let capture = LiveCapture()
    let root: URL
    let hub = HuggingFaceClient()

    @ObservationIgnored private let persistence: LibraryStore
    @ObservationIgnored private let installer: ModelInstaller
    @ObservationIgnored private let attachmentImporter: AttachmentImporter
    @ObservationIgnored private let runtime: any InferenceServing
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationID: UUID?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID: UUID?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceRevision = 0
    @ObservationIgnored private var committedRevision = 0
    @ObservationIgnored private var bootstrapping = false
    @ObservationIgnored private var canPersist = true
    @ObservationIgnored private var persistedConversations: [Conversation] = []
    @ObservationIgnored private var drafts: [UUID: (String, [ChatAttachment])] = [:]
    @ObservationIgnored private var freshDraft: (String, [ChatAttachment]) = ("", [])
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var searchID: UUID?
    @ObservationIgnored private var liveGenerationID: UUID?
    @ObservationIgnored private var spokenGenerationID: UUID?
    @ObservationIgnored private var captureSubmissionID: UUID?
    @ObservationIgnored private var captureSubmissionTask: Task<Void, Never>?

    init(root: URL? = nil, runtime: any InferenceServing = InferenceRuntime()) {
        let voice = VoiceCapture()
        self.voice = voice
        self.liveVoice = LiveVoiceSession(input: voice, output: speech)
        self.root = root ?? (try? LibraryStore.defaultRoot())
            ?? FileManager.default.temporaryDirectory.appending(path: "Hush-Recovery")
        self.persistence = LibraryStore(root: self.root)
        self.installer = ModelInstaller(root: self.root)
        self.attachmentImporter = AttachmentImporter(root: self.root.appending(path: "Attachments"))
        self.runtime = runtime
        liveVoice.onTurn = { [weak self] text, id in try await self?.submitVoiceTurn(text, id: id) }
        liveVoice.onInterrupt = { [weak self] in
            guard let self, self.liveGenerationID == self.generationID else { return }
            self.cancelGeneration()
        }
        liveVoice.onError = { [weak self] error in self?.showError(error) }
        capture.onError = { [weak self] error in self?.showError(error) }
        speech.onError = { [weak self] error in
            self?.liveVoice.stop()
            self?.showError(error)
        }
    }

    var isGenerating: Bool { activeConversationID != nil }
    var availableModels: [ModelRecord] { [.apple] + installedModels }
    var selectedModel: ModelRecord { availableModels.first { $0.id == settings.selectedModelID } ?? .apple }
    var currentConversation: Conversation? { conversations.first { $0.id == selectedConversationID } }
    var messages: [ChatMessage] { currentConversation?.messages ?? [] }
    var filteredConversations: [Conversation] {
        conversations.filter { conversationSearch.isEmpty || $0.searchText.localizedStandardContains(conversationSearch) }
            .sorted { lhs, rhs in lhs.isPinned != rhs.isPinned ? lhs.isPinned : lhs.updatedAt > rhs.updatedAt }
    }
    var appleIsReady: Bool { SystemLanguageModel.default.isAvailable }
    var canStartResponse: Bool { isReady && !isGenerating && !isImporting && !isRemovingModel && !voice.isDictating }
    var canSend: Bool { canStartResponse && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }

    func bootstrap() async {
        guard !bootstrapping else { return }
        bootstrapping = true
        do {
            let archive = try await persistence.load()
            conversations = archive.conversations
            settings = archive.settings
            persistedConversations = conversations
            installedModels = try await persistence.installedModels()
            try await persistence.pruneAttachments(keeping: Set(conversations.flatMap(\.messages).flatMap(\.attachments).map(\.filename)))
            if !availableModels.contains(where: { $0.id == settings.selectedModelID }) { settings.selectedModelID = ModelRecord.apple.id }
        } catch {
            canPersist = false
            notice = HushNotice(title: "Your saved library is safe", message: "Hush could not read the library. It will not overwrite it. You can still use a temporary conversation. \(error.localizedDescription)")
        }
        isReady = true
        scheduleSave()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.hardware.refresh()
                if ProcessInfo.processInfo.thermalState == .critical && (self.liveVoice.isActive || self.capture.isActive) {
                    self.stopLiveInputs()
                    self.showError(HushError.message("Live inputs stopped because the device is too warm. Let it cool down before restarting."))
                }
                if self.settings.unloadWhenIdle && !self.isGenerating && self.loadedModelName != nil
                    && Date().timeIntervalSince(self.lastActivity) > 120 {
                    await self.unloadModel()
                }
            }
        }
    }

    func newConversation() {
        stopLiveInputs()
        rememberDraft()
        selectedConversationID = nil
        draft = freshDraft.0
        attachments = freshDraft.1
        composerFocusID = UUID()
        page = .chat
    }

    func selectConversation(_ id: UUID) {
        stopLiveInputs()
        rememberDraft()
        selectedConversationID = id
        draft = drafts[id]?.0 ?? ""
        attachments = drafts[id]?.1 ?? []
        composerFocusID = UUID()
        if let modelID = currentConversation?.modelID, availableModels.contains(where: { $0.id == modelID }) {
            settings.selectedModelID = modelID
        }
        page = .chat
    }

    func selectModel(_ model: ModelRecord) {
        guard model.isInstalled else { page = .discover; return }
        if model.id != settings.selectedModelID { stopLiveInputs() }
        settings.selectedModelID = model.id
        if let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) { conversations[index].modelID = model.id }
        scheduleSave()
    }

    func send(_ text: String? = nil) {
        if let text { draft = text }
        guard canSend else { return }
        if liveVoice.isActive { liveVoice.stop() }
        if capture.isActive {
            submitWithLiveFrame()
            return
        }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        submit(prompt: prompt, submittedAttachments: attachments)
    }

    private func submit(prompt: String, submittedAttachments: [ChatAttachment], clearDraft: Bool = true, liveTurnID: UUID? = nil) {
        guard canStartResponse else { return }
        if selectedConversationID == nil {
            let conversation = Conversation(title: String((prompt.isEmpty ? submittedAttachments.first?.name ?? "Image conversation" : prompt).prefix(54)), modelID: selectedModel.id)
            conversations.insert(conversation, at: 0)
            selectedConversationID = conversation.id
            freshDraft = ("", [])
        }
        guard let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else { return }
        let history = conversations[index].messages
        let userMessage = ChatMessage(role: .user, text: prompt.isEmpty ? "Tell me about this attachment." : prompt, attachments: submittedAttachments)
        conversations[index].messages.append(userMessage)
        if clearDraft { draft = "" }
        attachments = []
        drafts[conversations[index].id] = nil
        beginGeneration(conversationID: conversations[index].id, userMessage: userMessage, history: history, liveTurnID: liveTurnID)
    }

    func retry() {
        guard canStartResponse, let conversation = currentConversation,
              let index = conversations.firstIndex(where: { $0.id == conversation.id }),
              let userIndex = conversation.messages.lastIndex(where: { $0.role == .user }) else { return }
        stopLiveInputs()
        conversations[index].messages.removeSubrange((userIndex + 1)...)
        beginGeneration(conversationID: conversation.id, userMessage: conversation.messages[userIndex],
                        history: Array(conversation.messages.prefix(userIndex)))
    }

    func stop() {
        spokenGenerationID = nil
        speech.stop()
        if liveVoice.isActive { liveVoice.interrupt() }
        cancelGeneration()
    }

    private func cancelGeneration() {
        guard isGenerating else { return }
        isStopping = true
        generationStatus = "Stopping safely"
        generationTask?.cancel()
    }

    private func beginGeneration(conversationID: UUID, userMessage: ChatMessage, history: [ChatMessage], liveTurnID: UUID? = nil) {
        guard canStartResponse, let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let model = selectedModel
        let response = ChatMessage(role: .assistant, text: "", modelName: model.name, status: .generating)
        conversations[index].messages.append(response)
        conversations[index].updatedAt = Date()
        conversations[index].modelID = model.id
        let jobID = UUID()
        generationID = jobID
        liveGenerationID = liveTurnID == nil ? nil : jobID
        spokenGenerationID = nil
        if let liveTurnID { liveVoice.beginResponse(jobID, turnID: liveTurnID) }
        else {
            speech.stop()
            if settings.voiceOptions.speakResponses {
                spokenGenerationID = jobID
                speech.begin(id: response.id, preferences: settings.voiceOptions)
            }
        }
        activeConversationID = conversationID
        isStopping = false
        lastActivity = Date()
        generationStatus = "Preparing \(model.name)"
        scheduleSave()

        let modelDirectory = model.installedDirectory.flatMap { try? ModelPath.resolve($0, under: root.appending(path: "Models")) }
        var requestSettings = settings
        if liveTurnID != nil {
            requestSettings.instructions += "\nThis is a live spoken conversation. Answer naturally in short sentences. Avoid Markdown, long lists, and code unless explicitly requested. Refer to any live frame as a snapshot, not as continuous video."
            requestSettings.maximumOutputTokens = min(requestSettings.maximumOutputTokens, 384)
        }
        let request = GenerationRequest(conversationID: conversationID, model: model, modelDirectory: modelDirectory,
            history: history, prompt: userMessage.text, attachments: userMessage.attachments,
            attachmentDirectory: root.appending(path: "Attachments"), settings: requestSettings,
            memoryBudget: hardware.budget(for: settings.computePolicy))
        generationTask = Task { [weak self, runtime] in
            do {
                try await runtime.generate(request) { [weak self] event in
                    await self?.receive(event, jobID: jobID, conversationID: conversationID, responseID: response.id)
                }
                self?.loadedModelName = model.engine == .apple ? nil : model.name
            } catch {
                self?.finishWithError(error, jobID: jobID, conversationID: conversationID, responseID: response.id,
                                      cancelled: Task.isCancelled || error is CancellationError)
                await runtime.unload()
                self?.loadedModelName = nil
            }
            guard let self, self.generationID == jobID else { return }
            self.activeConversationID = nil
            self.generationID = nil
            self.liveGenerationID = nil
            self.spokenGenerationID = nil
            self.generationTask = nil
            self.isStopping = false
            self.lastActivity = Date()
            self.hardware.refresh()
            self.scheduleSave()
        }
    }

    private func receive(_ event: GenerationEvent, jobID: UUID, conversationID: UUID, responseID: UUID) {
        guard generationID == jobID, let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[index].messages.firstIndex(where: { $0.id == responseID }) else { return }
        switch event {
        case .status(let status): if !isStopping { generationStatus = status }
        case .snapshot(let text):
            conversations[index].messages[messageIndex].text = text
            if liveGenerationID == jobID { liveVoice.receiveResponse(text, id: jobID, final: false) }
            else if spokenGenerationID == jobID { speech.append(snapshot: text, final: false) }
        case .completed(let metrics):
            conversations[index].messages[messageIndex].metrics = metrics
            conversations[index].messages[messageIndex].status = .complete
            lastMetrics = metrics
            generationStatus = "Completed on this device"
            let text = conversations[index].messages[messageIndex].text
            if liveGenerationID == jobID { liveVoice.receiveResponse(text, id: jobID, final: true) }
            else if spokenGenerationID == jobID { speech.append(snapshot: text, final: true) }
        }
    }

    private func finishWithError(_ error: Error, jobID: UUID, conversationID: UUID, responseID: UUID, cancelled: Bool) {
        guard generationID == jobID, let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[index].messages.firstIndex(where: { $0.id == responseID }) else { return }
        conversations[index].messages[messageIndex].status = cancelled ? .stopped : .failed
        if conversations[index].messages[messageIndex].text.isEmpty {
            conversations[index].messages[messageIndex].text = cancelled ? "Response stopped." : error.localizedDescription
        } else if !cancelled {
            notice = HushNotice(title: "Response interrupted", message: error.localizedDescription)
        }
        generationStatus = cancelled ? "Stopped" : "Could not complete this response"
        if liveGenerationID == jobID { liveVoice.failedResponse(jobID) }
        else if spokenGenerationID == jobID { speech.stop() }
    }

    func togglePin(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isPinned.toggle()
        scheduleSave()
    }

    func deleteConversation(_ id: UUID) {
        guard id != activeConversationID else { showError(HushError.message("Stop the response before deleting this conversation.")); return }
        let messages = conversations.first { $0.id == id }?.messages ?? []
        let removed = Set((messages.flatMap(\.attachments) + (drafts[id]?.1 ?? [])
                           + (selectedConversationID == id ? attachments : [])).map(\.filename))
        conversations.removeAll { $0.id == id }
        persistedConversations.removeAll { $0.id == id }
        drafts[id] = nil
        if selectedConversationID == id {
            stopLiveInputs()
            selectedConversationID = nil
            draft = freshDraft.0
            attachments = freshDraft.1
            composerFocusID = UUID()
        }
        scheduleSave()
        Task {
            guard await flush() else { return }
            do { try await persistence.removeAttachments(removed.subtracting(retainedAttachmentNames)) }
            catch { showError(error) }
        }
    }

    func addAttachments(_ urls: [URL]) async {
        guard isReady, !isImporting else { return }
        guard attachments.count + urls.count <= 4 else { showError(HushError.message("Attach up to four files per message.")); return }
        isImporting = true
        let conversationID = selectedConversationID
        defer { isImporting = false }
        for url in urls {
            do {
                let attachment = try await attachmentImporter.importFile(url)
                if selectedConversationID == conversationID { attachments.append(attachment) }
                else if let conversationID, conversations.contains(where: { $0.id == conversationID }) {
                    var saved = drafts[conversationID] ?? ("", [])
                    saved.1.append(attachment)
                    drafts[conversationID] = saved
                } else if conversationID == nil {
                    freshDraft.1.append(attachment)
                } else {
                    try await persistence.removeAttachments([attachment.filename])
                }
            } catch { showError(error) }
        }
    }

    func removeAttachment(_ id: UUID) {
        let removed = Set(attachments.filter { $0.id == id }.map(\.filename))
        attachments.removeAll { $0.id == id }
        rememberDraft()
        let unused = removed.subtracting(retainedAttachmentNames)
        Task {
            do { try await persistence.removeAttachments(unused) }
            catch { showError(error) }
        }
    }

    func searchModels() async {
        let id = UUID()
        searchID = id
        isSearching = true
        catalogError = nil
        defer { if searchID == id { isSearching = false } }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let results = try await hub.search(modelSearch, sort: modelSort, token: HubCredential.load())
            try Task.checkCancellation()
            guard searchID == id else { return }
            catalog = results
        } catch {
            if !Task.isCancelled && searchID == id { catalogError = error.localizedDescription }
        }
    }

    func install(_ manifest: ModelManifest) {
        guard downloadTask == nil else { showError(HushError.message("A model is already downloading. Pause it first.")); return }
        let jobID = UUID()
        downloadID = jobID
        download = ModelDownload(modelID: manifest.model.id, totalBytes: manifest.totalBytes)
        let token = HubCredential.load()
        downloadTask = Task { [weak self, installer] in
            do {
                let model = try await installer.download(manifest, token: token) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.downloadID == jobID, self.download?.isActive == true else { return }
                        self.download = progress
                    }
                }
                guard let self, self.downloadID == jobID else { return }
                self.installedModels.removeAll { $0.id == model.id }
                self.installedModels.append(model)
                self.download = ModelDownload(modelID: model.id, phase: .complete, completedBytes: manifest.totalBytes,
                                              totalBytes: manifest.totalBytes, filename: "Ready to use")
            } catch {
                guard let self, self.downloadID == jobID else { return }
                self.download?.phase = Task.isCancelled ? .paused : .failed
                self.download?.error = Task.isCancelled ? nil : error.localizedDescription
            }
            if self?.downloadID == jobID { self?.downloadTask = nil }
        }
    }

    func pauseDownload() { downloadTask?.cancel() }

    func importCoreAI(_ url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let model = try await installer.importCoreAI(from: url)
            installedModels.append(model)
            page = .library
        } catch { showError(error) }
    }

    func removeModel(_ model: ModelRecord) async {
        guard !isGenerating, !isImporting, !isRemovingModel else {
            showError(HushError.message("Finish the active response or file operation before removing a model.")); return
        }
        isRemovingModel = true
        defer { isRemovingModel = false }
        await unloadModel()
        do {
            try await persistence.removeModel(model)
            installedModels.removeAll { $0.id == model.id }
            if settings.selectedModelID == model.id { settings.selectedModelID = ModelRecord.apple.id }
            scheduleSave()
        } catch { showError(error) }
    }

    func unloadModel() async {
        guard !isGenerating else { return }
        await runtime.unload()
        loadedModelName = nil
        hardware.refresh()
    }

    func savePreferences() {
        settings.validate()
        scheduleSave()
    }

    @discardableResult
    func flush() async -> Bool {
        guard isReady, canPersist else { return false }
        persistenceTask?.cancel()
        persistenceRevision += 1
        let revision = persistenceRevision
        let archive = LibraryArchive(conversations: settings.keepHistory ? conversations : persistedConversations, settings: settings)
        do {
            let saved = try await persistence.save(archive, revision: revision)
            if saved, revision >= committedRevision {
                persistedConversations = archive.conversations
                committedRevision = revision
            }
            return saved
        } catch { showError(error); return false }
    }

    func prepareToClose() async {
        stopLiveInputs()
        stop()
        downloadTask?.cancel()
        await generationTask?.value
        await downloadTask?.value
        await captureSubmissionTask?.value
        await capture.waitUntilStopped()
        await flush()
        await unloadModel()
    }

    func toggleDictation() {
        if liveVoice.isActive { liveVoice.toggleMute(); return }
        if voice.phase == .recording { voice.finish(); return }
        if voice.isActive { voice.cancel(); return }
        guard canStartResponse else { return }
        speech.stop()
        let base = draft
        let conversationID = selectedConversationID
        voice.start(mode: .dictation, onReady: {}, onUpdate: { [weak self] text in
            guard let self else { return }
            guard self.selectedConversationID == conversationID else { return }
            self.draft = base + (base.isEmpty || text.isEmpty ? "" : " ") + text
        }, onLevel: { _ in }, onError: { [weak self] error in self?.showError(error) })
    }

    func toggleLiveVoice() {
        if liveVoice.isActive { stopLiveInputs(); return }
        guard canStartResponse else { return }
        liveVoice.start(preferences: settings.voiceOptions)
    }

    func stopLiveInputs() {
        captureSubmissionID = nil
        captureSubmissionTask?.cancel()
        liveVoice.stop()
        voice.cancel()
        speech.stop()
        spokenGenerationID = nil
        capture.stop()
    }

    func readAloud(_ message: ChatMessage) {
        if speech.messageID == message.id, speech.isSpeaking { speech.stop(); return }
        liveVoice.stop()
        voice.cancel()
        spokenGenerationID = nil
        speech.begin(id: message.id, preferences: settings.voiceOptions)
        speech.append(snapshot: message.text, final: true)
    }

    private func liveAttachment() async throws -> ChatAttachment? {
        guard capture.isActive else { return nil }
        guard selectedModel.supportsVision else {
            throw HushError.message("Choose a vision-capable model to use live camera or screen context.")
        }
        guard let frame = capture.frame, !capture.isStarting else {
            throw HushError.message("Wait for the live preview before sending your question.")
        }
        if capture.source == .camera, Date().timeIntervalSince(frame.capturedAt) > 5 {
            throw HushError.message("The camera preview stopped updating. Restart the camera before asking about it.")
        }
        return try await attachmentImporter.importCapturedImage(frame.jpeg,
            name: "\(capture.title) \(frame.capturedAt.formatted(date: .omitted, time: .standard))")
    }

    private func submitWithLiveFrame() {
        guard attachments.count < 4 else { showError(HushError.message("Leave one attachment slot for the live frame.")); return }
        let id = UUID()
        captureSubmissionID = id
        let prompt = draft
        let submitted = attachments
        let conversationID = selectedConversationID
        let modelID = settings.selectedModelID
        isImporting = true
        captureSubmissionTask = Task {
            var image: ChatAttachment?
            defer { isImporting = false }
            do {
                image = try await liveAttachment()
                try Task.checkCancellation()
                guard captureSubmissionID == id, selectedConversationID == conversationID,
                      settings.selectedModelID == modelID, draft == prompt, attachments == submitted else {
                    if let image { try await persistence.removeAttachments([image.filename]) }
                    return
                }
                isImporting = false
                submit(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    submittedAttachments: submitted + (image.map { [$0] } ?? []))
            } catch {
                if let image { try? await persistence.removeAttachments([image.filename]) }
                if !(error is CancellationError) { showError(error) }
            }
        }
    }

    private func submitVoiceTurn(_ text: String, id: UUID) async throws {
        await generationTask?.value
        try Task.checkCancellation()
        guard liveVoice.isActive, liveVoice.pendingTurnID == id, canStartResponse else {
            throw HushError.message("Finish the active file operation before asking another question.")
        }
        guard attachments.count < (capture.isActive ? 4 : 5) else {
            throw HushError.message("Leave one attachment slot for the live frame.")
        }
        isImporting = true
        var image: ChatAttachment?
        let modelID = settings.selectedModelID
        defer { isImporting = false }
        do {
            image = try await liveAttachment()
            try Task.checkCancellation()
            guard liveVoice.isActive, liveVoice.pendingTurnID == id, settings.selectedModelID == modelID else {
                throw CancellationError()
            }
            isImporting = false
            submit(prompt: text, submittedAttachments: attachments + (image.map { [$0] } ?? []),
                   clearDraft: false, liveTurnID: id)
        } catch {
            if let image { try? await persistence.removeAttachments([image.filename]) }
            throw error
        }
    }

    func editMessage(_ messageID: UUID, text: String) {
        guard canStartResponse, let original = currentConversation,
              let position = original.messages.firstIndex(where: { $0.id == messageID && $0.role == .user }) else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stopLiveInputs()
        rememberDraft()
        var branch = Conversation(title: String((original.title + " / Edited").prefix(80)), modelID: selectedModel.id)
        branch.branch = ConversationBranch(conversationID: original.id, messageID: messageID)
        branch.messages = Array(original.messages.prefix(position))
        let edited = ChatMessage(role: .user, text: text, attachments: original.messages[position].attachments)
        let history = branch.messages
        branch.messages.append(edited)
        conversations.insert(branch, at: 0)
        selectedConversationID = branch.id
        draft = ""
        attachments = []
        page = .chat
        beginGeneration(conversationID: branch.id, userMessage: edited, history: history)
    }

    func branchConversation(at messageID: UUID) {
        guard canStartResponse, let original = currentConversation,
              let position = original.messages.firstIndex(where: { $0.id == messageID }) else { return }
        stopLiveInputs()
        rememberDraft()
        var branch = Conversation(title: String((original.title + " / Branch").prefix(80)), modelID: selectedModel.id)
        branch.branch = ConversationBranch(conversationID: original.id, messageID: messageID)
        branch.messages = Array(original.messages.prefix(position + 1))
        conversations.insert(branch, at: 0)
        selectedConversationID = branch.id
        draft = ""
        attachments = []
        composerFocusID = UUID()
        page = .chat
        if let last = branch.messages.last, last.role == .user {
            beginGeneration(conversationID: branch.id, userMessage: last, history: Array(branch.messages.dropLast()))
        } else { scheduleSave() }
    }

    func renameConversation(_ id: UUID, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = String(title.prefix(80))
        scheduleSave()
    }

    func showError(_ error: Error) { notice = HushNotice(title: "Hush needs your attention", message: error.localizedDescription) }

    private func rememberDraft() {
        if let selectedConversationID { drafts[selectedConversationID] = (draft, attachments) }
        else { freshDraft = (draft, attachments) }
    }

    private var retainedAttachmentNames: Set<String> {
        Set((conversations.flatMap(\.messages).flatMap(\.attachments)
             + persistedConversations.flatMap(\.messages).flatMap(\.attachments)
             + attachments + freshDraft.1 + drafts.values.flatMap { $0.1 }).map(\.filename))
    }

    private func scheduleSave() {
        guard isReady, canPersist else { return }
        persistenceRevision += 1
        let revision = persistenceRevision
        let archive = LibraryArchive(conversations: settings.keepHistory ? conversations : persistedConversations,
                                     settings: settings)
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, persistence] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                let saved = try await persistence.save(archive, revision: revision)
                if let self, saved, revision >= self.committedRevision {
                    self.persistedConversations = archive.conversations
                    self.committedRevision = revision
                }
            } catch is CancellationError { }
            catch { self?.showError(error) }
        }
    }
}
