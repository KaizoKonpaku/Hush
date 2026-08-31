import Foundation

struct CompanionPacket: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case request, update, finished, failure, cancel }
    var version = 1
    var id: UUID
    var kind: Kind
    var text = ""

    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1024 else { throw CocoaError(.coderReadCorrupt) }
        let packet = try JSONDecoder().decode(Self.self, from: data)
        guard packet.version == 1, packet.text.count <= 16_000 else { throw CocoaError(.coderReadCorrupt) }
        return packet
    }
}
