import SwiftUI

struct MessageView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let message: ChatMessage
    var isLast: Bool
    @State private var copied = false
    @State private var showsEditor = false
    @State private var editedText = ""

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 12) {
                if message.role == .assistant {
                    HStack(spacing: 8) {
                        HushMark(size: 17)
                        Text(message.modelName ?? "Hush").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        if message.status == .stopped { Text("Stopped").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
                if message.text.isEmpty && message.status == .generating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(workspace.generationStatus).font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else {
                    MarkdownMessage(text: message.text)
                        .foregroundStyle(message.status == .failed ? .secondary : .primary)
                }
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { attachment in
                        Label(attachment.name, systemImage: attachment.kind == .image ? "photo" : "doc.text")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if message.role == .assistant && message.status != .generating {
                    HStack(spacing: 6) {
                        Button {
                            copyText(message.text)
                            copied = true
                        } label: { actionLabel(copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc") }
                        .help("Copy response")
                        if isLast {
                            Button { workspace.retry() } label: { actionLabel("Try again", symbol: "arrow.clockwise") }
                                .disabled(!workspace.canStartResponse)
                        }
                        ShareLink(item: message.text) { actionLabel("Share", symbol: "square.and.arrow.up") }
                        Button { workspace.readAloud(message) } label: {
                            actionLabel(workspace.speech.messageID == message.id && workspace.speech.isSpeaking ? "Stop reading" : "Read aloud",
                                symbol: workspace.speech.messageID == message.id && workspace.speech.isSpeaking ? "speaker.slash" : "speaker.wave.2")
                        }
                        Button { workspace.branchConversation(at: message.id) } label: {
                            actionLabel("Branch from here", symbol: "arrow.triangle.branch")
                        }.disabled(!workspace.canStartResponse)
                        Spacer()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .buttonStyle(.plain).labelStyle(.iconOnly)
                    if let metrics = message.metrics, metrics.outputTokens > 0 {
                        HStack(spacing: 12) {
                            Text("\(metrics.outputTokens) tokens")
                            if metrics.tokensPerSecond > 0 { Text("\(metrics.tokensPerSecond, specifier: "%.1f") tok/s") }
                        }.font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    }
                }
                if message.role == .user {
                    HStack(spacing: 14) {
                        Button {
                            editedText = message.text
                            showsEditor = true
                        } label: { actionLabel("Edit and branch", symbol: "pencil") }
                        Button { workspace.branchConversation(at: message.id) } label: {
                            actionLabel("Branch from here", symbol: "arrow.triangle.branch")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).buttonStyle(.plain).labelStyle(.iconOnly)
                    .disabled(!workspace.canStartResponse)
                }
            }
            .padding(message.role == .user ? 18 : 0)
            .background {
                if message.role == .user { RoundedRectangle(cornerRadius: 22).fill(HushStyle.accent.opacity(0.085)) }
            }
            if message.role == .assistant { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .sheet(isPresented: $showsEditor) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Editing starts a new branch. Your original conversation and attachments are kept.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $editedText).font(.body).frame(minHeight: 180)
                        .padding(12).background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 16))
                    if !message.attachments.isEmpty {
                        Label("\(message.attachments.count) original attachments included", systemImage: "paperclip")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
                .navigationTitle("Edit message")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsEditor = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send edited branch") {
                            workspace.editMessage(message.id, text: editedText)
                            showsEditor = false
                        }
                        .disabled(!workspace.canStartResponse || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
            .frame(minWidth: 300, minHeight: 300)
            #if os(macOS)
            .frame(width: 600, height: 420)
            #endif
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
            .contentShape(.rect)
    }
}

struct MarkdownMessage: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(text.components(separatedBy: "```").enumerated()), id: \.offset) { index, section in
                if index.isMultiple(of: 2) {
                    if !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(.init(section)).font(.body).lineSpacing(5).textSelection(.enabled)
                    }
                } else {
                    let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
                    let language = String(lines.first ?? "")
                    let code = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(language.isEmpty ? "Code" : language).foregroundStyle(.secondary)
                            Spacer()
                            Button { copyText(code) } label: {
                                Label("Copy code", systemImage: "doc.on.doc")
                                    .frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
                            }.labelStyle(.iconOnly).buttonStyle(.plain)
                        }.font(.caption)
                        ScrollView(.horizontal) {
                            Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(.bottom, 3)
                        }
                    }.hushCard(padding: 16)
                }
            }
        }
    }
}

@MainActor
func copyText(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}
