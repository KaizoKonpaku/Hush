import SwiftUI

struct PreferencesView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var hubToken = ""
    @State private var hasToken = false
    @State private var tokenSaved = false

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section {
                HStack(spacing: 14) {
                    HushMark(size: 38)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Make yourself at home.").font(.system(size: 25, weight: .regular, design: .serif))
                        Text("Hush 2.0 / Native to OS 27").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            }
            Section("Appearance") {
                Picker("Theme", selection: $workspace.settings.appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Text("Native Liquid Glass follows your system's transparency, contrast, and motion preferences.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("On-device runtime") {
                Picker("Memory policy", selection: $workspace.settings.computePolicy) {
                    ForEach(ComputePolicy.allCases, id: \.self) { policy in Text(policy.title).tag(policy) }
                }.disabled(workspace.isGenerating)
                Toggle("Unload models after two minutes idle", isOn: $workspace.settings.unloadWhenIdle)
                Text(workspace.settings.computePolicy.explanation).font(.caption).foregroundStyle(.secondary)
            }
            Section("Responses") {
                Stepper("Maximum output: \(workspace.settings.maximumOutputTokens) tokens", value: $workspace.settings.maximumOutputTokens, in: 64...8192, step: 128)
                HStack {
                    Text("Temperature")
                    Slider(value: $workspace.settings.temperature, in: 0...2, step: 0.1)
                    Text(workspace.settings.temperature, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Instructions").font(.callout)
                    TextEditor(text: $workspace.settings.instructions).font(.system(size: 12))
                        .frame(minHeight: 110).scrollContentBackground(.hidden)
                        .padding(10).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
                    Text("Applied to new responses. Output length is also bounded by the selected model's context window.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            Section("Privacy") {
                Toggle("Save conversation history", isOn: $workspace.settings.keepHistory)
                Text("History is stored only on this device. Turning this off stops new changes from being saved; previously saved conversations are kept.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("No cloud inference, advertising, or analytics", systemImage: "lock.shield").font(.callout)
            }
            Section("Hugging Face") {
                Text("Public models need no account. For a gated model, accept its license on Hugging Face and add a read token. Tokens stay in this device's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField(hasToken ? "Token saved in Keychain" : "Read token (hf_...)", text: $hubToken)
                    .textFieldStyle(.roundedBorder).onSubmit { saveToken() }
                HStack {
                    Button(tokenSaved ? "Saved" : "Save token") { saveToken() }.disabled(hubToken.isEmpty)
                    if hasToken {
                        Button("Remove token", role: .destructive) {
                            do { try HubCredential.save(""); hasToken = false; hubToken = ""; tokenSaved = false }
                            catch { workspace.showError(error) }
                        }
                    }
                    Spacer()
                    Link("Read tokens", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                }
            }
            Section("Made with Apple's native tools") {
                Link("WWDC26: Foundation Models", destination: URL(string: "https://developer.apple.com/videos/play/wwdc2026/241/")!)
                Link("Apple Core AI model recipes", destination: URL(string: "https://github.com/apple/coreai-models")!)
                Link("MLX Swift language models", destination: URL(string: "https://github.com/ml-explore/mlx-swift-lm")!)
                Text("Apple on-device model availability depends on hardware, language, region, and system settings. Open models also depend on supported architectures and available memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(HushStyle.accent)
        .preferredColorScheme(workspace.settings.appearance == "system" ? nil : workspace.settings.appearance == "dark" ? .dark : .light)
        .onAppear { hasToken = HubCredential.load() != nil }
        .onChange(of: workspace.settings) { workspace.savePreferences() }
        .onChange(of: hubToken) { tokenSaved = false }
    }

    private func saveToken() {
        do {
            try HubCredential.save(hubToken)
            hubToken = ""
            hasToken = true
            tokenSaved = true
        } catch { workspace.showError(error) }
    }
}
