import Observation
import SwiftUI
import WatchConnectivity

@main
struct HushWatchApp: App {
    @State private var companion = WatchCompanion()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            WatchChatView().environment(companion)
                .task { companion.activate() }
                .onChange(of: phase) { _, value in if value == .background { companion.stop() } }
        }
    }
}

@MainActor @Observable
final class WatchCompanion: NSObject, WCSessionDelegate {
    var prompt = ""
    var response = ""
    var error: String?
    var isReachable = false
    var isGenerating = false
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
        isReachable = WCSession.default.isReachable
    }

    func send() {
        guard !isGenerating else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= 2000 else { error = "Keep your question under 2,000 characters."; return }
        guard WCSession.default.isReachable else { error = "Open Hush on your paired iPhone and try again."; return }
        let packet = CompanionPacket(id: UUID(), kind: .request, text: text)
        guard let data = try? packet.encoded() else { return }
        requestID = packet.id
        isGenerating = true
        error = nil
        response = ""
        WCSession.default.sendMessageData(data, replyHandler: { _ in }, errorHandler: { [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in
                guard self?.requestID == packet.id else { return }
                self?.fail(message)
            }
        })
        timeout = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(45))
                guard let self, self.requestID == packet.id else { return }
                self.stop()
                self.error = "The iPhone didn't finish in time. Open Hush on iPhone and try again."
            } catch { }
        }
    }

    func stop() {
        if let requestID, let data = try? CompanionPacket(id: requestID, kind: .cancel).encoded(), WCSession.default.isReachable {
            WCSession.default.sendMessageData(data, replyHandler: { _ in }, errorHandler: nil)
        }
        timeout?.cancel()
        requestID = nil
        isGenerating = false
    }

    private func fail(_ message: String) {
        error = message
        timeout?.cancel()
        requestID = nil
        isGenerating = false
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in self?.isReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in self?.isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let packet = try? CompanionPacket.decode(messageData) else { return }
        Task { @MainActor [weak self] in
            guard let self, requestID == packet.id else { return }
            switch packet.kind {
            case .update: response = packet.text
            case .finished:
                response = packet.text
                requestID = nil
                isGenerating = false
                timeout?.cancel()
            case .failure: fail(packet.text)
            case .request, .cancel: break
            }
        }
    }
}

struct WatchChatView: View {
    @Environment(WatchCompanion.self) private var companion

    var body: some View {
        @Bindable var companion = companion
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle").foregroundStyle(.teal)
                    Text("hush").font(.system(size: 27, design: .serif))
                    Spacer()
                    Circle().fill(companion.isReachable ? .green : .secondary).frame(width: 5, height: 5)
                }
                Text("A thought away.").font(.system(size: 24, design: .serif))
                TextField("Ask Hush", text: $companion.prompt).disabled(companion.isGenerating)
                Button(companion.isGenerating ? "Stop" : "Ask iPhone", systemImage: companion.isGenerating ? "stop.fill" : "arrow.up") {
                    if companion.isGenerating { companion.stop() } else { companion.send() }
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .disabled(!companion.isGenerating && companion.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if companion.isGenerating && companion.response.isEmpty { ProgressView("Thinking on iPhone") }
                if !companion.response.isEmpty { Text(companion.response).font(.body) }
                if let error = companion.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Apple On-Device runs on your paired iPhone, not your Watch. No chat history is saved here.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
        }
    }
}
