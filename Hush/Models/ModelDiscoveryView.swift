import SwiftUI

struct ModelDiscoveryView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var detail: ModelRecord?
    @State private var visionOnly = false
    @State private var refreshID = 0

    private var models: [ModelRecord] { workspace.catalog.filter { !visionOnly || $0.supportsVision } }

    var body: some View {
        @Bindable var workspace = workspace
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "The model explorer")
                    Text("Open possibilities.\nLocal intelligence.")
                        .font(.system(size: 39, weight: .regular, design: .serif)).tracking(-1.2)
                    Text("Find a model that feels right for your device and the way you think.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(.top, 12)

                NativeGlassGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search Hugging Face models", text: $workspace.modelSearch)
                            .textFieldStyle(.plain).font(.system(size: 15))
                            .accessibilityLabel("Search Hugging Face models")
                        if !workspace.modelSearch.isEmpty {
                            Button("Clear search", systemImage: "xmark.circle.fill") { workspace.modelSearch = "" }
                                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.tertiary)
                        }
                        if workspace.isSearching { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .nativeGlass(in: .capsule)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { filters; Spacer(); sortPicker }
                    VStack(alignment: .leading, spacing: 12) { HStack(spacing: 8) { filters }; sortPicker }
                }

                if let error = workspace.catalogError {
                    ContentUnavailableView {
                        Label("Couldn't reach the model catalog", systemImage: "wifi.slash")
                    } description: { Text(error) } actions: {
                        Button("Try again") { refreshID += 1 }.nativeGlassButton()
                    }
                } else if workspace.isSearching && workspace.catalog.isEmpty {
                    ProgressView("Finding local models...").frame(maxWidth: .infinity, minHeight: 200)
                } else if models.isEmpty {
                    ContentUnavailableView.search(text: workspace.modelSearch)
                } else {
                    HStack {
                        Eyebrow(text: workspace.modelSearch.isEmpty ? "From the community" : "Search results")
                        Spacer()
                        Text("\(models.count) models").font(.caption).foregroundStyle(.tertiary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245, maximum: 420), spacing: 16)], spacing: 16) {
                        ForEach(models) { model in
                            ModelCard(model: installedVersion(model)) { detail = installedVersion(model) }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Search and downloads connect to Hugging Face. Conversations run locally. Model compatibility, license terms, and memory needs vary.")
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
            }
            .frame(maxWidth: 1120).padding(30).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if workspace.download != nil { DownloadProgressView().padding(.horizontal, 24).padding(.bottom, 16) }
        }
        .task(id: "\(workspace.modelSearch)|\(workspace.modelSort)|\(refreshID)") { await workspace.searchModels() }
        .sheet(item: $detail) { model in ModelDetailView(model: model) }
    }

    private var filters: some View {
        Group {
            Button("All models") { workspace.modelSearch = ""; visionOnly = false }
                .nativeGlassButton()
            Button("Start small") { workspace.modelSearch = "Qwen3-0.6B"; visionOnly = false }
                .nativeGlassButton()
            Toggle(isOn: $visionOnly) { Label("Vision", systemImage: "eye") }
                .toggleStyle(.button).nativeGlassButton()
        }.font(.system(size: 11, weight: .medium))
    }

    private var sortPicker: some View {
        @Bindable var workspace = workspace
        return Picker("Sort", selection: $workspace.modelSort) {
            Text("Most downloaded").tag("downloads")
            Text("Most liked").tag("likes")
            Text("Recently updated").tag("lastModified")
        }
        .pickerStyle(.menu).labelsHidden().fixedSize()
        .accessibilityLabel("Sort models")
    }

    private func installedVersion(_ model: ModelRecord) -> ModelRecord {
        workspace.installedModels.first { $0.id == model.id } ?? model
    }
}

struct ModelCard: View {
    let model: ModelRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ModelGlyph(model: model)
                    Spacer()
                    if model.isInstalled { Image(systemName: "checkmark.circle.fill").foregroundStyle(HushStyle.accent) }
                    else { Image(systemName: "arrow.down").foregroundStyle(.tertiary) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name).font(.system(size: 15, weight: .medium)).lineLimit(2).frame(height: 38, alignment: .top)
                    Text(model.author).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    CapabilityBadge(title: model.engine.title)
                    if let quantization = model.quantization { CapabilityBadge(title: quantization) }
                    if model.supportsVision { CapabilityBadge(title: "Vision", symbol: "eye") }
                }
                HStack {
                    if let size = model.sizeBytes { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                    else if model.downloads > 0 {
                        Label(model.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.to.line")
                    } else { Text(model.engine == .apple ? "Included with your device" : "View model") }
                    Spacer()
                    if let license = model.license { Text(license.uppercased()).lineLimit(1) }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hushCard()
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.name), \(model.engine.title), \(model.isInstalled ? "installed" : "view download details")")
    }
}

struct DownloadProgressView: View {
    @Environment(WorkspaceModel.self) private var workspace
    var compact = false
    var body: some View {
        if let download = workspace.download {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: download.phase == .complete ? "checkmark.circle" : "arrow.down.circle")
                        .foregroundStyle(HushStyle.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(download.phase == .complete ? "Model ready to use" : download.modelID.components(separatedBy: "/").last ?? download.modelID)
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if !compact {
                            Text(download.error ?? (download.phase == .paused ? "Paused. Reopen the model to resume verified files." : download.filename))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    if download.isActive {
                        Button("Pause download", systemImage: "pause.fill") { workspace.pauseDownload() }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                    } else {
                        Button("Dismiss", systemImage: "xmark") { workspace.download = nil }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                if download.isActive {
                    ProgressView(value: download.fraction).tint(HushStyle.accent)
                    if !compact {
                        Text("\(ByteCountFormatter.string(fromByteCount: download.completedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: download.totalBytes, countStyle: .file))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(compact ? 0 : 16)
            .frame(maxWidth: compact ? .infinity : 700)
            .background {
                if !compact { RoundedRectangle(cornerRadius: 22).fill(.clear).nativeGlass(in: .rect(cornerRadius: 22)) }
            }
        }
    }
}
