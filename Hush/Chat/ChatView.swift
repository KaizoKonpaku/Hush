import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    var onDiscover: (() -> Void)?
    @State private var isNearBottom = true
    @State private var showsAttachmentPicker = false
    @FocusState private var composerFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 52
    @ScaledMetric(relativeTo: .title) private var compactHeroSize = 32

    var body: some View {
        @Bindable var workspace = workspace
        ScrollViewReader { proxy in
            ScrollView {
                if workspace.messages.isEmpty {
                    welcome
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(workspace.messages) { message in
                            MessageView(message: message, isLast: workspace.messages.last?.id == message.id)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 740).padding(.horizontal, compact ? 22 : 32)
                    .padding(.top, 30).padding(.bottom, 10).frame(maxWidth: .infinity)
                }
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 100
            } action: { _, nearBottom in isNearBottom = nearBottom }
            .onChange(of: workspace.messages.last?.text) {
                if isNearBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: workspace.messages.count) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: workspace.selectedConversationID) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer.padding(.top, 14).padding(.bottom, compact ? 14 : 20)
        }
        .fileImporter(isPresented: $showsAttachmentPicker, allowedContentTypes: [.image, .pdf, .text, .sourceCode, .json], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await workspace.addAttachments(urls) }
            case .failure(let error): workspace.showError(error)
            }
        }
        .onChange(of: workspace.composerFocusID) { composerFocused = true }
        .onDisappear { workspace.stopLiveInputs() }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await workspace.addAttachments(urls) }
            return !urls.isEmpty
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 25) {
            if !compact {
                HStack(spacing: 7) {
                    Circle().fill(HushStyle.accent).frame(width: 5, height: 5)
                    Eyebrow(text: "A private place for your ideas")
                }
            }
            Text(compact ? "A thought away." : "A clearer space\nto think.")
                .font(.system(size: compact ? compactHeroSize : heroSize, weight: .regular, design: .serif))
                .tracking(compact ? -0.7 : -1.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your models. Your ideas. On your device.")
                .font(compact ? .callout : .body).foregroundStyle(.secondary)

            if workspace.selectedModel.engine == .apple && !workspace.appleIsReady {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(HushStyle.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(InferenceRuntime.appleAvailabilityMessage).font(.callout).foregroundStyle(.secondary)
                        Button("Find a local model") { discoverModels() }.buttonStyle(.plain).foregroundStyle(HushStyle.accent)
                    }
                }.padding(.top, 2)
            }
            if !compact {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    suggestion("Untangle an idea", subtitle: "Find the clear next step", symbol: "lightbulb") {
                        workspace.draft = "Help me think through an idea. Ask me a few focused questions to get started."
                        composerFocused = true
                    }
                    suggestion("Make it well written", subtitle: "A first draft, a fresh angle", symbol: "pencil.line") {
                        workspace.draft = "Help me write something. First, ask what I'm writing and who it's for."
                        composerFocused = true
                    }
                    suggestion("Bring your context", subtitle: "Read an image or document", symbol: "doc.viewfinder") {
                        showsAttachmentPicker = true
                    }
                    suggestion("Find your model", subtitle: "Explore the open ecosystem", symbol: "square.stack.3d.up") {
                        discoverModels()
                    }
                }.padding(.top, 13)
            }
        }
        .frame(maxWidth: compact ? 520 : 570, alignment: .leading)
        .padding(.horizontal, compact ? 24 : 36)
        .padding(.top, compact ? 25 : 88).padding(.bottom, compact ? 20 : 50)
    }

    private func discoverModels() {
        workspace.page = .discover
        onDiscover?()
    }

    private func suggestion(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(HushStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .hushCard(padding: 18)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        @Bindable var workspace = workspace
        return VStack(spacing: 10) {
            if workspace.capture.isActive { LiveCaptureBar() }
            if workspace.liveVoice.isActive { LiveVoiceBar() }
            else if workspace.speech.isSpeaking { SpeechPlaybackBar() }
            if !workspace.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workspace.attachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachment.kind == .image ? "photo" : "doc.text")
                                Text(attachment.name).lineLimit(1)
                                Button {
                                    workspace.removeAttachment(attachment.id)
                                } label: {
                                    Image(systemName: "xmark").frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
                                }
                                .buttonStyle(.plain).accessibilityLabel("Remove \(attachment.name)")
                            }
                            .font(.caption).padding(.horizontal, 12).padding(.vertical, 8)
                            .nativeGlass(in: .capsule)
                        }
                    }.padding(.horizontal, 4)
                }
            }
            if !workspace.liveVoice.isActive && (workspace.isGenerating || workspace.isImporting || workspace.voice.isActive) {
                HStack(spacing: 7) {
                    if workspace.voice.phase == .recording {
                        Circle().fill(.red).frame(width: 6, height: 6)
                    } else { ProgressView().controlSize(.mini) }
                    Text(workspace.voice.isActive ? workspace.voice.status : workspace.isImporting ? "Reading on this device" : workspace.generationStatus)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, 60)
            }
            NativeGlassGroup(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    Menu {
                        Button("Attach files or images", systemImage: "paperclip") { showsAttachmentPicker = true }
                        Divider()
                        #if os(macOS) || os(iOS)
                        Button("Start live camera", systemImage: "video") { workspace.capture.startCamera() }
                        #endif
                        Button("Share screen live", systemImage: "rectangle.inset.filled") { workspace.capture.startScreen() }
                            .disabled(!LiveCapture.supportsScreenCapture)
                        if workspace.capture.isActive {
                            Button("Stop visual sharing", systemImage: "xmark.circle") { workspace.capture.stop() }
                        }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 19, weight: .regular)).frame(width: 28, height: 28)
                    }
                    .menuIndicator(.hidden)
                    .nativeGlassButton().buttonBorderShape(.circle).controlSize(.large)
                    .accessibilityLabel("Attach files, use camera, or share screen").help("Files, live camera, and screen sharing")
                    .disabled(!workspace.isReady || workspace.isImporting)

                    HStack(alignment: .bottom, spacing: 4) {
                        TextField("Message Hush...", text: $workspace.draft, axis: .vertical)
                            .textFieldStyle(.plain).font(.body)
                            .lineLimit(1...6).padding(.leading, 22).padding(.vertical, 16)
                            .focused($composerFocused)
                            .onSubmit { workspace.send() }
                            .accessibilityLabel("Message Hush")
                            .disabled(workspace.voice.isDictating || workspace.isImporting)
                        Button { workspace.toggleDictation() } label: {
                            Image(systemName: workspace.liveVoice.isMuted ? "mic.slash" : workspace.voice.isActive ? "waveform" : "mic")
                                .font(.system(size: 16)).frame(width: 44, height: 52)
                                .foregroundStyle(workspace.voice.isActive ? .red : .secondary)
                        }
                        .buttonStyle(.plain).padding(.trailing, 5)
                        .disabled(!workspace.liveVoice.isActive && (workspace.isGenerating || workspace.isImporting))
                        .accessibilityLabel(workspace.liveVoice.isActive ? (workspace.liveVoice.isMuted ? "Unmute microphone" : "Mute microphone") : workspace.voice.isActive ? "Finish dictation" : "Dictate on device")
                        .help("Live on-device dictation. Language assets may download on first use.")
                    }
                    .frame(minHeight: 52)
                    .nativeGlass(in: .rect(cornerRadius: 27))

                    Button {
                        if workspace.isGenerating { workspace.stop() } else { workspace.send() }
                    } label: {
                        Image(systemName: workspace.isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 18, weight: .semibold)).frame(width: 28, height: 28)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    }
                    .nativeGlassButton(prominent: true).buttonBorderShape(.circle).controlSize(.large)
                    .disabled(workspace.isGenerating ? workspace.isStopping : !workspace.canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(workspace.isGenerating ? "Stop response" : "Send message")
                }
            }
            if !compact {
                HStack(spacing: 4) {
                    Image(systemName: "lock").font(.system(size: 9))
                    Text("Stays on this device. AI can make mistakes.").font(.caption2)
                }.foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, compact ? 18 : 24)
        .frame(maxWidth: .infinity)
    }
}
