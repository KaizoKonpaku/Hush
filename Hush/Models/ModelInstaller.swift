import CryptoKit
import Foundation

actor ModelInstaller {
    let root: URL
    private var isInstalling = false
    init(root: URL) { self.root = root }

    func download(_ manifest: ModelManifest, token: String?,
                  progress: @Sendable @escaping (ModelDownload) -> Void) async throws -> ModelRecord {
        guard !isInstalling else { throw HushError.message("Wait for the current model installation to finish.") }
        isInstalling = true
        defer { isInstalling = false }
        let fileManager = FileManager.default
        let directoryName = manifest.model.diskKey + "-" + manifest.revision.prefix(12)
        let staging = root.appending(path: "Downloads/\(directoryName)")
        let destination = root.appending(path: "Models/\(directoryName)")
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw HushError.message("This exact model revision is already installed.")
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var verifiedFiles: Set<String> = []
        var stagedBytes: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let target = try ModelPath.resolve(file.path, under: staging)
            guard fileManager.fileExists(atPath: target.path) else { continue }
            progress(ModelDownload(modelID: manifest.model.id, phase: .verifying,
                                   completedBytes: stagedBytes, totalBytes: manifest.totalBytes, filename: file.path))
            do {
                try Self.verify(target, file: file)
                verifiedFiles.insert(file.path)
                stagedBytes += file.size
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try fileManager.removeItem(at: target)
            }
        }
        let available = try Self.availableStorage(at: root)
        let remainingBytes = manifest.totalBytes - stagedBytes
        guard remainingBytes + 512 * 1024 * 1024 < available else {
            throw HushError.message("Not enough free storage for this download. It still needs \(ByteCountFormatter.string(fromByteCount: remainingBytes, countStyle: .file)) plus working space.")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var completedBytes: Int64 = 0

        for file in manifest.files {
            try Task.checkCancellation()
            let target = try ModelPath.resolve(file.path, under: staging)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if verifiedFiles.contains(file.path) {
                completedBytes += file.size
                continue
            }
            let pinnedURL = URL(string: "https://huggingface.co/\(manifest.model.id)/resolve/\(manifest.revision)/")!
                .appending(path: file.path)
            var request = URLRequest(url: pinnedURL)
            if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let base = completedBytes
            let delegate = DownloadObserver { received in
                progress(ModelDownload(modelID: manifest.model.id, phase: .downloading,
                    completedBytes: base + min(received, file.size), totalBytes: manifest.totalBytes, filename: file.path))
            }
            let (temporary, response) = try await session.download(for: request, delegate: delegate)
            defer { try? fileManager.removeItem(at: temporary) }
            try HuggingFaceClient.check(response)
            try Task.checkCancellation()
            progress(ModelDownload(modelID: manifest.model.id, phase: .verifying,
                                   completedBytes: completedBytes, totalBytes: manifest.totalBytes, filename: file.path))
            try Self.verify(temporary, file: file)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.moveItem(at: temporary, to: target)
            completedBytes += file.size
        }

        try Task.checkCancellation()
        var installed = manifest.model
        installed.installedDirectory = directoryName
        installed.installedAt = Date()
        installed.revision = manifest.revision
        installed.sizeBytes = manifest.totalBytes
        try JSONEncoder().encode(installed).write(to: staging.appending(path: "hush-model.json"), options: .atomic)
        try fileManager.moveItem(at: staging, to: destination)
        progress(ModelDownload(modelID: installed.id, phase: .complete,
                               completedBytes: manifest.totalBytes, totalBytes: manifest.totalBytes, filename: "Ready to use"))
        return installed
    }

    static func verify(_ url: URL, file: ModelFile) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == file.size else { throw HushError.message("\(file.path) was incomplete. Retry to resume the download.") }
        guard let stream = InputStream(url: url) else { throw HushError.message("The downloaded file could not be opened.") }
        stream.open()
        defer { stream.close() }
        var sha256 = SHA256()
        var gitSHA1 = Insecure.SHA1()
        gitSHA1.update(data: Data("blob \(file.size)\0".utf8))
        var buffer = [UInt8](repeating: 0, count: 512 * 1024)
        while stream.hasBytesAvailable {
            try Task.checkCancellation()
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? HushError.message("Could not verify the model file.") }
            if count == 0 { break }
            let data = Data(buffer.prefix(count))
            sha256.update(data: data)
            gitSHA1.update(data: data)
        }
        if let expected = file.sha256 {
            guard sha256.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else {
                throw HushError.message("\(file.path) failed its SHA-256 check. The model was not installed.")
            }
        } else if let expected = file.gitBlobID {
            guard gitSHA1.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else {
                throw HushError.message("\(file.path) did not match the pinned repository file.")
            }
        } else {
            throw HushError.message("\(file.path) has no verification checksum. The model was not installed.")
        }
    }

    func importCoreAI(from source: URL) async throws -> ModelRecord {
        guard !isInstalling else { throw HushError.message("Wait for the current model installation to finish.") }
        isInstalling = true
        defer { isInstalling = false }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let metadataURL = try ModelPath.resolve("metadata.json", under: source)
        guard try metadataURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= 2 * 1024 * 1024 else {
            throw HushError.message("The model metadata is too large to import safely.")
        }
        let metadataData = try Data(contentsOf: metadataURL)
        guard metadataData.count <= 2 * 1024 * 1024,
              let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              let language = metadata["language"] as? [String: Any],
              let kind = metadata["kind"] as? String, ["llm", "vlm"].contains(kind),
              (language["embedded_tokenizer"] as? Bool) != false,
              FileManager.default.fileExists(atPath: source.appending(path: "tokenizer/tokenizer.json").path),
              FileManager.default.fileExists(atPath: source.appending(path: "tokenizer/tokenizer_config.json").path),
              let assets = metadata["assets"] as? [String: String], assets["main"] != nil else {
            throw HushError.message("Choose an exported Core AI language-model bundle with metadata.json and an embedded tokenizer. Hush does not fetch missing files during inference.")
        }
        for path in assets.values {
            let asset = try ModelPath.resolve(path, under: source)
            guard asset.pathExtension == "aimodel", FileManager.default.fileExists(atPath: asset.path) else {
                throw HushError.message("A Core AI asset is missing. Import the complete exported bundle, including its .aimodel files.")
            }
        }
        let files = try Self.safeFiles(in: source)
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        try FileManager.default.createDirectory(at: root.appending(path: "Models"), withIntermediateDirectories: true)
        let available = try Self.availableStorage(at: root)
        guard total + 512 * 1024 * 1024 < available else { throw HushError.message("Not enough storage to import this model.") }
        let id = "local/\(UUID().uuidString)"
        var model = ModelRecord(id: id, name: metadata["name"] as? String ?? source.lastPathComponent,
                                author: "Imported bundle", engine: .coreAI,
                                summary: "An Apple Core AI model bundle, stored on this device.", sizeBytes: total,
                                supportsVision: kind == "vlm")
        model.installedDirectory = model.diskKey
        model.installedAt = Date()
        let destination = root.appending(path: "Models/\(model.diskKey)")
        let staging = root.appending(path: "Downloads/\(model.diskKey)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for file in files {
                try Task.checkCancellation()
                let target = try ModelPath.resolve(file.path, under: staging)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: ModelPath.resolve(file.path, under: source), to: target)
            }
            try JSONEncoder().encode(model).write(to: staging.appending(path: "hush-model.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: destination)
            return model
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func availableStorage(at root: URL) throws -> Int64 {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(values.volumeAvailableCapacity ?? 0)
    }

    private static func safeFiles(in root: URL) throws -> [ModelFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            throw HushError.message("The selected model folder could not be read.")
        }
        var result: [ModelFile] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw HushError.message("Model bundles containing symbolic links cannot be imported.") }
            guard values.isRegularFile == true else { continue }
            let path = String(url.path.dropFirst(root.path.count + 1))
            _ = try ModelPath.resolve(path, under: root)
            guard !["py", "sh", "dylib", "so", "app", "exe", "pkl", "pickle"].contains(url.pathExtension.lowercased()) else {
                throw HushError.message("The bundle contains executable code or unsafe weights. Import only the exported Core AI bundle.")
            }
            if path == "hush-model.json" { continue }
            result.append(ModelFile(path: path, size: Int64(values.fileSize ?? 0), sha256: nil, gitBlobID: nil))
            guard result.count <= 20_000 else { throw HushError.message("The model bundle contains too many files.") }
        }
        return result
    }

}

private final class DownloadObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let handler: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var lastUpdate = Date.distantPast
    init(handler: @Sendable @escaping (Int64) -> Void) { self.handler = handler }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock()
        let now = Date()
        let shouldUpdate = now.timeIntervalSince(lastUpdate) >= 0.1
        if shouldUpdate { lastUpdate = now }
        lock.unlock()
        if shouldUpdate { handler(totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var request = request
        // Download CDNs use signed URLs. Never forward the user's Hub token to another host.
        if request.url?.host != "huggingface.co" { request.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(request)
    }
}
