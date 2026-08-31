import SwiftUI

struct ModelDetailView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let model: ModelRecord
    @State private var manifest: ModelManifest?
    @State private var failure: String?
    @State private var loading = false

    private var installed: ModelRecord? { workspace.availableModels.first { $0.id == model.id } }
    private var displayModel: ModelRecord { installed ?? manifest?.model ?? model }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(alignment: .top, spacing: 15) {
                        ModelGlyph(model: displayModel, size: 60)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(displayModel.name).font(.system(size: 25, weight: .regular, design: .serif))
                            Text(displayModel.author).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Text(displayModel.summary).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        CapabilityBadge(title: displayModel.engine.title)
                        if displayModel.supportsVision { CapabilityBadge(title: "Vision", symbol: "eye") }
                        if let quantization = displayModel.quantization { CapabilityBadge(title: quantization) }
                    }
                    VStack(spacing: 15) {
                        detailRow("Execution", value: "On this device", symbol: "lock.shield")
                        detailRow("Acceleration", value: displayModel.engine.hardware, symbol: "cpu")
                        if let size = displayModel.sizeBytes {
                            detailRow("Download size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file), symbol: "internaldrive")
                        }
                        if let parameters = displayModel.parameterLabel { detailRow("Parameters", value: parameters, symbol: "square.stack.3d.up") }
                        if let license = displayModel.license { detailRow("License", value: license, symbol: "doc.text") }
                    }.hushCard()

                    if let size = displayModel.sizeBytes,
                       size + max(768 * 1024 * 1024, size / 4) >= Int64(workspace.hardware.budget(for: workspace.settings.computePolicy)) {
                        Label("This model may not fit your current memory budget. Try a smaller quantization or adjust the runtime policy before running it.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(HushStyle.amber)
                    }
                    if let failure {
                        Text(failure).font(.callout).foregroundStyle(.secondary)
                        Button("Retry model lookup") { Task { await inspect() } }.nativeGlassButton()
                    }
                    if loading { ProgressView("Checking files, size, and revision...").font(.callout) }
                    if let revision = manifest?.revision ?? displayModel.revision {
                        VStack(alignment: .leading, spacing: 7) {
                            Eyebrow(text: installed == nil ? "Pinned revision" : "Verified installation")
                            Text("Revision \(revision.prefix(12))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            Text("Safe tensor files only. Weight checksums are verified before installation. Completed files are kept if a download is paused.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let url = displayModel.repositoryURL {
                        Link(destination: url) { Label("Model card & license on Hugging Face", systemImage: "arrow.up.right") }
                            .font(.callout)
                    }
                }.padding(28)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let installed {
                        Button {
                            workspace.selectModel(installed)
                            workspace.page = .chat
                            dismiss()
                        } label: { Label("Use this model", systemImage: "bubble.left").frame(maxWidth: .infinity).padding(8) }
                        .nativeGlassButton(prominent: true)
                    } else if workspace.download?.modelID == model.id && workspace.download?.isActive == true {
                        DownloadProgressView()
                    } else {
                        Button {
                            if let manifest { workspace.install(manifest) }
                        } label: {
                            Label(manifest.map { "Download \(ByteCountFormatter.string(fromByteCount: $0.totalBytes, countStyle: .file))" } ?? "Download model", systemImage: "arrow.down")
                                .frame(maxWidth: .infinity).padding(8)
                        }
                        .nativeGlassButton(prominent: true)
                        .disabled(manifest == nil || workspace.download?.isActive == true)
                    }
                }.padding(24)
            }
            .navigationTitle("Model details")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(HushStyle.accent)
        #if os(macOS)
        .frame(width: 560, height: 690)
        #endif
        .task { await inspect() }
    }

    private func inspect() async {
        guard model.engine == .mlx, !model.isInstalled else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            manifest = try await workspace.hub.manifest(for: model, token: HubCredential.load())
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }

    private func detailRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top) {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer(minLength: 20)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.system(size: 12))
    }
}
