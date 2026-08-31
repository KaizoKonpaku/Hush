#if os(iOS)
import Foundation
import FoundationModels
import UIKit
import WatchConnectivity

@MainActor
final class PhoneCompanion: NSObject, WCSessionDelegate {
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        guard let packet = try? CompanionPacket.decode(messageData) else { replyHandler(Data()); return }
        replyHandler(Data([1]))
        Task { @MainActor [weak self] in self?.receive(packet) }
    }

    private func receive(_ packet: CompanionPacket) {
        if packet.kind == .cancel {
            if requestID == packet.id { task?.cancel() }
            return
        }
        guard packet.kind == .request else { return }
        guard task == nil else {
            if requestID != packet.id { send(.init(id: packet.id, kind: .failure, text: "Another Watch response is running.")) }
            return
        }
        let prompt = packet.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 2000 else {
            send(.init(id: packet.id, kind: .failure, text: "Send a question of up to 2,000 characters."))
            return
        }
        requestID = packet.id
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Hush Watch response") { [weak self] in
            Task { @MainActor in self?.task?.cancel() }
        }
        task = Task {
            defer {
                task = nil
                requestID = nil
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            do {
                guard SystemLanguageModel.default.isAvailable else {
                    throw HushError.message("Apple Intelligence must be ready on your iPhone to use the Watch companion.")
                }
                let session = LanguageModelSession(model: SystemLanguageModel.default,
                    instructions: "Answer clearly and briefly for a small Apple Watch display. Use at most a short paragraph. Admit uncertainty.")
                var text = ""
                var lastUpdate = ContinuousClock.now
                for try await snapshot in session.streamResponse(to: prompt, options: GenerationOptions(maximumResponseTokens: 192)) {
                    try Task.checkCancellation()
                    text = snapshot.content
                    if lastUpdate.duration(to: .now) >= .milliseconds(200) {
                        send(.init(id: packet.id, kind: .update, text: text))
                        lastUpdate = .now
                    }
                }
                try Task.checkCancellation()
                send(.init(id: packet.id, kind: .finished, text: text))
            } catch {
                send(.init(id: packet.id, kind: .failure, text: Task.isCancelled ? "Stopped. Keep Hush open on your iPhone for longer responses." : error.localizedDescription))
            }
        }
    }

    private func send(_ packet: CompanionPacket) {
        guard WCSession.default.isReachable, let data = try? packet.encoded() else { task?.cancel(); return }
        WCSession.default.sendMessageData(data, replyHandler: nil) { [weak self] _ in
            Task { @MainActor in if self?.requestID == packet.id { self?.task?.cancel() } }
        }
    }
}
#endif
