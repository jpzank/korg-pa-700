import Foundation

public enum PA700LiveCertainty: String, Codable, Equatable, Sendable {
    case observed
    case inferred
    case stale
    case unknown

    public var isCurrent: Bool { self == .observed || self == .inferred }
}

public enum PA700CommandStateStatus: String, Equatable, Sendable {
    case current
    case stale
}

public struct PA700CommandedShowState: Equatable, Sendable {
    public let preset: ShowPreset
    public let setListItemID: UUID?
    public let sentAt: Date
    public private(set) var status: PA700CommandStateStatus

    public init(
        preset: ShowPreset,
        setListItemID: UUID?,
        sentAt: Date,
        status: PA700CommandStateStatus = .current
    ) {
        self.preset = preset
        self.setListItemID = setListItemID
        self.sentAt = sentAt
        self.status = status
    }

    public var presetID: UUID { preset.id }

    public mutating func markStale() {
        status = .stale
    }
}

public struct PA700LiveField<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value?
    public var certainty: PA700LiveCertainty
    public var source: String?
    public var observedAtNanoseconds: UInt64?

    public init(
        value: Value? = nil,
        certainty: PA700LiveCertainty = .unknown,
        source: String? = nil,
        observedAtNanoseconds: UInt64? = nil
    ) {
        self.value = value
        self.certainty = certainty
        self.source = source
        self.observedAtNanoseconds = observedAtNanoseconds
    }

    public var currentValue: Value? { certainty.isCurrent ? value : nil }

    mutating func update(
        _ value: Value,
        certainty: PA700LiveCertainty,
        source: String,
        at timestamp: UInt64
    ) {
        self.value = value
        self.certainty = certainty
        self.source = source
        observedAtNanoseconds = timestamp
    }

    mutating func markStale() {
        if certainty.isCurrent { certainty = .stale }
    }
}

public struct PA700LiveSelection: Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let library: String?
    public let category: String?
    public let bankMSB: UInt8
    public let bankLSB: UInt8
    public let program: UInt8

    public init(
        id: String,
        displayName: String,
        library: String? = nil,
        category: String? = nil,
        bankMSB: UInt8,
        bankLSB: UInt8,
        program: UInt8
    ) {
        self.id = id
        self.displayName = displayName
        self.library = library
        self.category = category
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.program = program
    }

    public var address: String { "\(bankMSB).\(bankLSB).\(program)" }
}

public struct PA700LivePartState: Equatable, Sendable {
    public var sound = PA700LiveField<PA700LiveSelection>()
    public var volume = PA700LiveField<Int>()
    public var expression = PA700LiveField<Int>()
    public var pan = PA700LiveField<Int>()
    public var damper = PA700LiveField<Bool>()
    public var effectSend1 = PA700LiveField<Int>()
    public var effectSend2 = PA700LiveField<Int>()

    public init() {}

    mutating func markStale() {
        sound.markStale()
        volume.markStale()
        expression.markStale()
        pan.markStale()
        damper.markStale()
        effectSend1.markStale()
        effectSend2.markStale()
    }
}

public struct PA700LiveState: Equatable, Sendable {
    public var deviceIdentity = PA700LiveField<String>()
    public var songBookEntry = PA700LiveField<Int>()
    public var style = PA700LiveField<PA700LiveSelection>()
    public var keyboardSetSlot = PA700LiveField<Int>()
    public var keyboardSet = PA700LiveField<PA700LiveSelection>()
    public var transpose = PA700LiveField<Int>()
    public var arrangerElement = PA700LiveField<ArrangerElement>()
    public var transport = PA700LiveField<TransportState>()
    public var parts: [ShowKeyboardPart: PA700LivePartState]
    public var lastObservedAtNanoseconds: UInt64?

    public init() {
        parts = Dictionary(uniqueKeysWithValues: ShowKeyboardPart.allCases.map { ($0, PA700LivePartState()) })
    }

    public var hasCurrentValues: Bool {
        songBookEntry.certainty.isCurrent
            || style.certainty.isCurrent
            || keyboardSetSlot.certainty.isCurrent
            || keyboardSet.certainty.isCurrent
            || transpose.certainty.isCurrent
            || arrangerElement.certainty.isCurrent
            || transport.certainty.isCurrent
            || parts.values.contains { part in
                part.sound.certainty.isCurrent
                    || part.volume.certainty.isCurrent
                    || part.expression.certainty.isCurrent
                    || part.pan.certainty.isCurrent
                    || part.damper.certainty.isCurrent
                    || part.effectSend1.certainty.isCurrent
                    || part.effectSend2.certainty.isCurrent
            }
    }

    public var hasCurrentIdentifier: Bool {
        songBookEntry.certainty.isCurrent
            || style.certainty.isCurrent
            || keyboardSetSlot.certainty.isCurrent
            || keyboardSet.certainty.isCurrent
            || transpose.certainty.isCurrent
            || parts.values.contains { $0.sound.certainty.isCurrent }
    }

    public var hasStaleIdentifier: Bool {
        songBookEntry.certainty == .stale
            || style.certainty == .stale
            || keyboardSetSlot.certainty == .stale
            || keyboardSet.certainty == .stale
            || transpose.certainty == .stale
            || parts.values.contains { $0.sound.certainty == .stale }
    }

    mutating func markStale() {
        deviceIdentity.markStale()
        songBookEntry.markStale()
        style.markStale()
        keyboardSetSlot.markStale()
        keyboardSet.markStale()
        transpose.markStale()
        arrangerElement.markStale()
        transport.markStale()
        for key in parts.keys { parts[key]?.markStale() }
    }
}

private struct PA700ProgramAddress: Hashable {
    let bankMSB: UInt8
    let bankLSB: UInt8
    let program: UInt8
}

public struct PA700LiveStateReducer: Sendable {
    public private(set) var state = PA700LiveState()

    private let profile: InstrumentProfile
    private let partByChannel: [UInt8: ShowKeyboardPart]
    private let soundByAddress: [PA700ProgramAddress: PA700LiveSelection]
    private let styleByAddress: [PA700ProgramAddress: PA700LiveSelection]
    private let keyboardSetByAddress: [PA700ProgramAddress: PA700LiveSelection]
    private let controlChannel: UInt8?

    private var bankMSB: [UInt8: UInt8] = [:]
    private var bankLSB: [UInt8: UInt8] = [:]
    private var bankMSBChangedChannels = Set<UInt8>()
    private var bankLSBChangedChannels = Set<UInt8>()
    private var nrpnMSB: [UInt8: UInt8] = [:]
    private var nrpnLSB: [UInt8: UInt8] = [:]
    private var dataMSB: [UInt8: UInt8] = [:]
    private var dataLSB: [UInt8: UInt8] = [:]

    public init(
        profile: InstrumentProfile,
        sounds: [PA700OfficialSound] = [],
        styles: [ArrangerStyle] = [],
        keyboardSets: [KeyboardSetLibraryEntry] = []
    ) {
        self.profile = profile
        controlChannel = profile.channels["control"].map { $0 - 1 }

        var channels: [UInt8: ShowKeyboardPart] = [:]
        for (key, part) in [
            ("right1", ShowKeyboardPart.upper1),
            ("right2", .upper2),
            ("right3", .upper3),
            ("left1", .lower)
        ] {
            if let oneBased = profile.channels[key] { channels[oneBased - 1] = part }
        }
        partByChannel = channels

        soundByAddress = Dictionary(
            sounds.map { sound in
                let address = PA700ProgramAddress(bankMSB: sound.bankMSB, bankLSB: sound.bankLSB, program: sound.program)
                let selection = PA700LiveSelection(
                    id: "pa700-\(sound.bankMSB)-\(sound.bankLSB)-\(sound.program)",
                    displayName: sound.name,
                    library: sound.library,
                    category: sound.category,
                    bankMSB: sound.bankMSB,
                    bankLSB: sound.bankLSB,
                    program: sound.program
                )
                return (address, selection)
            },
            uniquingKeysWith: { first, _ in first }
        )
        styleByAddress = Dictionary(
            styles.map { style in
                let address = PA700ProgramAddress(bankMSB: style.bankMSB, bankLSB: style.bankLSB, program: style.program)
                let selection = PA700LiveSelection(
                    id: style.id,
                    displayName: style.displayName,
                    library: style.libraryName,
                    category: style.userBankName ?? style.category,
                    bankMSB: style.bankMSB,
                    bankLSB: style.bankLSB,
                    program: style.program
                )
                return (address, selection)
            },
            uniquingKeysWith: { first, _ in first }
        )
        keyboardSetByAddress = Dictionary(
            keyboardSets.map { entry in
                let address = PA700ProgramAddress(bankMSB: entry.bankMSB, bankLSB: entry.bankLSB, program: entry.program)
                let selection = PA700LiveSelection(
                    id: entry.id,
                    displayName: entry.displayName,
                    library: "Factory",
                    category: entry.category,
                    bankMSB: entry.bankMSB,
                    bankLSB: entry.bankLSB,
                    program: entry.program
                )
                return (address, selection)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @discardableResult
    public mutating func consume(_ event: MIDIEvent) -> Bool {
        guard event.direction == .input,
              let message = event.message,
              event.rawBytes == message.canonicalBytes else { return false }

        let changed: Bool
        switch message {
        case let .controlChange(channel, controller, value):
            changed = consumeControlChange(channel: channel, controller: controller, value: value, at: event.timestampNanoseconds)
        case let .programChange(channel, program):
            changed = consumeProgramChange(channel: channel, program: program, at: event.timestampNanoseconds)
        case let .systemExclusive(bytes):
            changed = consumeSysEx(bytes, at: event.timestampNanoseconds)
        case let .realtime(status) where status == 0xFA || status == 0xFB || status == 0xFC:
            let transport: TransportState = status == 0xFA ? .start : (status == 0xFB ? .continue : .stop)
            state.transport.update(transport, certainty: .observed, source: "MIDI realtime recebido", at: event.timestampNanoseconds)
            changed = true
        default:
            changed = false
        }
        if changed { state.lastObservedAtNanoseconds = event.timestampNanoseconds }
        return changed
    }

    public mutating func markStale() {
        state.markStale()
        bankMSB.removeAll()
        bankLSB.removeAll()
        bankMSBChangedChannels.removeAll()
        bankLSBChangedChannels.removeAll()
        nrpnMSB.removeAll()
        nrpnLSB.removeAll()
        dataMSB.removeAll()
        dataLSB.removeAll()
    }

    public mutating func reset() {
        state = PA700LiveState()
        bankMSB.removeAll()
        bankLSB.removeAll()
        bankMSBChangedChannels.removeAll()
        bankLSBChangedChannels.removeAll()
        nrpnMSB.removeAll()
        nrpnLSB.removeAll()
        dataMSB.removeAll()
        dataLSB.removeAll()
    }

    private mutating func consumeControlChange(channel: UInt8, controller: UInt8, value: UInt8, at timestamp: UInt64) -> Bool {
        if controller == 0 {
            bankMSB[channel] = value
            bankMSBChangedChannels.insert(channel)
            return false
        }
        if controller == 32 {
            bankLSB[channel] = value
            bankLSBChangedChannels.insert(channel)
            return false
        }

        if channel == controlChannel {
            switch controller {
            case 99:
                nrpnMSB[channel] = value
                dataMSB[channel] = nil
                dataLSB[channel] = nil
            case 98:
                nrpnLSB[channel] = value
            case 6:
                dataMSB[channel] = value
            case 38:
                dataLSB[channel] = value
            default:
                break
            }
            if nrpnMSB[channel] == 2,
               nrpnLSB[channel] == 64,
               let hundreds = dataMSB[channel],
               let remainder = dataLSB[channel],
               remainder < 100 {
                state.songBookEntry.update(
                    Int(hundreds) * 100 + Int(remainder),
                    certainty: .observed,
                    source: "NRPN SongBook recebido no canal Control",
                    at: timestamp
                )
                return true
            }
            return false
        }

        guard let part = partByChannel[channel] else { return false }
        switch controller {
        case 7:
            state.parts[part]?.volume.update(Int(value), certainty: .observed, source: "CC7 recebido", at: timestamp)
        case 11:
            state.parts[part]?.expression.update(Int(value), certainty: .observed, source: "CC11 recebido", at: timestamp)
        case 10:
            state.parts[part]?.pan.update(Int(value), certainty: .observed, source: "CC10 recebido", at: timestamp)
        case 64:
            state.parts[part]?.damper.update(value >= 64, certainty: .observed, source: "CC64 recebido", at: timestamp)
        case 91:
            state.parts[part]?.effectSend1.update(Int(value), certainty: .observed, source: "CC91 recebido", at: timestamp)
        case 93:
            state.parts[part]?.effectSend2.update(Int(value), certainty: .observed, source: "CC93 recebido", at: timestamp)
        default:
            return false
        }
        return true
    }

    private mutating func consumeProgramChange(channel: UInt8, program: UInt8, at timestamp: UInt64) -> Bool {
        if let part = partByChannel[channel] {
            guard let msb = bankMSB[channel], let lsb = bankLSB[channel] else { return false }
            let address = PA700ProgramAddress(bankMSB: msb, bankLSB: lsb, program: program)
            let selection = soundByAddress[address] ?? PA700LiveSelection(
                id: "pa700-\(msb)-\(lsb)-\(program)",
                displayName: "Som \(msb).\(lsb).\(program)",
                bankMSB: msb,
                bankLSB: lsb,
                program: program
            )
            state.parts[part]?.sound.update(selection, certainty: .observed, source: "CC0, CC32 e Program Change recebidos", at: timestamp)
            return true
        }

        guard channel == controlChannel else { return false }
        defer {
            bankMSBChangedChannels.remove(channel)
            bankLSBChangedChannels.remove(channel)
        }

        if bankMSBChangedChannels.contains(channel),
           bankLSBChangedChannels.contains(channel),
           let msb = bankMSB[channel],
           let lsb = bankLSB[channel] {
            let address = PA700ProgramAddress(bankMSB: msb, bankLSB: lsb, program: program)
            let style = styleByAddress[address]
            let keyboardSet = keyboardSetByAddress[address]
            if let style, keyboardSet == nil {
                state.style.update(
                    style,
                    certainty: .inferred,
                    source: "CC0, CC32 e Program Change no Control; mapping físico ainda experimental",
                    at: timestamp
                )
                return true
            }
            if let keyboardSet, style == nil {
                state.keyboardSet.update(
                    keyboardSet,
                    certainty: .inferred,
                    source: "CC0, CC32 e Program Change no Control; mapping físico ainda experimental",
                    at: timestamp
                )
                return true
            }
        }

        if (64...67).contains(program) {
            state.keyboardSetSlot.update(
                Int(program - 63),
                certainty: .inferred,
                source: "Program Change 64–67 no canal Control; confirmar no PA700",
                at: timestamp
            )
            return true
        }
        if let element = ArrangerElement(rawValue: program) {
            state.arrangerElement.update(
                element,
                certainty: .inferred,
                source: "Program Change de elemento no canal Control; confirmar no PA700",
                at: timestamp
            )
            return true
        }
        return false
    }

    private mutating func consumeSysEx(_ bytes: [UInt8], at timestamp: UInt64) -> Bool {
        for signature in profile.identitySignatures where bytes.starts(with: signature.responsePrefix) {
            state.deviceIdentity.update(
                "\(profile.model) \(profile.firmware)",
                certainty: .observed,
                source: "Universal Identity Reply recebido",
                at: timestamp
            )
            return true
        }
        guard bytes.count == 8,
              Array(bytes.prefix(6)) == [0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00],
              bytes.last == 0xF7,
              (52...76).contains(bytes[6]) else { return false }
        state.transpose.update(
            Int(bytes[6]) - 64,
            certainty: .observed,
            source: "SysEx universal de Master Transpose recebido",
            at: timestamp
        )
        return true
    }
}

public enum PA700LiveMatchStatus: String, Equatable, Sendable {
    case matches
    case mismatch
    case unknown
}

public struct PA700LiveComparison: Equatable, Sendable {
    public let status: PA700LiveMatchStatus
    public let mismatchedFields: [String]
    public let matchedFields: [String]
    public let inferredFields: [String]

    public init(status: PA700LiveMatchStatus, mismatchedFields: [String], matchedFields: [String], inferredFields: [String] = []) {
        self.status = status
        self.mismatchedFields = mismatchedFields
        self.matchedFields = matchedFields
        self.inferredFields = inferredFields
    }
}

public enum PA700LiveComparator {
    public static func compare(
        state: PA700LiveState,
        expected preset: ShowPreset?
    ) -> PA700LiveComparison {
        guard let preset else { return .init(status: .unknown, mismatchedFields: [], matchedFields: []) }
        var mismatches: [String] = []
        var matches: [String] = []
        var inferred: [String] = []

        func record(_ field: String, _ matchesExpected: Bool, certainty: PA700LiveCertainty) {
            if matchesExpected { matches.append(field) } else { mismatches.append(field) }
            if certainty == .inferred { inferred.append(field) }
        }

        if preset.hasDirectSetup {
            if let expectedStyleID = preset.arrangerStyleID,
               let observedStyle = state.style.currentValue {
                record("Style", observedStyle.id == expectedStyleID, certainty: state.style.certainty)
            }
            if let expectedSlot = preset.keyboardSetSlot,
               let observedSlot = state.keyboardSetSlot.currentValue {
                record("Keyboard Set", observedSlot == expectedSlot, certainty: state.keyboardSetSlot.certainty)
            }
        } else if let expectedSongBook = preset.songBookNumber,
                  let observedSongBook = state.songBookEntry.currentValue {
            record("SongBook", observedSongBook == expectedSongBook, certainty: state.songBookEntry.certainty)
        }

        if let observedTranspose = state.transpose.currentValue {
            record("Transpose", observedTranspose == preset.transposeSemitones, certainty: state.transpose.certainty)
        }

        for part in ShowKeyboardPart.allCases {
            guard let expected = preset.parts.first(where: { $0.part == part }),
                  expected.isEnabled,
                  let expectedSoundID = expected.soundID,
                  let observed = state.parts[part]?.sound.currentValue else { continue }
            record(part.rawValue, observed.id == expectedSoundID, certainty: state.parts[part]?.sound.certainty ?? .unknown)
        }

        if !mismatches.isEmpty {
            return .init(status: .mismatch, mismatchedFields: mismatches, matchedFields: matches, inferredFields: inferred)
        }
        if !matches.isEmpty {
            return .init(status: .matches, mismatchedFields: [], matchedFields: matches, inferredFields: inferred)
        }
        return .init(status: .unknown, mismatchedFields: [], matchedFields: [])
    }
}

public enum PA700LiveDiscoveryTarget: String, CaseIterable, Identifiable, Sendable {
    case sound = "Timbre"
    case songBook = "SongBook"
    case keyboardSet = "Keyboard Set"
    case transpose = "Transpose"
    case style = "Style"
    case variation = "Variação"
    case effects = "Efeitos"

    public var id: String { rawValue }

    public var instruction: String {
        switch self {
        case .sound: return "Escolha um único timbre no painel do PA700."
        case .songBook: return "Abra uma única entrada do SongBook."
        case .keyboardSet: return "Pressione um único Keyboard Set, de 1 a 4."
        case .transpose: return "Altere o transpose em exatamente um semitom."
        case .style: return "Escolha um único Style sem tocar notas."
        case .variation: return "Pressione uma única Variation."
        case .effects: return "Altere um único parâmetro de efeito."
        }
    }
}

public struct PA700LiveDiscoverySample: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let target: PA700LiveDiscoveryTarget
    public let repetition: Int
    public let messages: [[UInt8]]

    public init(id: UUID = UUID(), target: PA700LiveDiscoveryTarget, repetition: Int, messages: [[UInt8]]) {
        self.id = id
        self.target = target
        self.repetition = repetition
        self.messages = messages
    }

    public var signature: String {
        messages.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }.joined(separator: " · ")
    }
}

public enum PA700LiveDiscovery {
    public static func canonicalInputMessages(from events: [MIDIEvent]) -> [[UInt8]] {
        events.compactMap { event in
            guard event.direction == .input,
                  let message = event.message,
                  event.rawBytes == message.canonicalBytes else { return nil }
            if message == .realtime(0xF8) || message == .realtime(0xFE) { return nil }
            return event.rawBytes
        }
    }

    public static func hasThreeMatchingSamples(_ samples: [PA700LiveDiscoverySample], for target: PA700LiveDiscoveryTarget) -> Bool {
        let latest = samples.filter { $0.target == target }.suffix(3)
        guard latest.count == 3, let first = latest.first?.messages, !first.isEmpty else { return false }
        return latest.dropFirst().allSatisfy { $0.messages == first }
    }
}
