import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var detail: ModelRecord?
    @State private var showsImporter = false
    @State private var modelToRemove: ModelRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Your collection")
                        Text("Intelligence, kept close.").font(.system(size: 36, weight: .regular, design: .serif)).tracking(-1)
                        Text("Everything here runs on your device. No API keys. No per-token bill.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button { showsImporter = true } label: { Image(systemName: "square.and.arrow.down").frame(width: 30, height: 30) }
                        .nativeGlassButton().buttonBorderShape(.circle).accessibilityLabel("Import a Core AI model bundle")
                }

                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        ModelGlyph(model: .apple, size: 50)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Apple On-Device").font(.system(size: 18, weight: .medium))
                            Text(workspace.appleIsReady ? "Built into OS 27. Ready when you are." : InferenceRuntime.appleAvailabilityMessage)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack {
                        CapabilityBadge(title: "Included", symbol: "apple.logo")
                        CapabilityBadge(title: "Vision", symbol: "eye")
                        Spacer()
                        Button("Use model") { workspace.selectModel(.apple); workspace.page = .chat }
                            .nativeGlassButton().disabled(!workspace.appleIsReady)
                    }
                }.hushCard(padding: 24)

                HStack {
                    Eyebrow(text: "Downloaded & imported")
                    Spacer()
                    Text("\(workspace.installedModels.count) models").font(.caption).foregroundStyle(.secondary)
                }
                if workspace.installedModels.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(HushStyle.accent)
                        Text("Make room for a new mind.").font(.system(size: 24, weight: .regular, design: .serif))
                        Text("Download an MLX model from Hugging Face, or import a Core AI bundle exported with Apple's model tools.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Discover models", systemImage: "magnifyingglass") { workspace.page = .discover }.nativeGlassButton(prominent: true)
                            Button("Import Core AI") { showsImporter = true }.nativeGlassButton()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).hushCard(padding: 28)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 16)], spacing: 16) {
                        ForEach(workspace.installedModels) { model in
                            ModelCard(model: model) { detail = model }
                                .contextMenu {
                                    Button("Use model", systemImage: "bubble.left") { workspace.selectModel(model); workspace.page = .chat }
                                    Button("Remove download", systemImage: "trash", role: .destructive) { modelToRemove = model }
                                }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Go deeper with Core AI")
                    Text("Apple's open model recipes target the CPU, GPU, or Neural Engine. Export a language-model bundle with its tokenizer, then import it here. The bundle determines which acceleration is available.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Link("Explore Apple's Core AI models", destination: URL(string: "https://github.com/apple/coreai-models")!)
                        .font(.callout)
                }.padding(.top, 6)
                if workspace.isRemovingModel { ProgressView("Removing model files...") }
                else if workspace.isImporting { ProgressView("Importing model files...") }
            }
            .frame(maxWidth: 1040).padding(30).frame(maxWidth: .infinity)
        }
        .sheet(item: $detail) { ModelDetailView(model: $0) }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await workspace.importCoreAI(url) }
            case .failure(let error): workspace.showError(error)
            }
        }
        .confirmationDialog("Remove this model from the device?", isPresented: Binding(get: { modelToRemove != nil }, set: { if !$0 { modelToRemove = nil } })) {
            Button("Remove download", role: .destructive) {
                if let model = modelToRemove { Task { await workspace.removeModel(model) } }
                modelToRemove = nil
            }
        } message: { Text("Conversations are kept. You can download the model again later.") }
    }
}
