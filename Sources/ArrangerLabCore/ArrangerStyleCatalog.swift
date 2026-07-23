import Foundation

public struct ArrangerStyle: Codable, Equatable, Identifiable, Sendable {
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

    public var libraryName: String { bankMSB == 2 ? "User" : "Factory" }

    public var userBankName: String? {
        guard bankMSB == 2 else { return nil }
        return Self.userBankNames[bankLSB]
    }

    public static let userBankNames: [UInt8: String] = [
        0: "User 1",
        1: "User 2",
        2: "User 3",
        3: "User 4",
        4: "User 5",
        5: "User 6",
        6: "PW",
        7: "Halloween",
        8: "Sertanejo K",
        9: "4 Bloco",
        10: "JPD",
        11: "User 12"
    ]
}

public struct ArrangerStyleCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let model: String
    public let firmware: String
    public let source: String
    public let styles: [ArrangerStyle]

    public init(schemaVersion: Int, model: String, firmware: String, source: String, styles: [ArrangerStyle]) {
        self.schemaVersion = schemaVersion
        self.model = model
        self.firmware = firmware
        self.source = source
        self.styles = styles
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw ArrangerLabError.invalidProfile("unsupported Style catalog schema") }
        guard model == "PA700", firmware == "1.5.0" else { throw ArrangerLabError.invalidProfile("Style catalog does not match PA700 firmware 1.5.0") }
        let factoryStyles = styles.filter { $0.category != "User" }
        guard factoryStyles.count == 379 else { throw ArrangerLabError.invalidProfile("expected 379 factory Styles, found \(factoryStyles.count)") }
        guard Set(styles.map(\.id)).count == styles.count else { throw ArrangerLabError.invalidProfile("Style IDs must be unique") }
        guard Set(styles.map(\.address)).count == styles.count else { throw ArrangerLabError.invalidProfile("Style MIDI addresses must be unique") }
    }

    public static func bundledPA700() throws -> ArrangerStyleCatalog {
        guard let url = Bundle.module.url(forResource: "pa700-styles", withExtension: "json") else {
            throw ArrangerLabError.invalidProfile("bundled PA700 Style catalog missing")
        }
        let catalog = try JSONDecoder().decode(ArrangerStyleCatalog.self, from: Data(contentsOf: url))
        try catalog.validate()
        return catalog
    }
}
