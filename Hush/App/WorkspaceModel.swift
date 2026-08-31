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
    let voice = VoiceCapture()
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

    init(root: URL? = nil, runtime: any InferenceServing = InferenceRuntime()) {
        self.root = root ?? (try? LibraryStore.defaultRoot())
            ?? FileManager.default.temporaryDirectory.appending(path: "Hush-Recovery")
        self.persistence = LibraryStore(root: self.root)
        self.installer = ModelInstaller(root: self.root)
        self.attachmentImporter = AttachmentImporter(root: self.root.appending(path: "Attachments"))
        self.runtime = runtime
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
    var canStartResponse: Bool { isReady && !isGenerating && !isImporting && !isRemovingModel && !voice.isActive }
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
                if self.settings.unloadWhenIdle && !self.isGenerating && self.loadedModelName != nil
                    && Date().timeIntervalSince(self.lastActivity) > 120 {
                    await self.unloadModel()
                }
            }
        }
    }

    func newConversation() {
        voice.cancel()
        rememberDraft()
        selectedConversationID = nil
        draft = freshDraft.0
        attachments = freshDraft.1
        composerFocusID = UUID()
        page = .chat
    }

    func selectConversation(_ id: UUID) {
        voice.cancel()
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
        settings.selectedModelID = model.id
        if let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) { conversations[index].modelID = model.id }
        scheduleSave()
    }

    func send(_ text: String? = nil) {
        if let text { draft = text }
        guard canSend else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedAttachments = attachments
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
        draft = ""
        attachments = []
        drafts[conversations[index].id] = nil
        beginGeneration(conversationID: conversations[index].id, userMessage: userMessage, history: history)
    }

    func retry() {
        guard canStartResponse, let conversation = currentConversation,
              let index = conversations.firstIndex(where: { $0.id == conversation.id }),
              let userIndex = conversation.messages.lastIndex(where: { $0.role == .user }) else { return }
        conversations[index].messages.removeSubrange((userIndex + 1)...)
        beginGeneration(conversationID: conversation.id, userMessage: conversation.messages[userIndex],
                        history: Array(conversation.messages.prefix(userIndex)))
    }

    func stop() {
        guard isGenerating else { return }
        isStopping = true
        generationStatus = "Stopping safely"
        generationTask?.cancel()
    }

    private func beginGeneration(conversationID: UUID, userMessage: ChatMessage, history: [ChatMessage]) {
        guard canStartResponse, let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let model = selectedModel
        let response = ChatMessage(role: .assistant, text: "", modelName: model.name, status: .generating)
        conversations[index].messages.append(response)
        conversations[index].updatedAt = Date()
        conversations[index].modelID = model.id
        let jobID = UUID()
        generationID = jobID
        activeConversationID = conversationID
        isStopping = false
        lastActivity = Date()
        generationStatus = "Preparing \(model.name)"
        scheduleSave()

        let modelDirectory = model.installedDirectory.flatMap { try? ModelPath.resolve($0, under: root.appending(path: "Models")) }
        let request = GenerationRequest(conversationID: conversationID, model: model, modelDirectory: modelDirectory,
            history: history, prompt: userMessage.text, attachments: userMessage.attachments,
            attachmentDirectory: root.appending(path: "Attachments"), settings: settings,
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
        case .snapshot(let text): conversations[index].messages[messageIndex].text = text
        case .completed(let metrics):
            conversations[index].messages[messageIndex].metrics = metrics
            conversations[index].messages[messageIndex].status = .complete
            lastMetrics = metrics
            generationStatus = "Completed on this device"
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
            voice.cancel()
            selectedConversationID = nil
            draft = freshDraft.0
            attachments = freshDraft.1
            composerFocusID = UUID()
        }
        let retained = retainedAttachmentNames
        scheduleSave()
        Task {
            guard await flush() else { return }
            do { try await persistence.removeAttachments(removed.subtracting(retained)) }
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
        voice.cancel()
        stop()
        downloadTask?.cancel()
        await generationTask?.value
        await downloadTask?.value
        await flush()
        await unloadModel()
    }

    func toggleDictation() {
        if voice.phase == .recording { voice.finish(); return }
        if voice.isActive { voice.cancel(); return }
        voice.start { [weak self] text in
            guard let self else { return }
            self.draft += (self.draft.isEmpty ? "" : " ") + text
        } onError: { [weak self] error in self?.showError(error) }
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
