import ArrangerLabCore
import ArrangerLabMIDI
import Foundation

enum CommandError: LocalizedError {
    case usage
    case pa700Unavailable
    case keyboardSetNotFound(String)
    case invalidTranspose(String)
    case invalidCaptureDuration(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: ArrangerLabMIDICommand keyboard-set <exact display name> | keyboard-set-address <msb> <lsb> <program> | master-transpose <-12...12> | capture-program [seconds]"
        case .pa700Unavailable:
            return "Pa700 KEYBOARD / Pa700 SOUND endpoints are unavailable"
        case let .keyboardSetNotFound(name):
            return "Keyboard Set not found: \(name)"
        case let .invalidTranspose(value):
            return "Invalid master transpose: \(value) (expected -12...12)"
        case let .invalidCaptureDuration(value):
            return "Invalid capture duration: \(value) (expected 1...120 seconds)"
        }
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let transport = try MIDITransport()
    guard try transport.autoConnectPA700() else {
        throw CommandError.pa700Unavailable
    }

    switch arguments.first {
    case "keyboard-set":
        guard arguments.count >= 2 else { throw CommandError.usage }
        let requestedName = arguments.dropFirst().joined(separator: " ")
        let profile = try InstrumentProfile.bundledPA700()
        let driver = PA700Driver(profile: profile)
        guard let entry = driver.keyboardSetLibraryCatalog.keyboardSets.first(where: {
            $0.displayName.compare(requestedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw CommandError.keyboardSetNotFound(requestedName)
        }
        let scheduled = try driver.compile(
            .selectKeyboardSetLibraryEntry(entryID: entry.id),
            allowDraft: true
        )
        try transport.sendScheduled(scheduled)
        let bytes = scheduled
            .map { $0.message.canonicalBytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
            .joined(separator: " · ")
        print("SENT \(entry.displayName) · \(entry.address) · \(bytes)")

    case "master-transpose":
        guard arguments.count == 2,
              let semitones = Int(arguments[1]),
              (-12...12).contains(semitones) else {
            throw CommandError.invalidTranspose(arguments.dropFirst().first ?? "")
        }
        // MIDI Tuning Standard Universal Realtime Master Coarse Tuning.
        // Device 7F targets the connected instrument without storing state.
        let value = UInt8(64 + semitones)
        let message = MIDIMessage.systemExclusive([0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, value, 0xF7])
        try transport.send(message)
        let bytes = message.canonicalBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("SENT master transpose \(semitones) · \(bytes)")

    case "keyboard-set-address":
        guard arguments.count == 4,
              let msb = UInt8(arguments[1]),
              let lsb = UInt8(arguments[2]),
              let program = UInt8(arguments[3]) else {
            throw CommandError.usage
        }
        let messages: [MIDIMessage] = [
            .controlChange(channel: 15, controller: 0, value: msb),
            .controlChange(channel: 15, controller: 32, value: lsb),
            .programChange(channel: 15, program: program)
        ]
        for message in messages { try transport.send(message) }
        let bytes = messages
            .map { $0.canonicalBytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
            .joined(separator: " · ")
        print("SENT keyboard set address \(msb).\(lsb).\(program) · \(bytes)")

    case "capture-program":
        let durationText = arguments.dropFirst().first ?? "30"
        guard arguments.count <= 2,
              let duration = Double(durationText),
              (1...120).contains(duration) else {
            throw CommandError.invalidCaptureDuration(durationText)
        }

        let lock = NSLock()
        var captured: [MIDIEvent] = []
        transport.onEvent = { event in
            guard event.direction == .input else { return }
            lock.lock()
            captured.append(event)
            lock.unlock()

            guard let message = event.message else {
                print("IN raw · \(event.hex)")
                fflush(stdout)
                return
            }
            switch message {
            case let .controlChange(channel, controller, value) where controller == 0 || controller == 32:
                print("IN ch\(channel + 1) · CC\(controller)=\(value) · \(event.hex)")
            case let .programChange(channel, program):
                print("IN ch\(channel + 1) · PC=\(program) · \(event.hex)")
            case .realtime(0xF8), .realtime(0xFE):
                return
            default:
                print("IN other · \(event.hex)")
            }
            fflush(stdout)
        }

        print("CAPTURING \(Int(duration))s from \(transport.selectedSource?.name ?? "MIDI input") — select the target once on the PA700")
        fflush(stdout)
        RunLoop.current.run(until: Date().addingTimeInterval(duration))

        lock.lock()
        let snapshot = captured
        lock.unlock()
        var found = false
        for channel in UInt8(0)...15 {
            if let selection = MIDIProgramSelectionExtractor.lastComplete(in: snapshot, channel: channel) {
                print("DETECTED \(selection.bankMSB).\(selection.bankLSB).\(selection.program) · ch\(selection.channel + 1) · \(selection.display)")
                found = true
            }
        }
        if !found {
            print("DETECTED none — no complete CC0/CC32/PC sequence received")
        }

    default:
        throw CommandError.usage
    }
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
