import Foundation
import Testing
@testable import Hush

struct CompanionPacketTests {
    @Test func roundTripsRequestIdentityAndText() throws {
        let packet = CompanionPacket(id: UUID(), kind: .request, text: "A short question")
        let decoded = try CompanionPacket.decode(packet.encoded())
        #expect(decoded.id == packet.id)
        #expect(decoded.kind == .request)
        #expect(decoded.text == packet.text)
    }

    @Test func rejectsUnknownProtocolAndOversizedMessages() throws {
        let unsupported = CompanionPacket(version: 2, id: UUID(), kind: .request)
        #expect(throws: CocoaError.self) { try CompanionPacket.decode(unsupported.encoded()) }
        let oversized = CompanionPacket(id: UUID(), kind: .request, text: String(repeating: "x", count: 16_001))
        #expect(throws: CocoaError.self) { try CompanionPacket.decode(oversized.encoded()) }
        #expect(throws: CocoaError.self) { try CompanionPacket.decode(Data(repeating: 0, count: 65_537)) }
    }
}
