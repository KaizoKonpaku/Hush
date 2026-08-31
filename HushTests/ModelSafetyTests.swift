import CryptoKit
import Foundation
import Testing
@testable import Hush

struct ModelSafetyTests {
    @Test(arguments: ["../model", "author/../model", "https://huggingface.co/a/b", "a/b?token=secret", "a/b#tag", "a/", "/b", "a/b\\c"])
    func rejectsInvalidRepositoryIDs(_ id: String) {
        #expect(throws: HushError.self) { try ModelPath.validateRepositoryID(id) }
    }

    @Test(arguments: ["../escape", "/absolute", "weights/../../secret", "weights//file", "weights/./file", "C:\\file", "%2e%2e/secret", "a\0b"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(throws: HushError.self) { try ModelPath.resolve(path, under: URL(fileURLWithPath: "/tmp/hush-test")) }
    }

    @Test func cannotFollowSymlinkOutsideModel() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "outside"), withDestinationURL: root.deletingLastPathComponent())
        #expect(throws: HushError.self) { try ModelPath.resolve("outside/secret", under: root) }
    }

    @Test func verifiesBytesBeforeInstallation() throws {
        let bytes = Data("verified tensor bytes".utf8)
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let expected = ModelFile(path: "model.safetensors", size: Int64(bytes.count), sha256: digest, gitBlobID: nil)
        try ModelInstaller.verify(file, file: expected)
        try Data("corrupted model bytes".utf8).write(to: file)
        #expect(throws: HushError.self) { try ModelInstaller.verify(file, file: expected) }
    }

    @Test func rejectsFilesWithoutIntegrityMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: HushError.self) {
            try ModelInstaller.verify(url, file: ModelFile(path: "config.json", size: 1, sha256: nil, gitBlobID: nil))
        }
    }

    @Test func neverIncludesRemoteCode() {
        for name in ["model.py", "pytorch_model.bin", "weights.pkl", "install.sh", "evil.dylib"] {
            #expect(!ModelPath.isAllowedModelFile(name))
        }
        #expect(ModelPath.isAllowedModelFile("model-00001-of-00002.safetensors"))
        #expect(ModelPath.isAllowedModelFile("tokenizer.json"))
    }

    @Test func settingsCannotIntroduceInvalidGenerationParameters() {
        var settings = HushSettings()
        settings.temperature = .nan
        settings.maximumOutputTokens = Int.max
        settings.appearance = "invalid"
        settings.validate()
        #expect(settings.temperature == 0.7)
        #expect(settings.maximumOutputTokens == 8192)
        #expect(settings.appearance == "system")
    }

    @Test func sixteenBitModelsAreNotMislabeledAsSixBit() {
        let model = ModelRecord(id: "example/model-16bit", name: "Model", author: "Example", engine: .mlx, summary: "")
        #expect(model.quantization == "16-bit")
    }

    @Test func coreAIImportRequiresAnEntireLocalBundle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try FileManager.default.createDirectory(at: source.appending(path: "tokenizer"), withIntermediateDirectories: true)
        let metadata: [String: Any] = ["kind": "llm", "language": ["embedded_tokenizer": true],
                                       "assets": ["main": "model.aimodel"]]
        try JSONSerialization.data(withJSONObject: metadata).write(to: source.appending(path: "metadata.json"))
        let installer = ModelInstaller(root: root.appending(path: "library"))
        await #expect(throws: HushError.self) { try await installer.importCoreAI(from: source) }
        try Data("{}".utf8).write(to: source.appending(path: "tokenizer/tokenizer.json"))
        try Data("{}".utf8).write(to: source.appending(path: "tokenizer/tokenizer_config.json"))
        await #expect(throws: HushError.self) { try await installer.importCoreAI(from: source) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "library/Models").path))
    }

    @Test func coreAIImportRejectsSymlinkedTokenizer() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        let outside = root.appending(path: "outside")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: outside.appending(path: "tokenizer.json"))
        try Data("{}".utf8).write(to: outside.appending(path: "tokenizer_config.json"))
        try FileManager.default.createSymbolicLink(at: source.appending(path: "tokenizer"), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: source.appending(path: "model.aimodel"), withIntermediateDirectories: true)
        let metadata: [String: Any] = ["kind": "llm", "language": ["embedded_tokenizer": true],
                                       "assets": ["main": "model.aimodel"]]
        try JSONSerialization.data(withJSONObject: metadata).write(to: source.appending(path: "metadata.json"))
        await #expect(throws: HushError.self) {
            try await ModelInstaller(root: root.appending(path: "library")).importCoreAI(from: source)
        }
    }

    @Test(.timeLimit(.minutes(1))) func fullyStagedDownloadInstallsWithoutFetchingFilesAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ModelRecord(id: "hush-tests/fully-staged-fixture", name: "Staging fixture", author: "Tests", engine: .mlx, summary: "")
        let revision = String(repeating: "f", count: 40)
        let directoryName = model.diskKey + "-" + revision.prefix(12)
        let staging = root.appending(path: "Downloads/\(directoryName)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let bytes = Data("{\"fixture\":true}".utf8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try bytes.write(to: staging.appending(path: "config.json"))
        let manifest = ModelManifest(model: model, revision: revision,
            files: [ModelFile(path: "config.json", size: Int64(bytes.count), sha256: digest, gitBlobID: nil)])
        let installer = ModelInstaller(root: root)
        let installed = try await installer.download(manifest, token: nil) { _ in }
        #expect(installed.revision == revision)
        #expect(installed.sizeBytes == Int64(bytes.count))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        let destination = root.appending(path: "Models/\(directoryName)")
        #expect(try Data(contentsOf: destination.appending(path: "config.json")) == bytes)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "hush-model.json").path))
        await #expect(throws: HushError.self) { try await installer.download(manifest, token: nil) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }
}
