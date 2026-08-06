import Foundation
import Testing
@testable import ArrangerLabCore

@Suite("ArrangerLabCore")
struct ArrangerLabCoreTests {
    @Test func capturePackageRoundTripAndMetadataOnlyLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrangerlab-core-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension("arrlab")
        defer { try? FileManager.default.removeItem(at: root) }

        let events = (0..<12_000).map { index in
            MIDIEvent(
                timestampNanoseconds: UInt64(index) * 1_000_000,
                direction: .input,
                endpointUniqueID: 7,
                endpointName: "Test",
                rawBytes: [0x90, 60, 100],
                message: .noteOn(channel: 0, note: 60, velocity: 100)
            )
        }
        let manifest = ArrLabManifest(
            schemaVersion: 1,
            experimentID: UUID(),
            title: "Streaming round trip",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            hypothesis: "",
            mappingID: nil,
            mappingStatus: .draft,
            deviceState: .init(
                model: "Test",
                firmware: "1",
                midiPreset: "Test",
                clockSource: "Internal",
                mode: "Test",
                inputEndpoint: "Test",
                outputEndpoint: "Test"
            ),
            annotations: []
        )
        let experiment = ArrLabExperiment(
            manifest: manifest,
            events: events,
            analysis: .init(notes: [], audioEvidence: [], manualConfirmations: [], spectralDistances: [:])
        )

        try ArrLabPackage.save(experiment, to: root)
        #expect(try ArrLabPackage.loadManifest(from: root) == manifest)
        #expect(try ArrLabPackage.load(from: root) == experiment)
    }

    @Test func streamingCSVMatchesCompatibilityExporter() throws {
        let events = (0..<20).map { index in
            MIDIEvent(
                timestampNanoseconds: UInt64(index) * 100_000_000,
                direction: .output,
                endpointUniqueID: 1,
                endpointName: "Test",
                rawBytes: [0xB0, 7, UInt8(index)],
                message: .controlChange(channel: 0, controller: 7, value: UInt8(index))
            )
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrangerlab-csv-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try CaptureExporter.writeCSV(events: events, to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == CaptureExporter.csv(events: events))
    }

    @Test func profileRejectsDuplicatePresetIDsAndMappingKeyDrift() throws {
        let evidence = ProfileEvidence(kind: "test", firmware: "1", bytes: nil, note: "test", capturedAt: "now")
        let preset = DevicePreset(id: "duplicate", displayName: "Test", bankMSB: 0, bankLSB: 0, program: 0, status: .draft, evidence: [evidence])
        let mapping = ProfileMapping(id: "different", status: .draft, template: "test", evidence: [evidence])
        let profile = InstrumentProfile(
            schemaVersion: 1,
            id: "test",
            manufacturer: "Test",
            model: "Test",
            firmware: "1",
            identitySignatures: [],
            aliases: [:],
            requiredConfiguration: [],
            channels: ["control": 16],
            mappings: ["mapping": mapping],
            presets: [preset, preset]
        )

        #expect(throws: (any Error).self) {
            try profile.validate()
        }
    }

    @Test func legacySchemaOneProfileDecodesWithoutTransportIdentity() throws {
        let profile = InstrumentProfile(
            schemaVersion: 1,
            id: "legacy",
            manufacturer: "Test",
            model: "Legacy",
            firmware: "1",
            identitySignatures: [],
            aliases: [:],
            requiredConfiguration: [],
            channels: ["control": 16],
            mappings: [:],
            presets: []
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(InstrumentProfile.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.transportIdentity == nil)
        try decoded.validate()
    }

    @Test func bundledPA700DeclaresStandardAndOrientalUSBIdentity() throws {
        let profile = try InstrumentProfile.bundledPA700()
        let identity = try #require(profile.transportIdentity)

        #expect(profile.schemaVersion == 2)
        #expect(profile.mappings.count == 37)
        #expect(identity.kind == .usbMIDI)
        #expect(identity.vendorID == 0x0944)
        #expect(identity.variants.map(\.id) == ["standard", "oriental"])
        #expect(identity.variants.map(\.productID) == [0x01C9, 0x01CB])
        #expect(identity.variants[0].sourceAliases.contains("Pa700 _ KEYBOARD"))
        #expect(identity.variants[1].destinationAliases.contains("Pa700 Oriental _ SOUND"))
    }

    @Test func transportIdentityRejectsOutOfRangeIDsAndCrossVariantAliasCollisions() {
        let standard = TransportVariant(
            id: "standard",
            displayName: "Standard",
            productID: 0x01C9,
            modelAliases: ["PA700"],
            sourceAliases: ["Pa700 KEYBOARD"],
            destinationAliases: ["Pa700 SOUND"]
        )
        let colliding = TransportVariant(
            id: "other",
            displayName: "Other",
            productID: 0x01CB,
            modelAliases: ["Other"],
            sourceAliases: ["Pá700 _ keyboard"],
            destinationAliases: ["Other SOUND"]
        )
        let aliasCollision = profile(
            identity: TransportIdentity(
                id: "collision",
                kind: .usbMIDI,
                manufacturer: "KORG",
                vendorID: 0x0944,
                variants: [standard, colliding]
            )
        )
        let invalidVendor = profile(
            identity: TransportIdentity(
                id: "invalid-vendor",
                kind: .usbMIDI,
                manufacturer: "KORG",
                vendorID: 65_536,
                variants: [standard]
            )
        )
        let invalidProduct = profile(
            identity: TransportIdentity(
                id: "invalid-product",
                kind: .usbMIDI,
                manufacturer: "KORG",
                vendorID: 0x0944,
                variants: [
                    TransportVariant(
                        id: "invalid",
                        displayName: "Invalid",
                        productID: -1,
                        modelAliases: ["Invalid"],
                        sourceAliases: ["Invalid KEYBOARD"],
                        destinationAliases: ["Invalid SOUND"]
                    )
                ]
            )
        )

        #expect(throws: (any Error).self) { try aliasCollision.validate() }
        #expect(throws: (any Error).self) { try invalidVendor.validate() }
        #expect(throws: (any Error).self) { try invalidProduct.validate() }
    }

    @Test func transportNameNormalizationIgnoresCaseDiacriticsAndSeparators() {
        #expect(TransportNameNormalizer.normalize("Pá700 Oriental _ KEYBOARD") == "pa700orientalkeyboard")
        #expect(TransportNameNormalizer.normalize("PA700-ORIENTAL keyboard") == "pa700orientalkeyboard")
    }

    private func profile(identity: TransportIdentity) -> InstrumentProfile {
        InstrumentProfile(
            schemaVersion: 2,
            id: "test",
            manufacturer: "Test",
            model: "Test",
            firmware: "1",
            transportIdentity: identity,
            identitySignatures: [],
            aliases: [:],
            requiredConfiguration: [],
            channels: ["control": 16],
            mappings: [:],
            presets: []
        )
    }
}
