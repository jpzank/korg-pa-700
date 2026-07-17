import ArrangerLabCore
import ArrangerLabMIDI
import Foundation

enum CommandError: LocalizedError {
    case usage
    case pa700Unavailable
    case keyboardSetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: ArrangerLabMIDICommand keyboard-set <exact display name>"
        case .pa700Unavailable:
            return "Pa700 KEYBOARD / Pa700 SOUND endpoints are unavailable"
        case let .keyboardSetNotFound(name):
            return "Keyboard Set not found: \(name)"
        }
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2, arguments[0] == "keyboard-set" else {
        throw CommandError.usage
    }

    let requestedName = arguments.dropFirst().joined(separator: " ")
    let profile = try InstrumentProfile.bundledPA700()
    let driver = PA700Driver(profile: profile)
    guard let entry = driver.keyboardSetLibraryCatalog.keyboardSets.first(where: {
        $0.displayName.compare(requestedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }) else {
        throw CommandError.keyboardSetNotFound(requestedName)
    }

    let transport = try MIDITransport()
    guard try transport.autoConnectPA700() else {
        throw CommandError.pa700Unavailable
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
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
