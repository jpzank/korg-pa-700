import Foundation

public struct DriverIdentification: Equatable, Sendable {
    public let model: String?
    public let confidence: Double
    public let reason: String
    public init(model: String?, confidence: Double, reason: String) { self.model = model; self.confidence = confidence; self.reason = reason }
}

public protocol InstrumentDriver {
    var profile: InstrumentProfile { get }
    var capabilities: Set<String> { get }
    func identify(from message: MIDIMessage) -> DriverIdentification
    func compile(_ action: InstrumentAction, allowDraft: Bool) throws -> [ScheduledMIDIMessage]
    func interpret(_ message: MIDIMessage) -> [InstrumentAction]
}

public struct PA700Driver: InstrumentDriver {
    public let profile: InstrumentProfile
    public let styleCatalog: ArrangerStyleCatalog
    public let keyboardSetLibraryCatalog: KeyboardSetLibraryCatalog
    public let capabilities: Set<String> = ["identity", "partVolume", "partExpression", "partPan", "partDamper", "devicePreset", "styleSelection", "keyboardSetLibrarySelection", "masterTranspose", "arrangerTransport", "midiClock", "songBook", "arrangerElement", "keyboardSet", "arrangerControl"]

    public init(profile: InstrumentProfile, styleCatalog: ArrangerStyleCatalog? = nil, keyboardSetLibraryCatalog: KeyboardSetLibraryCatalog? = nil) {
        self.profile = profile
        self.styleCatalog = styleCatalog ?? (try? .bundledPA700()) ?? .init(schemaVersion: 1, model: "PA700", firmware: "1.5.0", source: "unavailable", styles: [])
        self.keyboardSetLibraryCatalog = keyboardSetLibraryCatalog ?? (try? .bundledPA700()) ?? .init(schemaVersion: 1, model: "PA700", firmware: "1.5.0", source: "unavailable", keyboardSets: [])
    }

    public func identify(from message: MIDIMessage) -> DriverIdentification {
        guard case let .systemExclusive(bytes) = message else { return .init(model: nil, confidence: 0, reason: "not SysEx") }
        for signature in profile.identitySignatures where bytes.starts(with: signature.responsePrefix) {
            return .init(model: profile.model, confidence: 1, reason: "Universal Identity Reply matched manufacturer/family/model")
        }
        return .init(model: nil, confidence: 0, reason: "identity signature did not match")
    }

    public func compile(_ action: InstrumentAction, allowDraft: Bool = false) throws -> [ScheduledMIDIMessage] {
        switch action {
        case let .setPartVolume(target, level):
            guard (0...1).contains(level) else { throw ArrangerLabError.invalidValue("level must be 0...1") }
            try requireMapping("partVolume", allowDraft: allowDraft)
            let channel = try channel(for: target)
            let value = UInt8((level * 127).rounded())
            return [.init(message: .controlChange(channel: channel, controller: 7, value: value), mappingID: "partVolume")]
        case let .setPartExpression(target, level):
            guard (0...1).contains(level) else { throw ArrangerLabError.invalidValue("level must be 0...1") }
            try requireMapping("partExpression", allowDraft: allowDraft)
            let channel = try channel(for: target)
            let value = UInt8((level * 127).rounded())
            return [.init(message: .controlChange(channel: channel, controller: 11, value: value), mappingID: "partExpression")]
        case let .setPartPan(target, position):
            guard (-1...1).contains(position) else { throw ArrangerLabError.invalidValue("position must be -1...1") }
            try requireMapping("partPan", allowDraft: allowDraft)
            let channel = try channel(for: target)
            let value = UInt8((((position + 1) / 2) * 127).rounded())
            return [.init(message: .controlChange(channel: channel, controller: 10, value: value), mappingID: "partPan")]
        case let .setPartDamper(target, engaged):
            try requireMapping("partDamper", allowDraft: allowDraft)
            let channel = try channel(for: target)
            return [.init(message: .controlChange(channel: channel, controller: 64, value: engaged ? 127 : 0), mappingID: "partDamper")]
        case let .selectDevicePreset(target, presetID):
            let channel = try channel(for: target)
            guard let preset = profile.presets.first(where: { $0.id == presetID }) else { throw ArrangerLabError.invalidValue("unknown exact preset \(presetID)") }
            if preset.status == .draft && !allowDraft { throw ArrangerLabError.draftMapping("preset.\(presetID)") }
            return [
                .init(message: .controlChange(channel: channel, controller: 0, value: preset.bankMSB), mappingID: "devicePreset"),
                .init(offsetNanoseconds: 1_000_000, message: .controlChange(channel: channel, controller: 32, value: preset.bankLSB), mappingID: "devicePreset"),
                .init(offsetNanoseconds: 2_000_000, message: .programChange(channel: channel, program: preset.program), mappingID: "devicePreset")
            ]
        case let .selectArrangerStyle(styleID):
            try requireMapping("styleSelection", allowDraft: allowDraft)
            guard let style = styleCatalog.styles.first(where: { $0.id == styleID }) else {
                throw ArrangerLabError.invalidValue("unknown exact Style \(styleID)")
            }
            let channel = try controlChannel()
            return [
                .init(message: .controlChange(channel: channel, controller: 0, value: style.bankMSB), mappingID: "styleSelection"),
                .init(offsetNanoseconds: 1_000_000, message: .controlChange(channel: channel, controller: 32, value: style.bankLSB), mappingID: "styleSelection"),
                .init(offsetNanoseconds: 2_000_000, message: .programChange(channel: channel, program: style.program), mappingID: "styleSelection")
            ]
        case let .selectKeyboardSetLibraryEntry(entryID):
            try requireMapping("keyboardSetLibrarySelection", allowDraft: allowDraft)
            guard let entry = keyboardSetLibraryCatalog.keyboardSets.first(where: { $0.id == entryID }) else {
                throw ArrangerLabError.invalidValue("unknown exact Keyboard Set Library entry \(entryID)")
            }
            let channel = try controlChannel()
            return [
                .init(message: .controlChange(channel: channel, controller: 0, value: entry.bankMSB), mappingID: "keyboardSetLibrarySelection"),
                .init(offsetNanoseconds: 1_000_000, message: .controlChange(channel: channel, controller: 32, value: entry.bankLSB), mappingID: "keyboardSetLibrarySelection"),
                .init(offsetNanoseconds: 2_000_000, message: .programChange(channel: channel, program: entry.program), mappingID: "keyboardSetLibrarySelection")
            ]
        case let .setMasterTranspose(semitones):
            guard (-12...12).contains(semitones) else {
                throw ArrangerLabError.invalidValue("master transpose must be -12...12")
            }
            try requireMapping("masterTranspose", allowDraft: allowDraft)
            return [
                .init(
                    message: .systemExclusive([0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, UInt8(64 + semitones), 0xF7]),
                    mappingID: "masterTranspose"
                )
            ]
        case let .setTransport(domain, state):
            let mapping = domain == .midiClock ? "midiClock" : "arrangerTransport"
            try requireMapping(mapping, allowDraft: allowDraft)
            let status: UInt8 = state == .start ? 0xFA : (state == .continue ? 0xFB : 0xFC)
            return [.init(message: .realtime(status), mappingID: mapping)]
        case let .selectSongBookEntry(number):
            guard (0...9_999).contains(number) else { throw ArrangerLabError.invalidValue("SongBook number must be 0...9999") }
            try requireMapping("songBook", allowDraft: allowDraft)
            guard let control = profile.channels["control"] else { throw ArrangerLabError.invalidProfile("control channel missing") }
            let channel = control - 1
            return [
                .init(message: .controlChange(channel: channel, controller: 99, value: 2), mappingID: "songBook"),
                .init(offsetNanoseconds: 1_000_000, message: .controlChange(channel: channel, controller: 98, value: 64), mappingID: "songBook"),
                .init(offsetNanoseconds: 2_000_000, message: .controlChange(channel: channel, controller: 6, value: UInt8(number / 100)), mappingID: "songBook"),
                .init(offsetNanoseconds: 3_000_000, message: .controlChange(channel: channel, controller: 38, value: UInt8(number % 100)), mappingID: "songBook")
            ]
        case let .selectArrangerElement(element):
            try requireMapping(element.mappingID, allowDraft: allowDraft)
            return [.init(message: .programChange(channel: try controlChannel(), program: element.rawValue), mappingID: element.mappingID)]
        case let .selectKeyboardSet(slot):
            guard (1...4).contains(slot) else { throw ArrangerLabError.invalidValue("Keyboard Set slot must be 1...4") }
            try requireMapping("keyboardSet", allowDraft: allowDraft)
            return [.init(message: .programChange(channel: try controlChannel(), program: UInt8(63 + slot)), mappingID: "keyboardSet")]
        case let .triggerArrangerControl(control):
            try requireMapping(control.mappingID, allowDraft: allowDraft)
            return [.init(message: .programChange(channel: try controlChannel(), program: control.rawValue), mappingID: control.mappingID)]
        }
    }

    public func interpret(_ message: MIDIMessage) -> [InstrumentAction] {
        switch message {
        case let .controlChange(channel, controller, value) where controller == 7:
            for (name, configured) in profile.channels where configured - 1 == channel {
                let target = profile.aliases[name] ?? profile.aliases[name.lowercased()]
                if let target { return [.setPartVolume(target: target, level: Double(value) / 127)] }
            }
        case let .controlChange(channel, controller, value) where controller == 11:
            for (name, configured) in profile.channels where configured - 1 == channel {
                let target = profile.aliases[name] ?? profile.aliases[name.lowercased()]
                if let target { return [.setPartExpression(target: target, level: Double(value) / 127)] }
            }
        case let .controlChange(channel, controller, value) where controller == 10:
            for (name, configured) in profile.channels where configured - 1 == channel {
                let target = profile.aliases[name] ?? profile.aliases[name.lowercased()]
                if let target {
                    let position = value == 64
                        ? 0
                        : (value < 64 ? (Double(value) / 64) - 1 : Double(value - 64) / 63)
                    return [.setPartPan(target: target, position: position)]
                }
            }
        case let .controlChange(channel, controller, value) where controller == 64:
            for (name, configured) in profile.channels where configured - 1 == channel {
                let target = profile.aliases[name] ?? profile.aliases[name.lowercased()]
                if let target { return [.setPartDamper(target: target, engaged: value >= 64)] }
            }
        case let .programChange(channel, program) where channel == (try? controlChannel()):
            if let element = ArrangerElement(rawValue: program) { return [.selectArrangerElement(element)] }
            if (64...67).contains(program) { return [.selectKeyboardSet(slot: Int(program - 63))] }
            if let control = ArrangerControl(rawValue: program) { return [.triggerArrangerControl(control)] }
        default:
            break
        }
        return []
    }

    private func requireMapping(_ id: String, allowDraft: Bool) throws {
        guard let mapping = profile.mappings[id] else { throw ArrangerLabError.unsupported(id) }
        if mapping.status == .draft && !allowDraft { throw ArrangerLabError.draftMapping(id) }
    }

    private func channel(for target: KeyboardPartTarget) throws -> UInt8 {
        let key = target.zone == .right ? "right\(target.layer)" : "left\(target.layer)"
        guard let oneBased = profile.channels[key] else { throw ArrangerLabError.unsupported("part \(key)") }
        return oneBased - 1
    }

    private func controlChannel() throws -> UInt8 {
        guard let oneBased = profile.channels["control"] else { throw ArrangerLabError.invalidProfile("control channel missing") }
        return oneBased - 1
    }
}
