import Charts
import FoundationModels
import SwiftUI

struct RuntimeView: View {
    @Environment(WorkspaceModel.self) private var workspace
    private var samples: [GenerationMetrics] {
        Array(workspace.conversations.flatMap(\.messages).sorted { $0.createdAt < $1.createdAt }.compactMap(\.metrics).suffix(20))
    }

    var body: some View {
        @Bindable var workspace = workspace
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Made for this machine")
                    Text("Every bit of possibility.").font(.system(size: 37, weight: .regular, design: .serif)).tracking(-1.1)
                    Text("A clear view of your hardware, your memory, and every local response.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    MetricTile(title: "APPLE SILICON", value: workspace.hardware.chipName, symbol: "cpu")
                    MetricTile(title: "UNIFIED MEMORY", value: HardwareMonitor.bytes(Int64(workspace.hardware.physicalMemory)), symbol: "memorychip")
                    MetricTile(title: "CPU CORES", value: "\(workspace.hardware.processorCount)", symbol: "square.grid.3x3")
                    MetricTile(title: "THERMAL STATE", value: workspace.hardware.thermalState, symbol: "thermometer.medium")
                }
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Give your model room.").font(.system(size: 23, weight: .regular, design: .serif))
                            Text("Memory policy").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(HardwareMonitor.bytes(Int64(workspace.hardware.budget(for: workspace.settings.computePolicy))))
                            .font(.system(size: 24, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Picker("Compute policy", selection: $workspace.settings.computePolicy) {
                        ForEach(ComputePolicy.allCases, id: \.self) { policy in Text(policy.title).tag(policy) }
                    }.pickerStyle(.segmented).disabled(workspace.isGenerating)
                    Text(workspace.settings.computePolicy.explanation).font(.callout).foregroundStyle(.secondary)
                    Gauge(value: Double(workspace.hardware.activeModelMemory), in: 0...Double(max(1, workspace.hardware.budget(for: workspace.settings.computePolicy)))) {
                        Text("MLX active allocations")
                    } currentValueLabel: {
                        Text(HardwareMonitor.bytes(Int64(workspace.hardware.activeModelMemory)))
                    }.tint(HushStyle.accent)
                    HStack {
                        Text("Metal recommended limit: \(HardwareMonitor.bytes(Int64(workspace.hardware.recommendedWorkingSet)))")
                        Spacer()
                        if workspace.hardware.isLowPowerMode { Label("Low Power Mode", systemImage: "battery.25") }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.hushCard(padding: 26)

                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Real work. Real numbers.").font(.system(size: 23, weight: .regular, design: .serif))
                        Spacer()
                        if workspace.isGenerating { ProgressView().controlSize(.small) }
                    }
                    if samples.isEmpty {
                        Text("Send a message to measure output tokens, time to first token, and generation speed. No simulated benchmarks.")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
                    } else {
                        Chart(Array(samples.enumerated()), id: \.offset) { index, sample in
                            BarMark(x: .value("Response", index + 1), y: .value("Tokens per second", sample.tokensPerSecond))
                                .foregroundStyle(HushStyle.accent.gradient).cornerRadius(5)
                        }
                        .chartXAxis(.hidden).chartYAxisLabel("tokens / second")
                        .frame(height: 140)
                        if let metrics = workspace.lastMetrics { GenerationMetricsRow(metrics: metrics) }
                    }
                }.hushCard(padding: 26)

                VStack(alignment: .leading, spacing: 21) {
                    Eyebrow(text: "Native engines")
                    engine("Foundation Models", subtitle: "The OS 27 model, vision input, token accounting, and context-aware streaming. Apple manages its hardware scheduling.", symbol: "apple.intelligence")
                    engine("MLX + Metal", subtitle: "Quantized open models use the GPU and unified memory. MLX selects device-supported Metal kernels. Neural Engine model variants run through Core AI.", symbol: "square.3.layers.3d")
                    engine("Core AI", subtitle: "Apple's exported models select CPU, GPU, or Neural Engine through their compiled variant. Hush does not claim to force every processor at once.", symbol: "cpu")
                }.hushCard(padding: 26)
            }
            .frame(maxWidth: 1040).padding(30).frame(maxWidth: .infinity)
        }
        .onChange(of: workspace.settings) { workspace.savePreferences() }
    }

    private func engine(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(HushStyle.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: symbol).foregroundStyle(HushStyle.accent); Spacer(); Eyebrow(text: title) }
            Text(value).font(.system(size: 22, weight: .regular, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading).hushCard(padding: 20)
    }
}

struct GenerationMetricsRow: View {
    let metrics: GenerationMetrics
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            metric("Output", value: "\(metrics.outputTokens) tokens")
            metric("First token", value: metrics.timeToFirstToken.map { String(format: "%.2fs", $0) } ?? "Not reported")
            metric("Elapsed", value: String(format: "%.2fs", metrics.duration))
            Spacer(minLength: 0)
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

struct RuntimeInspector: View {
    @Environment(WorkspaceModel.self) private var workspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Eyebrow(text: "On this device")
                VStack(alignment: .leading, spacing: 14) {
                    ModelGlyph(model: workspace.selectedModel, size: 52)
                    Text(workspace.selectedModel.name).font(.system(size: 23, weight: .regular, design: .serif))
                    Text(workspace.selectedModel.engine.hardware).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                inspectorRow("Engine", value: workspace.selectedModel.engine.title)
                inspectorRow("Device", value: workspace.hardware.chipName)
                inspectorRow("Memory budget", value: HardwareMonitor.bytes(Int64(workspace.hardware.budget(for: workspace.settings.computePolicy))))
                inspectorRow("MLX active", value: HardwareMonitor.bytes(Int64(workspace.hardware.activeModelMemory)))
                inspectorRow("Thermal", value: workspace.hardware.thermalState)
                if workspace.selectedModel.engine == .apple { inspectorRow("Context window", value: "\(SystemLanguageModel.default.contextSize) tokens") }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Local by design", systemImage: "lock.shield").font(.system(size: 13, weight: .medium))
                    Text("Your prompts and attachments stay here. Only model discovery and downloads need a network connection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let metrics = workspace.lastMetrics {
                    Divider()
                    Eyebrow(text: "Last response")
                    inspectorRow("Input", value: "\(metrics.inputTokens) tokens")
                    inspectorRow("Output", value: "\(metrics.outputTokens) tokens")
                    inspectorRow("Speed", value: String(format: "%.1f tok/s", metrics.tokensPerSecond))
                    if metrics.peakMemoryBytes > 0 { inspectorRow("Peak MLX memory", value: HardwareMonitor.bytes(Int64(metrics.peakMemoryBytes))) }
                }
                Button("Unload model", systemImage: "eject") { Task { await workspace.unloadModel() } }
                    .nativeGlassButton().disabled(workspace.isGenerating || workspace.loadedModelName == nil)
                Text("Idle models unload after two minutes when enabled. The system model is managed by the OS.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(24)
        }
    }
    private func inspectorRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }
            .font(.system(size: 11))
    }
}
