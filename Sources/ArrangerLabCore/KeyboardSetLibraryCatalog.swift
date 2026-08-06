import Foundation

public struct KeyboardSetLibraryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let category: String
    public let bankMSB: UInt8
    public let bankLSB: UInt8
    public let program: UInt8

    public init(id: String, displayName: String, category: String, bankMSB: UInt8, bankLSB: UInt8, program: UInt8) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.program = program
    }

    public var address: String { "\(bankMSB).\(bankLSB).\(program)" }
}

public struct KeyboardSetLibraryCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let model: String
    public let firmware: String
    public let source: String
    public let keyboardSets: [KeyboardSetLibraryEntry]

    public init(schemaVersion: Int, model: String, firmware: String, source: String, keyboardSets: [KeyboardSetLibraryEntry]) {
        self.schemaVersion = schemaVersion
        self.model = model
        self.firmware = firmware
        self.source = source
        self.keyboardSets = keyboardSets
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw ArrangerLabError.invalidProfile("unsupported Keyboard Set Library catalog schema") }
        guard model == "PA700", firmware == "1.5.0" else { throw ArrangerLabError.invalidProfile("Keyboard Set Library catalog does not match PA700 firmware 1.5.0") }
        guard keyboardSets.count == 298 else { throw ArrangerLabError.invalidProfile("expected 298 factory Keyboard Sets, found \(keyboardSets.count)") }
        guard Set(keyboardSets.map(\.id)).count == keyboardSets.count else { throw ArrangerLabError.invalidProfile("Keyboard Set IDs must be unique") }
        guard Set(keyboardSets.map(\.address)).count == keyboardSets.count else { throw ArrangerLabError.invalidProfile("Keyboard Set MIDI addresses must be unique") }
    }

    public static func bundledPA700() throws -> KeyboardSetLibraryCatalog {
        guard let url = Bundle.module.url(forResource: "pa700-keyboard-sets", withExtension: "json") else {
            throw ArrangerLabError.invalidProfile("bundled PA700 Keyboard Set Library catalog missing")
        }
        let catalog = try JSONDecoder().decode(KeyboardSetLibraryCatalog.self, from: Data(contentsOf: url))
        try catalog.validate()
        return catalog
    }
}
