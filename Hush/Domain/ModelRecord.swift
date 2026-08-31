import CryptoKit
import Foundation

enum ModelEngine: String, Codable, CaseIterable, Sendable {
    case apple, mlx, coreAI

    var title: String {
        switch self { case .apple: "Apple Intelligence"; case .mlx: "MLX"; case .coreAI: "Core AI" }
    }
    var hardware: String {
        switch self {
        case .apple: "Apple-managed acceleration"
        case .mlx: "Metal GPU + unified memory"
        case .coreAI: "CPU, GPU or Neural Engine by model variant"
        }
    }
}

struct ModelRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var author: String
    var engine: ModelEngine
    var summary: String
    var tags: [String] = []
    var downloads: Int = 0
    var likes: Int = 0
    var license: String?
    var parameterCount: Int64?
    var sizeBytes: Int64?
    var supportsVision = false
    var supportsReasoning = false
    var installedDirectory: String?
    var revision: String?
    var installedAt: Date?

    var isInstalled: Bool { engine == .apple || installedDirectory != nil }
    var diskKey: String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    var repositoryURL: URL? { engine == .mlx ? URL(string: "https://huggingface.co/\(id)") : nil }
    var parameterLabel: String? {
        guard let parameterCount, parameterCount > 0 else { return nil }
        return parameterCount >= 1_000_000_000
            ? String(format: "%.1fB", Double(parameterCount) / 1_000_000_000)
            : String(format: "%.0fM", Double(parameterCount) / 1_000_000)
    }
    var quantization: String? {
        let text = (tags + [id]).joined(separator: " ").lowercased()
        for bits in [2, 3, 4, 5, 6, 8, 16] {
            if text.range(of: "(^|[^0-9])\(bits)-?bit([^a-z0-9]|$)", options: .regularExpression) != nil {
                return "\(bits)-bit"
            }
        }
        return nil
    }

    static let apple = ModelRecord(
        id: "apple/system-on-device", name: "Apple On-Device", author: "Apple",
        engine: .apple,
        summary: "Apple's built-in OS 27 foundation model. Runs locally once Apple Intelligence is ready.",
        tags: ["Built in", "Vision"], supportsVision: true
    )
}

struct ModelFile: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let sha256: String?
    let gitBlobID: String?
}

struct ModelManifest: Codable, Sendable {
    var model: ModelRecord
    let revision: String
    let files: [ModelFile]
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

struct ModelDownload: Sendable {
    enum Phase: String, Sendable { case preparing, downloading, verifying, paused, complete, failed }
    var modelID: String
    var phase: Phase = .preparing
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var filename = "Preparing download"
    var error: String?
    var fraction: Double { totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0 }
    var isActive: Bool { [.preparing, .downloading, .verifying].contains(phase) }
}

enum ModelPath {
    static func validateRepositoryID(_ id: String) throws {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && part.count <= 96 &&
            part.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
        }) else { throw HushError.message("Enter a Hugging Face model ID in the form author/model.") }
    }

    static func resolve(_ relativePath: String, under root: URL) throws -> URL {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, relativePath.count <= 512,
              !relativePath.contains("\\"), !relativePath.contains("\0"),
              !relativePath.contains(":"), !relativePath.contains("%"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw HushError.message("The model contains an unsafe file path.")
        }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        var candidate = base
        for part in parts {
            candidate.append(path: String(part))
            // Resolve each existing parent: the final file may not exist yet.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                throw HushError.message("Model files cannot follow symbolic links.")
            }
        }
        candidate = candidate.standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else {
            throw HushError.message("A model file points outside its folder.")
        }
        return candidate
    }

    static func isAllowedModelFile(_ path: String) -> Bool {
        let name = path.lowercased()
        return [".safetensors", ".json", ".jinja", ".model"].contains { name.hasSuffix($0) }
            || name == "merges.txt" || name == "vocab.txt"
    }
}
