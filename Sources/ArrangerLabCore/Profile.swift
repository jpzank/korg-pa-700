import Foundation

public enum TransportKind: String, Codable, Equatable, Sendable {
    case usbMIDI
}

public enum TransportNameNormalizer {
    public static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

public struct TransportVariant: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let productID: Int
    public let modelAliases: [String]
    public let sourceAliases: [String]
    public let destinationAliases: [String]

    public init(
        id: String,
        displayName: String,
        productID: Int,
        modelAliases: [String],
        sourceAliases: [String],
        destinationAliases: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.productID = productID
        self.modelAliases = modelAliases
        self.sourceAliases = sourceAliases
        self.destinationAliases = destinationAliases
    }
}

public struct TransportIdentity: Codable, Equatable, Sendable {
    public let id: String
    public let kind: TransportKind
    public let manufacturer: String
    public let vendorID: Int
    public let variants: [TransportVariant]

    public init(
        id: String,
        kind: TransportKind,
        manufacturer: String,
        vendorID: Int,
        variants: [TransportVariant]
    ) {
        self.id = id
        self.kind = kind
        self.manufacturer = manufacturer
        self.vendorID = vendorID
        self.variants = variants
    }

    fileprivate func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArrangerLabError.invalidProfile("transport identity ID is required")
        }
        guard !manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArrangerLabError.invalidProfile("transport manufacturer is required")
        }
        guard (0...65_535).contains(vendorID) else {
            throw ArrangerLabError.invalidProfile("USB vendor ID must be 0...65535")
        }
        guard !variants.isEmpty else {
            throw ArrangerLabError.invalidProfile("transport identity requires at least one variant")
        }
        guard Set(variants.map(\.id)).count == variants.count else {
            throw ArrangerLabError.invalidProfile("transport variant IDs must be unique")
        }
        guard Set(variants.map(\.productID)).count == variants.count else {
            throw ArrangerLabError.invalidProfile("USB product IDs must be unique")
        }

        var modelOwners: [String: String] = [:]
        var sourceOwners: [String: String] = [:]
        var destinationOwners: [String: String] = [:]

        for variant in variants {
            guard !variant.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !variant.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArrangerLabError.invalidProfile("transport variant IDs and names are required")
            }
            guard (0...65_535).contains(variant.productID) else {
                throw ArrangerLabError.invalidProfile("USB product ID must be 0...65535")
            }
            guard !variant.modelAliases.isEmpty,
                  !variant.sourceAliases.isEmpty,
                  !variant.destinationAliases.isEmpty else {
                throw ArrangerLabError.invalidProfile("transport variants require model, source, and destination aliases")
            }

            try validateAliases(variant.modelAliases, role: "model", variantID: variant.id, owners: &modelOwners)
            try validateAliases(variant.sourceAliases, role: "source", variantID: variant.id, owners: &sourceOwners)
            try validateAliases(variant.destinationAliases, role: "destination", variantID: variant.id, owners: &destinationOwners)
        }
    }

    private func validateAliases(
        _ aliases: [String],
        role: String,
        variantID: String,
        owners: inout [String: String]
    ) throws {
        for alias in aliases {
            let normalized = TransportNameNormalizer.normalize(alias)
            guard !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !normalized.isEmpty else {
                throw ArrangerLabError.invalidProfile("transport \(role) aliases must not be empty")
            }
            if let owner = owners[normalized], owner != variantID {
                throw ArrangerLabError.invalidProfile(
                    "normalized transport \(role) alias collides between variants \(owner) and \(variantID)"
                )
            }
            owners[normalized] = variantID
        }
    }
}

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
    public let transportIdentity: TransportIdentity?
    public let identitySignatures: [IdentitySignature]
    public let aliases: [String: KeyboardPartTarget]
    public let requiredConfiguration: [String]
    public let channels: [String: UInt8]
    public var mappings: [String: ProfileMapping]
    public let presets: [DevicePreset]

    public init(
        schemaVersion: Int,
        id: String,
        manufacturer: String,
        model: String,
        firmware: String,
        transportIdentity: TransportIdentity? = nil,
        identitySignatures: [IdentitySignature],
        aliases: [String: KeyboardPartTarget],
        requiredConfiguration: [String],
        channels: [String: UInt8],
        mappings: [String: ProfileMapping],
        presets: [DevicePreset]
    ) {
        self.schemaVersion = schemaVersion; self.id = id; self.manufacturer = manufacturer; self.model = model; self.firmware = firmware
        self.transportIdentity = transportIdentity
        self.identitySignatures = identitySignatures; self.aliases = aliases; self.requiredConfiguration = requiredConfiguration
        self.channels = channels; self.mappings = mappings; self.presets = presets
    }

    public func validate() throws {
        guard (1...2).contains(schemaVersion) else { throw ArrangerLabError.invalidProfile("unsupported schema version \(schemaVersion)") }
        guard !id.isEmpty, !model.isEmpty else { throw ArrangerLabError.invalidProfile("id and model are required") }
        if schemaVersion == 1, transportIdentity != nil {
            throw ArrangerLabError.invalidProfile("transport identity requires profile schema version 2")
        }
        try transportIdentity?.validate()
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
        guard let url = Bundle.module.url(forResource: "pa700", withExtension: "json") else {
            throw ArrangerLabError.invalidProfile("bundled PA700 profile missing")
        }
        let profile = try JSONDecoder().decode(InstrumentProfile.self, from: Data(contentsOf: url))
        try profile.validate()
        return profile
    }
}
