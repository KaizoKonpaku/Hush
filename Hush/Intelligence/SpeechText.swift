import Foundation

struct SpeechTranscript: Sendable {
    struct Segment: Sendable {
        var start: Double
        var end: Double
        var text: String
        var isFinal: Bool
    }

    private(set) var segments: [Segment] = []
    private(set) var consumedThrough: Double = 0

    var text: String {
        segments.sorted { $0.start < $1.start }.map(\.text)
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func update(_ segment: Segment) {
        guard segment.start.isFinite, segment.end.isFinite, segment.end > segment.start,
              segment.start >= consumedThrough - 0.001 else { return }
        if segments.contains(where: { $0.isFinal && $0.start == segment.start && !segment.isFinal }) { return }
        segments.removeAll { $0.start < segment.end && $0.end > segment.start }
        segments.append(segment)
    }

    mutating func discard(through time: Double? = nil) {
        consumedThrough = max(consumedThrough, segments.map(\.end).max() ?? 0, time ?? 0)
        segments.removeAll()
    }
}

struct SpeechChunker: Sendable {
    private(set) var consumed = ""

    mutating func append(snapshot: String, final: Bool) -> [String] {
        let clean = SpokenText.clean(snapshot)
        // Never repeat already spoken words if a streaming model revises a prefix.
        guard clean.hasPrefix(consumed) else { return [] }
        var remaining = String(clean.dropFirst(consumed.count))
        var chunks: [String] = []
        while !remaining.isEmpty {
            let characters = Array(remaining)
            var count: Int?
            for index in characters.indices {
                let character = characters[index]
                if ".!?\u{3002}\u{ff01}\u{ff1f}\n".contains(character),
                   index + 1 < characters.count,
                   characters[index + 1].isWhitespace {
                    count = index + 1
                    break
                }
                if index >= 240, character.isWhitespace {
                    count = index
                    break
                }
            }
            if count == nil, final { count = min(characters.count, 400) }
            guard let count, count > 0 else { break }
            let raw = String(characters.prefix(count))
            consumed += raw
            remaining = String(characters.dropFirst(count))
            let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty { chunks.append(spoken) }
        }
        return chunks
    }
}

enum SpokenText {
    static func clean(_ text: String) -> String {
        let fence = String(repeating: "\u{60}", count: 3)
        let sections = text.components(separatedBy: fence)
        var value = sections.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element).joined(separator: " ")
        value = value.replacingOccurrences(of: #"<think>[\s\S]*?(</think>|$)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?m)^\s{0,3}[#>*-]+\s+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\u{60}", with: "").replacingOccurrences(of: "**", with: "")
        return String(value.prefix(64_000))
    }

    static func isEcho(_ input: String, of output: String) -> Bool {
        func words(_ value: String) -> String {
            value.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        }
        let candidate = words(input)
        return candidate.split(separator: " ").count >= 3 && words(output).contains(candidate)
    }
}
