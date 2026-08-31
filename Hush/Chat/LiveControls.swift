import SwiftUI

struct LiveVoiceButton: View {
    @Environment(WorkspaceModel.self) private var workspace
    var body: some View {
        Button(workspace.liveVoice.isActive ? "End live voice" : "Start live voice",
               systemImage: workspace.liveVoice.isActive ? "phone.down" : "waveform.circle") {
            workspace.toggleLiveVoice()
        }
        .labelStyle(.iconOnly)
        .tint(workspace.liveVoice.isActive ? .red : HushStyle.accent)
        .disabled(!workspace.liveVoice.isActive && !workspace.canStartResponse)
        .help(workspace.liveVoice.isActive ? "End the on-device voice conversation" : "Start a hands-free on-device voice conversation")
    }
}

struct LiveVoiceBar: View {
    @Environment(WorkspaceModel.self) private var workspace
    var body: some View {
        HStack(spacing: 12) {
            VoiceMeter(level: workspace.liveVoice.level, muted: workspace.liveVoice.isMuted)
                .frame(width: 32, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.liveVoice.status).font(.caption.weight(.medium))
                Text(workspace.liveVoice.caption.isEmpty ? "On device. Speak naturally; pause to send." : workspace.liveVoice.caption)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if workspace.liveVoice.phase == .speaking || workspace.liveVoice.phase == .thinking {
                Button("Interrupt response", systemImage: "stop.fill") { workspace.stop() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
            }
            Button("End live voice", systemImage: "phone.down.fill") { workspace.stopLiveInputs() }
                .labelStyle(.iconOnly).nativeGlassButton().buttonBorderShape(.circle).tint(.red)
        }
        .frame(minHeight: 48).padding(.horizontal, 6)
    }
}

private struct VoiceMeter: View {
    let level: Double
    let muted: Bool
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Capsule().fill(muted ? Color.secondary : HushStyle.accent)
                    .frame(width: 3, height: muted ? 3 : 4 + CGFloat(level) * CGFloat([10, 17, 24, 17, 10][index]))
            }
        }.frame(width: 32, height: 26)
    }
}

struct SpeechPlaybackBar: View {
    @Environment(WorkspaceModel.self) private var workspace
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2").foregroundStyle(HushStyle.accent)
            Text(workspace.speech.isPaused ? "Reading paused" : "Reading aloud")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(workspace.speech.isPaused ? "Resume reading" : "Pause reading",
                   systemImage: workspace.speech.isPaused ? "play.fill" : "pause.fill") { workspace.speech.togglePause() }
                .frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
            Button("Stop reading", systemImage: "stop.fill") { workspace.speech.stop() }
                .frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
        }
        .buttonStyle(.borderless).labelStyle(.iconOnly).padding(.horizontal, 6)
    }
}

struct LiveCaptureBar: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var showsPreview = false
    var body: some View {
        HStack(spacing: 12) {
            Button { showsPreview = true } label: {
                preview.frame(width: 72, height: 52).clipShape(.rect(cornerRadius: 10))
            }.buttonStyle(.plain).accessibilityLabel("Expand live preview")
            VStack(alignment: .leading, spacing: 3) {
                Label(workspace.capture.title, systemImage: "record.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(HushStyle.accent)
                Text(workspace.capture.isStarting ? "Waiting for your permission" : "Latest frame is included with each question.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            #if os(iOS)
            if workspace.capture.source == .camera {
                Button("Switch camera", systemImage: "arrow.triangle.2.circlepath.camera") { workspace.capture.flipCamera() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .frame(minWidth: HushStyle.minimumHitSize, minHeight: HushStyle.minimumHitSize)
            }
            #endif
            Button("Stop visual sharing", systemImage: "xmark") { workspace.capture.stop() }
                .labelStyle(.iconOnly).nativeGlassButton().buttonBorderShape(.circle)
        }
        .padding(.horizontal, 6)
        .sheet(isPresented: $showsPreview) {
            NavigationStack {
                VStack(spacing: 20) {
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(.rect(cornerRadius: 20))
                    Text("Preview frames stay in memory. Only a frame sent with a question becomes a local chat attachment. Your history setting controls whether the conversation is retained.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Stop sharing", role: .destructive) {
                        workspace.capture.stop()
                        showsPreview = false
                    }.nativeGlassButton()
                }.padding(24)
                .navigationTitle(workspace.capture.title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Close") { showsPreview = false } }
                }
            }
            .frame(minWidth: 300, minHeight: 300)
            #if os(macOS)
            .frame(idealWidth: 760, idealHeight: 580)
            #endif
        }
    }

    @ViewBuilder private var preview: some View {
        if let image = workspace.capture.frame?.image {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
            ZStack {
                Color.secondary.opacity(0.08)
                ProgressView().controlSize(.small)
            }
        }
    }
}
