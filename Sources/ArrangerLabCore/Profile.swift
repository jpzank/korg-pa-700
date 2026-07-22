import Foundation

public struct IdentitySignature: Codable, Equatable, Sendable {
    public let manufacturer: UInt8
    public let family: [UInt8]
    public let model: [UInt8]
    public let responsePrefix: [UInt8]
}

public struct ProfileEvidence: Codable, Equatable, Sendable {
    public let kind: String
    public let firmware: String
    public let bytes: [UInt8]?
    public let note: String
    public let capturedAt: String

    public init(kind: String, firmware: String, bytes: [UInt8]?, note: String, capturedAt: String) {
        self.kind = kind
        self.firmware = firmware
        self.bytes = bytes
        self.note = note
        self.capturedAt = capturedAt
    }
}

public struct ProfileMapping: Codable, Equatable, Sendable {
    public let id: String
    public var status: MappingStatus
    public let template: String
    public let evidence: [ProfileEvidence]
}

public struct DevicePreset: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let bankMSB: UInt8
    public let bankLSB: UInt8
    public let program: UInt8
    public let status: MappingStatus
    public let evidence: [ProfileEvidence]

    public init(id: String, displayName: String, bankMSB: UInt8, bankLSB: UInt8, program: UInt8, status: MappingStatus, evidence: [ProfileEvidence]) {
        self.id = id
        self.displayName = displayName
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.program = program
        self.status = status
        self.evidence = evidence
    }
}

public struct InstrumentProfile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let manufacturer: String
    public let model: String
    public let firmware: String
    public let identitySignatures: [IdentitySignature]
    public let aliases: [String: KeyboardPartTarget]
    public let requiredConfiguration: [String]
    public let channels: [String: UInt8]
    public var mappings: [String: ProfileMapping]
    public let presets: [DevicePreset]

    public init(schemaVersion: Int, id: String, manufacturer: String, model: String, firmware: String, identitySignatures: [IdentitySignature], aliases: [String: KeyboardPartTarget], requiredConfiguration: [String], channels: [String: UInt8], mappings: [String: ProfileMapping], presets: [DevicePreset]) {
        self.schemaVersion = schemaVersion; self.id = id; self.manufacturer = manufacturer; self.model = model; self.firmware = firmware
        self.identitySignatures = identitySignatures; self.aliases = aliases; self.requiredConfiguration = requiredConfiguration
        self.channels = channels; self.mappings = mappings; self.presets = presets
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw ArrangerLabError.invalidProfile("unsupported schema version \(schemaVersion)") }
        guard !id.isEmpty, !model.isEmpty else { throw ArrangerLabError.invalidProfile("id and model are required") }
        guard channels.values.allSatisfy({ (1...16).contains(Int($0)) }) else { throw ArrangerLabError.invalidProfile("channels must be 1...16") }
        guard mappings.allSatisfy({ key, mapping in key == mapping.id }) else {
            throw ArrangerLabError.invalidProfile("mapping dictionary keys must match mapping IDs")
        }
        guard presets.allSatisfy({ !$0.id.isEmpty && !$0.displayName.isEmpty }) else {
            throw ArrangerLabError.invalidProfile("preset IDs and names are required")
        }
        guard Set(presets.map(\.id)).count == presets.count else {
            throw ArrangerLabError.invalidProfile("preset IDs must be unique")
        }
    }

    public static func bundledPA700() throws -> InstrumentProfile {
        let packagedURL = Bundle.main.resourceURL?
            .appendingPathComponent("ArrangerLab_ArrangerLabCore.bundle", isDirectory: true)
            .appendingPathComponent("pa700.json", isDirectory: false)
        let url: URL
        if let packagedURL, FileManager.default.isReadableFile(atPath: packagedURL.path) {
            url = packagedURL
        } else {
            let moduleURL = Bundle.module.bundleURL.appendingPathComponent("pa700.json", isDirectory: false)
            guard FileManager.default.isReadableFile(atPath: moduleURL.path) else {
                throw ArrangerLabError.invalidProfile("bundled PA700 profile missing")
            }
            url = moduleURL
        }
        let profile = try JSONDecoder().decode(InstrumentProfile.self, from: Data(contentsOf: url))
        try profile.validate()
        return profile
    }
}
