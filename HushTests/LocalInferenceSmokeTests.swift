import Foundation
import FoundationModels
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Hush

@Suite(.serialized)
struct LocalInferenceSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUSH_RUN_MODEL_SMOKE"] == "1"), .timeLimit(.minutes(10)))
    func downloadsVerifiedModelAndGeneratesLocally() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Hush-Model-Validation")
        let store = LibraryStore(root: root)
        let installed = try await store.installedModels()
        let model: ModelRecord
        if let existing = installed.first(where: { $0.id == "mlx-community/Qwen3-0.6B-4bit" }) {
            model = existing
        } else {
            let hub = HuggingFaceClient()
            let results = try await hub.search("Qwen3-0.6B-4bit")
            let found = try #require(results.first { $0.id == "mlx-community/Qwen3-0.6B-4bit" })
            let manifest = try await hub.manifest(for: found)
            model = try await ModelInstaller(root: root).download(manifest, token: nil) { _ in }
        }
        let folder = try #require(model.installedDirectory)
        let directory = try ModelPath.resolve(folder, under: root.appending(path: "Models"))
        let runtime = InferenceRuntime()
        var settings = HushSettings()
        settings.temperature = 0
        settings.maximumOutputTokens = 64
        let conversationID = UUID()
        let prompt = "What is two plus two? Reply briefly."
        let first = SmokeEvents()
        let request = GenerationRequest(conversationID: conversationID, model: model, modelDirectory: directory,
            history: [], prompt: prompt, attachments: [], attachmentDirectory: root.appending(path: "Attachments"),
            settings: settings, memoryBudget: 4 * 1024 * 1024 * 1024)
        try await runtime.generate(request) { await first.receive($0) }
        let text = await first.text
        let metrics = try #require(await first.metrics)
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(metrics.outputTokens > 0)
        #expect(metrics.inputTokens > 0)
        #expect(metrics.peakMemoryBytes > 0)

        let second = SmokeEvents()
        let continuation = GenerationRequest(conversationID: conversationID, model: model, modelDirectory: directory,
            history: [ChatMessage(role: .user, text: prompt), ChatMessage(role: .assistant, text: text)],
            prompt: "Now add one to that number. Reply briefly.", attachments: [], attachmentDirectory: root.appending(path: "Attachments"),
            settings: settings, memoryBudget: request.memoryBudget)
        try await runtime.generate(continuation) { await second.receive($0) }
        #expect(await second.metrics?.cachedTokens ?? 0 > 0)
        #expect(await second.metrics?.outputTokens ?? 0 > 0)
        print("MLX smoke test: \(metrics.outputTokens) output tokens, \(metrics.tokensPerSecond.formatted()) tokens/s; second-turn cached tokens: \(await second.metrics?.cachedTokens ?? 0)")

        var longSettings = settings
        longSettings.maximumOutputTokens = 512
        let interrupted = SmokeEvents()
        let longRequest = GenerationRequest(conversationID: UUID(), model: model, modelDirectory: directory,
            history: [], prompt: "Write a numbered list of 200 detailed ideas for a garden. Keep going until the list is finished.",
            attachments: [], attachmentDirectory: request.attachmentDirectory, settings: longSettings, memoryBudget: request.memoryBudget)
        let task = Task {
            try await runtime.generate(longRequest) { await interrupted.receive($0) }
        }
        for _ in 0..<6000 {
            if await !interrupted.text.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("The long model response completed before cancellation was exercised.")
        } catch is CancellationError { }
        #expect(await !interrupted.text.isEmpty)
        #expect(await interrupted.metrics == nil)

        let restarted = SmokeEvents()
        try await runtime.generate(request) { await restarted.receive($0) }
        #expect(await !restarted.text.isEmpty)
        #expect(await restarted.metrics?.outputTokens ?? 0 > 0)
        print("MLX cancellation and immediate restart passed.")
        await runtime.unload()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUSH_RUN_MODEL_SMOKE"] == "1"
                   && SystemLanguageModel.default.isAvailable), .timeLimit(.minutes(3)))
    func appleFoundationModelGeneratesOnDevice() async throws {
        let runtime = InferenceRuntime()
        let events = SmokeEvents()
        var settings = HushSettings()
        settings.maximumOutputTokens = 64
        let request = GenerationRequest(conversationID: UUID(), model: .apple, modelDirectory: nil,
            history: [], prompt: "What is two plus two? Reply briefly.", attachments: [],
            attachmentDirectory: FileManager.default.temporaryDirectory, settings: settings,
            memoryBudget: 4 * 1024 * 1024 * 1024)
        try await runtime.generate(request) { await events.receive($0) }
        #expect(await !events.text.isEmpty)
        #expect(await events.metrics?.outputTokens ?? 0 > 0)
        print("Apple Foundation Models on-device generation passed.")
        await runtime.unload()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUSH_RUN_MODEL_SMOKE"] == "1"
                   && SystemLanguageModel.default.isAvailable), .timeLimit(.minutes(3)))
    func appleVisionUnderstandsAnImportedLiveFrame() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try #require(CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8,
            bytesPerRow: 1280 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let directory = root.appending(path: "Attachments")
        let attachment = try await AttachmentImporter(root: directory).importCapturedImage(bytes as Data, name: "Test live frame")
        var settings = HushSettings()
        settings.maximumOutputTokens = 64
        let runtime = InferenceRuntime()
        let events = SmokeEvents()
        let request = GenerationRequest(conversationID: UUID(), model: .apple, modelDirectory: nil,
            history: [], prompt: "What is the main color of this image? Answer with the color name.",
            attachments: [attachment], attachmentDirectory: directory, settings: settings,
            memoryBudget: 4 * 1024 * 1024 * 1024)
        try await runtime.generate(request) { await events.receive($0) }
        #expect(await events.text.localizedCaseInsensitiveContains("red"))
        #expect(await events.metrics?.outputTokens ?? 0 > 0)
        print("Apple live-frame vision passed: \(await events.text)")
        let followUp = SmokeEvents()
        let continuation = GenerationRequest(conversationID: request.conversationID, model: .apple, modelDirectory: nil,
            history: [ChatMessage(role: .user, text: request.prompt, attachments: [attachment]),
                      ChatMessage(role: .assistant, text: await events.text)],
            prompt: "What color was the image in my previous message? Answer with the color name.",
            attachments: [], attachmentDirectory: directory, settings: settings, memoryBudget: request.memoryBudget)
        try await runtime.generate(continuation) { await followUp.receive($0) }
        #expect(await followUp.text.localizedCaseInsensitiveContains("red"))
        #expect(await followUp.metrics?.outputTokens ?? 0 > 0)
        print("Apple vision follow-up with image history passed.")
        await runtime.unload()
    }
}

private actor SmokeEvents {
    var text = ""
    var metrics: GenerationMetrics?
    func receive(_ event: GenerationEvent) {
        switch event {
        case .snapshot(let text): self.text = text
        case .completed(let metrics): self.metrics = metrics
        case .status: break
        }
    }
}
