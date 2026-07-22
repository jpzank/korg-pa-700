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
}
