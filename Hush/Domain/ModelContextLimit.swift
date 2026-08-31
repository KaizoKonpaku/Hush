import Foundation

enum ModelContextLimit {
    static func read(from directory: URL) -> Int {
        for filename in ["config.json", "metadata.json"] {
            guard let data = try? Data(contentsOf: directory.appending(path: filename)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let settings = json["text_config"] as? [String: Any] ?? json["language"] as? [String: Any] ?? json
            if let limit = settings["max_position_embeddings"] as? Int ?? settings["max_context_length"] as? Int {
                return max(512, min(32_768, limit))
            }
        }
        return 4096
    }
}
