import Foundation

public enum MappingStatus: String, Codable, Sendable { case draft = "Draft", verified = "Verified" }
public enum KeyboardZone: String, Codable, CaseIterable, Sendable { case left, right }

public struct KeyboardPartTarget: Codable, Hashable, Sendable {
    public let zone: KeyboardZone
    public let layer: Int

    public init(zone: KeyboardZone, layer: Int) throws {
        guard layer > 0 else { throw ArrangerLabError.invalidValue("layer must be positive") }
        self.zone = zone
        self.layer = layer
    }
}

public enum TransportDomain: String, Codable, CaseIterable, Sendable { case arranger, songPlayer, midiClock }
public enum TransportState: String, Codable, CaseIterable, Sendable { case start, stop, `continue` }

public enum ArrangerElement: UInt8, Codable, CaseIterable, Sendable {
    case intro1 = 80, intro2, intro3
    case variation1, variation2, variation3, variation4
    case fill1, fill2, fill3, fill4
    case `break`, ending1, ending2, ending3

    public var displayName: String {
        switch self {
        case .intro1: return "Intro 1"
        case .intro2: return "Intro 2"
        case .intro3: return "Intro 3 / Count In"
        case .variation1: return "Variation 1"
        case .variation2: return "Variation 2"
        case .variation3: return "Variation 3"
        case .variation4: return "Variation 4"
        case .fill1: return "Fill 1"
        case .fill2: return "Fill 2"
        case .fill3: return "Fill 3"
        case .fill4: return "Fill 4"
        case .break: return "Break"
        case .ending1: return "Ending 1"
        case .ending2: return "Ending 2"
        case .ending3: return "Ending 3"
        }
    }

    public var mappingID: String { "arrangerElement.\(rawValue)" }
}

public enum ArrangerControl: UInt8, Codable, CaseIterable, Sendable {
    case fadeInOut = 95
    case styleToKeyboardSet = 96
    case autoFill = 97
    case memory = 98
    case bassInversion = 99
    case manualBass = 100
    case tempoLock = 101
    case arrangerStartStop = 103
    case playerPlayStop = 104

    public var displayName: String {
        switch self {
        case .fadeInOut: return "Fade In / Out"
        case .styleToKeyboardSet: return "Style to Kbd Set"
        case .autoFill: return "Auto Fill"
        case .memory: return "Memory"
        case .bassInversion: return "Bass Inversion"
        case .manualBass: return "Manual Bass"
        case .tempoLock: return "Tempo Lock"
        case .arrangerStartStop: return "Arranger Start / Stop"
        case .playerPlayStop: return "Player Play / Stop"
        }
    }

    public var mappingID: String { "arrangerControl.\(rawValue)" }
}

public enum InstrumentAction: Codable, Equatable, Sendable {
    case setPartVolume(target: KeyboardPartTarget, level: Double)
    case setPartExpression(target: KeyboardPartTarget, level: Double)
    case setPartPan(target: KeyboardPartTarget, position: Double)
    case setPartDamper(target: KeyboardPartTarget, engaged: Bool)
    case selectDevicePreset(target: KeyboardPartTarget, presetID: String)
    case selectArrangerStyle(styleID: String)
    case selectKeyboardSetLibraryEntry(entryID: String)
    case setTransport(domain: TransportDomain, state: TransportState)
    case selectSongBookEntry(number: Int)
    case selectArrangerElement(ArrangerElement)
    case selectKeyboardSet(slot: Int)
    case triggerArrangerControl(ArrangerControl)
}

public enum MIDIDirection: String, Codable, Sendable { case input, output }
public enum MIDIProtocolKind: String, Codable, Sendable { case midi1 = "MIDI 1.0" }

public enum MIDIMessage: Codable, Equatable, Sendable {
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case polyPressure(channel: UInt8, note: UInt8, pressure: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    case channelPressure(channel: UInt8, pressure: UInt8)
    case pitchBend(channel: UInt8, value: Int)
    case systemCommon(status: UInt8, data: [UInt8])
    case systemExclusive([UInt8])
    case realtime(UInt8)
}

public extension MIDIMessage {
    var canonicalBytes: [UInt8] {
        switch self {
        case let .noteOff(c, n, v): return [0x80 | c, n, v]
        case let .noteOn(c, n, v): return [0x90 | c, n, v]
        case let .polyPressure(c, n, p): return [0xA0 | c, n, p]
        case let .controlChange(c, cc, v): return [0xB0 | c, cc, v]
        case let .programChange(c, p): return [0xC0 | c, p]
        case let .channelPressure(c, p): return [0xD0 | c, p]
        case let .pitchBend(c, value):
            let raw = max(0, min(16_383, value + 8_192))
            return [0xE0 | c, UInt8(raw & 0x7F), UInt8((raw >> 7) & 0x7F)]
        case let .systemCommon(status, data): return [status] + data
        case let .systemExclusive(bytes): return bytes
        case let .realtime(status): return [status]
        }
    }

    var displayName: String {
        switch self {
        case .noteOff: return "Note Off"
        case .noteOn: return "Note On"
        case .polyPressure: return "Poly Pressure"
        case .controlChange: return "Control Change"
        case .programChange: return "Program Change"
        case .channelPressure: return "Channel Pressure"
        case .pitchBend: return "Pitch Bend"
        case .systemCommon: return "System Common"
        case .systemExclusive: return "SysEx"
        case let .realtime(status):
            return [0xF8: "Clock", 0xFA: "Start", 0xFB: "Continue", 0xFC: "Stop", 0xFE: "Active Sensing", 0xFF: "Reset"][status] ?? "Realtime"
        }
    }
}

public struct MIDIEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestampNanoseconds: UInt64
    public let direction: MIDIDirection
    public let endpointUniqueID: Int32
    public let endpointName: String
    public let protocolKind: MIDIProtocolKind
    public let rawBytes: [UInt8]
    public let message: MIDIMessage?

    public init(id: UUID = UUID(), timestampNanoseconds: UInt64, direction: MIDIDirection, endpointUniqueID: Int32, endpointName: String, protocolKind: MIDIProtocolKind = .midi1, rawBytes: [UInt8], message: MIDIMessage?) {
        self.id = id
        self.timestampNanoseconds = timestampNanoseconds
        self.direction = direction
        self.endpointUniqueID = endpointUniqueID
        self.endpointName = endpointName
        self.protocolKind = protocolKind
        self.rawBytes = rawBytes
        self.message = message
    }

    public var hex: String { rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

public struct ScheduledMIDIMessage: Codable, Equatable, Sendable {
    public let offsetNanoseconds: UInt64
    public let message: MIDIMessage
    public let mappingID: String
    public init(offsetNanoseconds: UInt64 = 0, message: MIDIMessage, mappingID: String) {
        self.offsetNanoseconds = offsetNanoseconds
        self.message = message
        self.mappingID = mappingID
    }
}

public struct MIDIProgramSelection: Codable, Equatable, Hashable, Sendable {
    public let channel: UInt8
    public let bankMSB: UInt8
    public let bankLSB: UInt8
    public let program: UInt8

    public init(channel: UInt8, bankMSB: UInt8, bankLSB: UInt8, program: UInt8) {
        self.channel = channel
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.program = program
    }

    public var display: String { "CC0 \(bankMSB) · CC32 \(bankLSB) · PC \(program) · ch \(channel + 1)" }
    public var canonicalMessages: [MIDIMessage] {
        [
            .controlChange(channel: channel, controller: 0, value: bankMSB),
            .controlChange(channel: channel, controller: 32, value: bankLSB),
            .programChange(channel: channel, program: program)
        ]
    }
}

public enum MIDIProgramSelectionExtractor {
    public static func lastComplete(
        in events: [MIDIEvent],
        direction: MIDIDirection = .input,
        channel requiredChannel: UInt8? = nil
    ) -> MIDIProgramSelection? {
        var bankMSB: [UInt8: UInt8] = [:]
        var bankLSB: [UInt8: UInt8] = [:]
        var result: MIDIProgramSelection?
        for event in events where event.direction == direction {
            guard let message = event.message,
                  event.rawBytes == message.canonicalBytes else { continue }
            switch message {
            case let .controlChange(channel, 0, value) where requiredChannel == nil || requiredChannel == channel:
                bankMSB[channel] = value
            case let .controlChange(channel, 32, value) where requiredChannel == nil || requiredChannel == channel:
                bankLSB[channel] = value
            case let .programChange(channel, program) where requiredChannel == nil || requiredChannel == channel:
                if let msb = bankMSB[channel], let lsb = bankLSB[channel] {
                    result = .init(channel: channel, bankMSB: msb, bankLSB: lsb, program: program)
                }
            default:
                continue
            }
        }
        return result
    }
}

public enum ArrangerLabError: LocalizedError, Equatable {
    case invalidValue(String)
    case draftMapping(String)
    case unsupported(String)
    case invalidProfile(String)
    case corruptCapture(String)
    case queueFull
    case endpointUnavailable
    case expertModeRequired
    case microphoneDenied

    public var errorDescription: String? {
        switch self {
        case let .invalidValue(v): return "Invalid value: \(v)"
        case let .draftMapping(v): return "Mapping is Draft: \(v)"
        case let .unsupported(v): return "Unsupported: \(v)"
        case let .invalidProfile(v): return "Invalid profile: \(v)"
        case let .corruptCapture(v): return "Corrupt capture: \(v)"
        case .queueFull: return "MIDI send queue is full"
        case .endpointUnavailable: return "MIDI endpoint is unavailable"
        case .expertModeRequired: return "Expert mode is required"
        case .microphoneDenied: return "Microphone access was denied"
        }
    }
}

public func monotonicNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
