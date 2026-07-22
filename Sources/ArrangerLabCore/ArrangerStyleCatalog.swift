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
        let packagedURL = Bundle.main.resourceURL?
            .appendingPathComponent("ArrangerLab_ArrangerLabCore.bundle", isDirectory: true)
            .appendingPathComponent("pa700-styles.json", isDirectory: false)
        let url: URL
        if let packagedURL, FileManager.default.isReadableFile(atPath: packagedURL.path) {
            url = packagedURL
        } else {
            let moduleURL = Bundle.module.bundleURL.appendingPathComponent("pa700-styles.json", isDirectory: false)
            guard FileManager.default.isReadableFile(atPath: moduleURL.path) else {
                throw ArrangerLabError.invalidProfile("bundled PA700 Style catalog missing")
            }
            url = moduleURL
        }
        let catalog = try JSONDecoder().decode(ArrangerStyleCatalog.self, from: Data(contentsOf: url))
        try catalog.validate()
        return catalog
    }
}
