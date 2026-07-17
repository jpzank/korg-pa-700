import Foundation

public struct PA700OfficialSound: Codable, Equatable, Sendable {
    public let name: String
    public let bankMSB: UInt8
    public let bankLSB: UInt8
    public let program: UInt8
    public let library: String
    public let category: String
    public let manualPage: Int

    public var selection: MIDIProgramSelection {
        MIDIProgramSelection(channel: 0, bankMSB: bankMSB, bankLSB: bankLSB, program: program)
    }
}

public struct PA700UserSlotRange: Codable, Equatable, Sendable {
    public let bankMSB: Int
    public let bankLSB: String
    public let program: String
    public let count: Int
}

public struct PA700OfficialSoundCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let model: String
    public let firmware: String
    public let source: String
    public let userSlots: PA700UserSlotRange
    public let sounds: [PA700OfficialSound]

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "PA700OfficialSounds", withExtension: "json") else {
            throw ArrangerLabError.corruptCapture("bundled PA700 sound catalog missing")
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1, catalog.model == "PA700" else {
            throw ArrangerLabError.corruptCapture("unsupported PA700 sound catalog")
        }
        return catalog
    }

    public var libraryCounts: [String: Int] {
        Dictionary(grouping: sounds, by: \.library).mapValues(\.count)
    }
}
