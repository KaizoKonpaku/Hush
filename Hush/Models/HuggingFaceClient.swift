import Foundation

actor HuggingFaceClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = session ?? URLSession(configuration: configuration)
    }

    func search(_ query: String, sort: String = "downloads", token: String? = nil) async throws -> [ModelRecord] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "mlx"),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "48"),
            URLQueryItem(name: "full", value: "true")
        ]
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { components.queryItems?.append(URLQueryItem(name: "search", value: String(query.prefix(200)))) }
        let data = try await get(components.url!, token: token)
        return try JSONDecoder().decode([HubModel].self, from: data).compactMap { model in
            guard (try? ModelPath.validateRepositoryID(model.id)) != nil,
                  model.tags?.contains("mlx") == true,
                  ["text-generation", "image-text-to-text", "conversational", nil].contains(model.pipelineTag) else { return nil }
            return model.record
        }
    }

    func manifest(for record: ModelRecord, token: String? = nil) async throws -> ModelManifest {
        try ModelPath.validateRepositoryID(record.id)
        let url = URL(string: "https://huggingface.co/api/models/\(record.id)?blobs=true")!
        let model = try JSONDecoder().decode(HubModel.self, from: await get(url, token: token))
        guard model.id == record.id,
              let revision = model.sha, revision.count == 40,
              revision.allSatisfy(\.isHexDigit) else {
            throw HushError.message("Hugging Face did not return a valid pinned model revision.")
        }
        let files = try (model.siblings ?? []).filter { ModelPath.isAllowedModelFile($0.rfilename) }.map { file in
            _ = try ModelPath.resolve(file.rfilename, under: URL(fileURLWithPath: "/model"))
            guard let size = file.size ?? file.lfs?.size, size > 0, size < 1_099_511_627_776 else {
                throw HushError.message("The model has missing or invalid file sizes. Download was not started.")
            }
            return ModelFile(path: file.rfilename, size: size, sha256: file.lfs?.sha256, gitBlobID: file.blobId)
        }
        guard files.count <= 512, files.contains(where: { $0.path == "config.json" }),
              files.contains(where: { $0.path == "tokenizer.json" }),
              files.contains(where: { $0.path == "tokenizer_config.json" }),
              files.contains(where: { $0.path.hasSuffix(".safetensors") }),
              Set(files.map(\.path)).count == files.count else {
            throw HushError.message("This repository is not a self-contained MLX language model. It needs config.json, tokenizer.json, tokenizer_config.json, and safetensors weights. Python code and pickle weights are never executed.")
        }
        var result = model.record
        result.sizeBytes = files.reduce(0) { $0 + $1.size }
        result.revision = revision
        return ModelManifest(model: result, revision: revision, files: files)
    }

    private func get(_ url: URL, token: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard data.count < 20 * 1024 * 1024 else { throw HushError.message("The model catalog response was unexpectedly large.") }
        return data
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw HushError.message("The model server returned an invalid response.") }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw HushError.message("This model needs access. Accept its license on Hugging Face and add a read token in Hush Settings.")
        case 404: throw HushError.message("This model or file is no longer available on Hugging Face.")
        case 429: throw HushError.message("Hugging Face is rate limiting requests. Wait a moment, then retry.")
        default: throw HushError.message("The model server returned HTTP \(http.statusCode). Please try again.")
        }
    }
}

private struct HubModel: Decodable {
    let id: String
    var author: String?
    var sha: String?
    var downloads: Int?
    var likes: Int?
    var tags: [String]?
    var pipelineTag: String?
    var siblings: [HubFile]?
    var safetensors: SafeTensorInfo?

    enum CodingKeys: String, CodingKey {
        case id, author, sha, downloads, likes, tags, siblings, safetensors
        case pipelineTag = "pipeline_tag"
    }
    struct SafeTensorInfo: Decodable { var total: Int64? }
    struct HubFile: Decodable {
        let rfilename: String
        var size: Int64?
        var blobId: String?
        var lfs: LFS?
        struct LFS: Decodable { var sha256: String?; var size: Int64? }
    }

    var record: ModelRecord {
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let tags = tags ?? []
        return ModelRecord(
            id: id, name: name.replacingOccurrences(of: "-", with: " "),
            author: author ?? id.components(separatedBy: "/").first ?? "Hugging Face",
            engine: .mlx, summary: pipelineTag == "image-text-to-text" ? "A local vision and language model for MLX." : "A local language model for Apple silicon.",
            tags: tags, downloads: downloads ?? 0, likes: likes ?? 0,
            license: tags.first(where: { $0.hasPrefix("license:") }).map { String($0.dropFirst(8)) },
            parameterCount: safetensors?.total,
            supportsVision: pipelineTag == "image-text-to-text",
            supportsReasoning: tags.contains("reasoning")
        )
    }
}
