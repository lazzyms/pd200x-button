import Foundation

enum MuteQueryProtocol {
    static let reportID: UInt8 = 0x4B
    static let reportLength = 64

    static func makeReadPacket() -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: reportLength)
        packet[0] = reportID
        packet[1] = 0xC4
        packet[2] = 0x09
        packet[5] = 0x04
        packet[6] = 0x22
        packet[7] = 0x20

        let checksum = checksum(for: packet, through: 63)
        packet[8] = UInt8(truncatingIfNeeded: checksum)
        packet[9] = UInt8(truncatingIfNeeded: checksum >> 8)
        return packet
    }

    static func makeForceUnmutePacket() -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: reportLength)
        packet[0] = reportID
        packet[1] = 0xC4
        packet[2] = 0x0B
        packet[5] = 0x03
        packet[6] = 0x22
        packet[7] = 0x20
        packet[8] = 0x00
        packet[9] = 0x00

        let checksum = checksum(for: packet, through: 10)
        packet[10] = UInt8(truncatingIfNeeded: checksum)
        packet[11] = UInt8(truncatingIfNeeded: checksum >> 8)
        return packet
    }

    static func isPermittedRead(_ packet: [UInt8]) -> Bool {
        packet == makeReadPacket()
    }

    static func isPermittedForceUnmute(_ packet: [UInt8]) -> Bool {
        packet == makeForceUnmutePacket()
    }

    static func parseReadResponse(payload: [UInt8]) -> Bool? {
        guard payload.count >= 8,
              payload[0] == 0xC4,
              payload[1] == 0x0B,
              payload[4] == 0x04,
              payload[5] == 0x22,
              payload[6] == 0x20
        else { return nil }

        return payload[7] != 0
    }

    static func parseRawReadResponse(report: [UInt8]) -> Bool? {
        guard report.count >= 9,
              report[0] == reportID,
              report[1] == 0xC4,
              report[2] == 0x0B,
              report[5] == 0x04,
              report[6] == 0x22,
              report[7] == 0x20
        else { return nil }

        return report[8] != 0
    }

    static func hex(_ packet: [UInt8]) -> String {
        packet.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func checksum(for packet: [UInt8], through end: Int) -> UInt16 {
        let sum = packet[1..<end].reduce(UInt16(0)) {
            $0 &+ UInt16($1)
        }
        return UInt16(0) &- sum
    }
}
