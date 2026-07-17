import Foundation

public struct DecodedMIDIMessage: Equatable, Sendable {
    public let message: MIDIMessage
    public let rawBytes: [UInt8]
    public init(message: MIDIMessage, rawBytes: [UInt8]) { self.message = message; self.rawBytes = rawBytes }
}

public final class MIDIStreamDecoder {
    private var runningStatus: UInt8?
    private var pendingStatus: UInt8?
    private var pendingData: [UInt8] = []
    private var pendingRaw: [UInt8] = []
    private var expectedData = 0
    private var sysEx: [UInt8]?

    public init() {}

    public func reset() {
        runningStatus = nil
        pendingStatus = nil
        pendingData.removeAll()
        pendingRaw.removeAll()
        expectedData = 0
        sysEx = nil
    }

    public func feed(_ bytes: [UInt8]) -> [DecodedMIDIMessage] {
        var result: [DecodedMIDIMessage] = []
        for byte in bytes {
            if byte >= 0xF8 {
                result.append(.init(message: .realtime(byte), rawBytes: [byte]))
                continue
            }
            if sysEx != nil {
                sysEx!.append(byte)
                if byte == 0xF7 {
                    let completed = sysEx!
                    result.append(.init(message: .systemExclusive(completed), rawBytes: completed))
                    sysEx = nil
                }
                continue
            }
            if byte & 0x80 != 0 {
                pendingData.removeAll()
                pendingRaw = [byte]
                if byte == 0xF0 {
                    sysEx = [byte]
                    runningStatus = nil
                    pendingStatus = nil
                    continue
                }
                if byte >= 0xF0 {
                    runningStatus = nil
                    pendingStatus = byte
                    expectedData = systemDataLength(byte)
                } else {
                    runningStatus = byte
                    pendingStatus = byte
                    expectedData = channelDataLength(byte)
                }
                if expectedData == 0, let decoded = decode(status: byte, data: []) {
                    result.append(.init(message: decoded, rawBytes: [byte]))
                    pendingStatus = nil
                }
                continue
            }

            if pendingStatus == nil, let status = runningStatus {
                pendingStatus = status
                expectedData = channelDataLength(status)
                pendingData.removeAll()
                pendingRaw.removeAll()
            }
            guard let status = pendingStatus else { continue }
            pendingData.append(byte)
            pendingRaw.append(byte)
            if pendingData.count == expectedData, let decoded = decode(status: status, data: pendingData) {
                result.append(.init(message: decoded, rawBytes: pendingRaw))
                pendingData.removeAll()
                pendingRaw.removeAll()
                pendingStatus = status < 0xF0 ? runningStatus : nil
            }
        }
        return result
    }

    private func channelDataLength(_ status: UInt8) -> Int { (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2 }
    private func systemDataLength(_ status: UInt8) -> Int { [0xF1: 1, 0xF2: 2, 0xF3: 1, 0xF6: 0, 0xF7: 0][status] ?? 0 }

    private func decode(status: UInt8, data: [UInt8]) -> MIDIMessage? {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x80: return .noteOff(channel: channel, note: data[0], velocity: data[1])
        case 0x90: return data[1] == 0 ? .noteOff(channel: channel, note: data[0], velocity: 0) : .noteOn(channel: channel, note: data[0], velocity: data[1])
        case 0xA0: return .polyPressure(channel: channel, note: data[0], pressure: data[1])
        case 0xB0: return .controlChange(channel: channel, controller: data[0], value: data[1])
        case 0xC0: return .programChange(channel: channel, program: data[0])
        case 0xD0: return .channelPressure(channel: channel, pressure: data[0])
        case 0xE0: return .pitchBend(channel: channel, value: (Int(data[0]) | (Int(data[1]) << 7)) - 8_192)
        case 0xF0: return .systemCommon(status: status, data: data)
        default: return nil
        }
    }
}
