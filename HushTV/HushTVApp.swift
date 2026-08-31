import SwiftUI
import Observation

@main
struct HushTVApp: App {
    @State private var workspace = TVWorkspace()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TVWorkspaceView().environment(workspace)
                .task { await workspace.load() }
                .onChange(of: phase) { _, value in
                    if value == .background { workspace.stop(); Task { await workspace.unload() } }
                }
        }
    }
}

@MainActor @Observable
final class TVWorkspace {
    var models: [ModelRecord] = []
    var catalog: [ModelRecord] = []
    var selectedModelID: String?
    var query = "Qwen3-0.6B"
    var prompt = ""
    var messages: [ChatMessage] = []
    var isGenerating = false
    var isRemovingModel = false
    var isSearching = false
    var download: ModelDownload?
    var notice: HushNotice?
    let hardware = HardwareMonitor()
    private let engine = MLXEngine()
    private let hub = HuggingFaceClient()
    private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "HushTV")
    private var conversationID = UUID()
    private var generationTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?
    private var didLoad = false

    var selectedModel: ModelRecord? { models.first { $0.id == selectedModelID } }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            models = try await LibraryStore(root: root).installedModels()
            selectedModelID = models.first?.id
        } catch { report(error) }
        await search()
    }

    func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            try await Task.sleep(for: .milliseconds(300))
            catalog = try await hub.search(query)
        } catch { if !Task.isCancelled { report(error) } }
    }

    func install(_ model: ModelRecord) {
        guard downloadTask == nil else { return }
        let id = UUID()
        downloadID = id
        download = ModelDownload(modelID: model.id)
        downloadTask = Task { [self] in
            do {
                let manifest = try await hub.manifest(for: model)
                guard manifest.totalBytes + max(768 * 1024 * 1024, manifest.totalBytes / 4) < Int64(hardware.budget(for: .maximum)) else {
                    throw HushError.message("This model is too large for this Apple TV. Choose a smaller 4-bit model.")
                }
                let installed = try await ModelInstaller(root: root).download(manifest, token: nil) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.downloadID == id, self.download?.isActive == true else { return }
                        self.download = progress
                    }
                }
                models.append(installed)
                selectedModelID = installed.id
                download = nil
            } catch {
                download?.phase = Task.isCancelled ? .paused : .failed
                download?.error = Task.isCancelled ? nil : error.localizedDescription
            }
            downloadID = nil
            downloadTask = nil
        }
    }

    func pauseDownload() { downloadTask?.cancel() }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !isRemovingModel, !text.isEmpty, let model = selectedModel, let folder = model.installedDirectory else { return }
        let history = messages
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: "", modelName: model.name, status: .generating))
        let responseID = messages.last!.id
        prompt = ""
        isGenerating = true
        var settings = HushSettings()
        settings.maximumOutputTokens = 512
        let request = GenerationRequest(conversationID: conversationID, model: model,
            modelDirectory: root.appending(path: "Models/\(folder)"), history: history, prompt: text,
            attachments: [], attachmentDirectory: root.appending(path: "Attachments"), settings: settings,
            memoryBudget: hardware.budget(for: .maximum))
        generationTask = Task { [self] in
            do {
                try await engine.generate(request) { [weak self] event in await self?.receive(event, id: responseID) }
            } catch {
                if let index = messages.firstIndex(where: { $0.id == responseID }) {
                    messages[index].status = Task.isCancelled ? .stopped : .failed
                    if messages[index].text.isEmpty { messages[index].text = Task.isCancelled ? "Stopped." : error.localizedDescription }
                }
                if !Task.isCancelled { report(error) }
                await engine.unload()
            }
            isGenerating = false
            generationTask = nil
            hardware.refresh()
        }
    }

    private func receive(_ event: GenerationEvent, id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .snapshot(let text): messages[index].text = text
        case .completed(let metrics): messages[index].metrics = metrics; messages[index].status = .complete
        case .status: break
        }
    }

    func newConversation() {
        guard !isGenerating else { return }
        messages = []
        conversationID = UUID()
    }

    func stop() { generationTask?.cancel() }
    func unload() async { await generationTask?.value; await engine.unload(); hardware.refresh() }

    func removeModel(_ model: ModelRecord) async {
        guard !isGenerating, !isRemovingModel else { return }
        isRemovingModel = true
        defer { isRemovingModel = false }
        await unload()
        do {
            try await LibraryStore(root: root).removeModel(model)
            models.removeAll { $0.id == model.id }
            if selectedModelID == model.id { selectedModelID = models.first?.id }
        } catch { report(error) }
    }

    private func report(_ error: Error) { notice = HushNotice(title: "Hush", message: error.localizedDescription) }
}

struct TVWorkspaceView: View {
    @Environment(TVWorkspace.self) private var workspace
    @State private var modelToRemove: ModelRecord?

    var body: some View {
        @Bindable var workspace = workspace
        TabView {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") { chat }
            Tab("Models", systemImage: "square.stack.3d.up") { models }
            Tab("Device", systemImage: "cpu") { device }
        }
        .tint(HushStyle.accent)
        .alert(item: $workspace.notice) { notice in Alert(title: Text(notice.title), message: Text(notice.message)) }
        .confirmationDialog("Remove this model?", isPresented: Binding(get: { modelToRemove != nil }, set: { if !$0 { modelToRemove = nil } })) {
            Button("Remove download", role: .destructive) {
                if let model = modelToRemove { Task { await workspace.removeModel(model) } }
                modelToRemove = nil
            }
        } message: { Text("Remove \(modelToRemove?.name ?? "this model") from this Apple TV. You can download it again later.") }
    }

    private var chat: some View {
        @Bindable var workspace = workspace
        return VStack(spacing: 30) {
            HStack {
                HushMark(size: 48)
                Text("hush").font(.system(size: 44, design: .serif))
                Spacer()
                if !workspace.models.isEmpty {
                    Picker("Model", selection: $workspace.selectedModelID) {
                        ForEach(workspace.models) { Text($0.name).tag(Optional($0.id)) }
                    }.frame(maxWidth: 480)
                }
                Button("New", systemImage: "square.and.pencil") { workspace.newConversation() }
                    .disabled(workspace.isGenerating)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if workspace.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Small models.\nA bigger canvas.").font(.system(size: 76, weight: .regular, design: .serif))
                            Text(workspace.selectedModel == nil ? "Choose a small model in Models to start. Everything runs here, on Apple TV." : "A private conversation, powered by your Apple TV.")
                                .font(.title3).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 30)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(workspace.messages) { message in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(message.role == .user ? "YOU" : "HUSH").font(.caption).foregroundStyle(.secondary)
                                    Text(message.text.isEmpty ? "Thinking on this device..." : message.text).font(.title3)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                    }
                }
                .onChange(of: workspace.messages.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(spacing: 20) {
                TextField("Message Hush", text: $workspace.prompt).onSubmit { workspace.send() }
                Button(workspace.isGenerating ? "Stop" : "Send", systemImage: workspace.isGenerating ? "stop.fill" : "arrow.up") {
                    if workspace.isGenerating { workspace.stop() } else { workspace.send() }
                }
                .buttonStyle(.glassProminent)
                .disabled(!workspace.isGenerating && (workspace.selectedModel == nil || workspace.prompt.isEmpty || workspace.isRemovingModel))
            }
            Text("On-device MLX. No cloud inference. Conversations are not saved on TV.").font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 80).padding(.vertical, 32)
    }

    private var models: some View {
        @Bindable var workspace = workspace
        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Find your model.").font(.system(size: 58, design: .serif))
                Text("Public Hugging Face models. Start with a small 4-bit model; Apple TV has a limited memory budget.")
                    .foregroundStyle(.secondary)
                TextField("Search MLX models", text: $workspace.query).onSubmit { Task { await workspace.search() } }
                if workspace.isSearching { ProgressView("Searching") }
                if let download = workspace.download {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(download.error ?? download.filename).font(.headline)
                        ProgressView(value: download.fraction)
                        if download.isActive { Button("Pause download") { workspace.pauseDownload() } }
                        else { Text("Select the model again to resume.").font(.caption) }
                    }.padding(24).glassEffect()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 30)], spacing: 30) {
                    ForEach(workspace.catalog) { model in
                        let installed = workspace.models.first { $0.id == model.id }
                        Button {
                            if installed != nil { workspace.selectedModelID = model.id }
                            else { workspace.install(model) }
                        } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                ModelGlyph(model: model, size: 60)
                                Text(model.name).font(.headline).lineLimit(2)
                                Text(installed == nil ? "Download from \(model.author)" : "Installed. Select to use.").font(.caption).foregroundStyle(.secondary)
                                if let license = model.license { Text(license).font(.caption2) }
                            }.frame(maxWidth: .infinity, minHeight: 200, alignment: .leading).padding(24)
                        }.buttonStyle(.card)
                    }
                }
                Text("tvOS may reclaim downloaded models when storage is low. Remove an unavailable model in Device, then download it again.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(80)
        }
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Made for this device.").font(.system(size: 58, design: .serif))
            Text(workspace.hardware.chipName).font(.title)
            Text("Unified memory: \(HardwareMonitor.bytes(Int64(workspace.hardware.physicalMemory)))")
            Text("Model budget: \(HardwareMonitor.bytes(Int64(workspace.hardware.budget(for: .maximum))))")
            Text("MLX uses Metal acceleration within the system's recommended memory limits. Thermal safeguards remain active.")
                .foregroundStyle(.secondary)
            Button("Unload model") { Task { await workspace.unload() } }.disabled(workspace.isGenerating || workspace.isRemovingModel)
            if let model = workspace.selectedModel {
                Button("Remove \(model.name)", role: .destructive) { modelToRemove = model }
                    .disabled(workspace.isGenerating || workspace.isRemovingModel)
            }
            if workspace.isRemovingModel { ProgressView("Removing model") }
        }.padding(80)
    }
}
