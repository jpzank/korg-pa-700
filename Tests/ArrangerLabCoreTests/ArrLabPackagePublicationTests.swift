import Foundation
import Testing
@testable import ArrangerLabCore

@Suite("ArrLab package publication")
struct ArrLabPackagePublicationTests {
    @Test func publishesCompletePackageAndSelectsUniqueDestination() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("arrlab-publication-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let audioID = UUID()
        let audioBytes = Data("test audio attachment".utf8)
        let audioSource = root.appendingPathComponent("source.wav")
        try audioBytes.write(to: audioSource)
        let experiment = makeExperiment(
            audioEvidence: [makeAudioEvidence(id: audioID, relativePath: "audio/clip.wav")]
        )
        let requestedURL = root
            .appendingPathComponent("Experiment", isDirectory: true)
            .appendingPathExtension("arrlab")

        let firstURL = try ArrLabPackage.publish(
            experiment,
            to: requestedURL,
            audioAttachments: [audioID: audioSource],
            bpm: 60,
            ppqn: 100
        )
        let secondURL = try ArrLabPackage.publish(
            experiment,
            to: requestedURL,
            audioAttachments: [audioID: audioSource],
            bpm: 60,
            ppqn: 100
        )

        #expect(firstURL == requestedURL)
        #expect(secondURL.lastPathComponent == "Experiment-2.arrlab")
        #expect(try ArrLabPackage.load(from: firstURL) == experiment)
        #expect(try ArrLabPackage.load(from: secondURL) == experiment)
        #expect(try ArrLabPackage.loadPublished(from: firstURL) == experiment)
        #expect(try ArrLabPackage.loadPublished(from: secondURL) == experiment)
        #expect(
            try Data(contentsOf: firstURL.appendingPathComponent("audio/clip.wav"))
                == audioBytes
        )
        #expect(
            try String(
                contentsOf: firstURL.appendingPathComponent("export.csv"),
                encoding: .utf8
            ).hasPrefix("tick,status,data1,data2\n")
        )
        #expect(
            try Data(contentsOf: firstURL.appendingPathComponent("export.mid"))
                .starts(with: Data("MThd".utf8))
        )
        #expect(try stagingURLs(in: root).isEmpty)
    }

    @Test func publishesWithoutAudioAttachments() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("arrlab-no-audio-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let experiment = makeExperiment()
        let requestedURL = root
            .appendingPathComponent("No-Audio", isDirectory: true)
            .appendingPathExtension("arrlab")

        let publishedURL = try ArrLabPackage.publish(experiment, to: requestedURL)
        let audioContents = try fm.contentsOfDirectory(
            at: publishedURL.appendingPathComponent("audio"),
            includingPropertiesForKeys: nil
        )

        #expect(publishedURL == requestedURL)
        #expect(audioContents.isEmpty)
        #expect(try ArrLabPackage.load(from: publishedURL) == experiment)
        #expect(try ArrLabPackage.loadPublished(from: publishedURL) == experiment)
        #expect(try stagingURLs(in: root).isEmpty)
    }

    @Test func publishedLoaderRejectsAudioEscapingThroughParentSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("arrlab-symlinked-audio-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let audioID = UUID()
        let audioSource = root.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: audioSource)
        let experiment = makeExperiment(
            audioEvidence: [
                makeAudioEvidence(id: audioID, relativePath: "audio/nested/clip.wav")
            ]
        )
        let packageURL = try ArrLabPackage.publish(
            experiment,
            to: root.appendingPathComponent("Symlinked.arrlab", isDirectory: true),
            audioAttachments: [audioID: audioSource]
        )

        let outsideDirectory = root.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(
            to: outsideDirectory.appendingPathComponent("clip.wav")
        )
        let nestedDirectory = packageURL.appendingPathComponent("audio/nested", isDirectory: true)
        try fm.removeItem(at: nestedDirectory)
        try fm.createSymbolicLink(at: nestedDirectory, withDestinationURL: outsideDirectory)

        #expect(throws: ArrangerLabError.self) {
            _ = try ArrLabPackage.loadPublished(from: packageURL)
        }
    }

    @Test func rejectsUnsafeAudioPathsWithoutEscapingStaging() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("arrlab-unsafe-path-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let audioSource = root.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: audioSource)
        let unsafePaths = [
            "../escape.wav",
            "audio/../escape.wav",
            "/tmp/arrlab-escape.wav",
            "audio\\..\\escape.wav",
            "manifest.json"
        ]

        for (index, relativePath) in unsafePaths.enumerated() {
            let audioID = UUID()
            let experiment = makeExperiment(
                audioEvidence: [makeAudioEvidence(id: audioID, relativePath: relativePath)]
            )
            let requestedURL = root
                .appendingPathComponent("Unsafe-\(index)", isDirectory: true)
                .appendingPathExtension("arrlab")

            #expect(throws: (any Error).self) {
                _ = try ArrLabPackage.publish(
                    experiment,
                    to: requestedURL,
                    audioAttachments: [audioID: audioSource]
                )
            }
            #expect(!fm.fileExists(atPath: requestedURL.path))
            #expect(try stagingURLs(in: root).isEmpty)
        }

        #expect(!fm.fileExists(atPath: root.appendingPathComponent("escape.wav").path))
    }

    @Test func missingReferencedAudioCleansStagingAndPublishesNothing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("arrlab-missing-audio-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let audioID = UUID()
        let experiment = makeExperiment(
            audioEvidence: [makeAudioEvidence(id: audioID, relativePath: "audio/missing.wav")]
        )
        let requestedURL = root
            .appendingPathComponent("Missing-Audio", isDirectory: true)
            .appendingPathExtension("arrlab")

        #expect(throws: (any Error).self) {
            _ = try ArrLabPackage.publish(experiment, to: requestedURL)
        }

        #expect(!fm.fileExists(atPath: requestedURL.path))
        #expect(try stagingURLs(in: root).isEmpty)
    }

    @Test func invalidStagedPackageFailsValidationAndIsRemoved() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("arrlab-invalid-package-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let experiment = makeExperiment(schemaVersion: 2)
        let requestedURL = root
            .appendingPathComponent("Unsupported-Schema", isDirectory: true)
            .appendingPathExtension("arrlab")

        #expect(throws: ArrangerLabError.self) {
            _ = try ArrLabPackage.publish(experiment, to: requestedURL)
        }

        #expect(!fm.fileExists(atPath: requestedURL.path))
        #expect(try stagingURLs(in: root).isEmpty)
    }

    private func makeExperiment(
        schemaVersion: Int = 1,
        audioEvidence: [AudioEvidenceRecord] = []
    ) -> ArrLabExperiment {
        let event = MIDIEvent(
            timestampNanoseconds: 1_000_000_000,
            direction: .output,
            endpointUniqueID: 7,
            endpointName: "Test",
            rawBytes: [0x90, 60, 100],
            message: .noteOn(channel: 0, note: 60, velocity: 100)
        )
        let manifest = ArrLabManifest(
            schemaVersion: schemaVersion,
            experimentID: UUID(),
            title: "Transactional publication",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            hypothesis: "A complete package is published atomically.",
            mappingID: nil,
            mappingStatus: .draft,
            deviceState: .init(
                model: "Test",
                firmware: "1",
                midiPreset: "Test",
                clockSource: "Internal",
                mode: "Test",
                inputEndpoint: "Input",
                outputEndpoint: "Output"
            ),
            annotations: []
        )
        return ArrLabExperiment(
            manifest: manifest,
            events: [event],
            analysis: .init(
                notes: [],
                audioEvidence: audioEvidence,
                manualConfirmations: [],
                spectralDistances: [:]
            )
        )
    }

    private func makeAudioEvidence(
        id: UUID,
        relativePath: String
    ) -> AudioEvidenceRecord {
        AudioEvidenceRecord(
            id: id,
            relativePath: relativePath,
            sampleRate: 48_000,
            channels: 1,
            durationSeconds: 1,
            metrics: .init(
                rms: 0.1,
                peak: 0.2,
                rmsDBFS: -20,
                spectralCentroidHz: 440,
                normalizedSpectrum: [1]
            )
        )
    }

    private func stagingURLs(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".staging") }
    }
}
