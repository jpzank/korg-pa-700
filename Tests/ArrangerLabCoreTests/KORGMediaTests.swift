import Foundation
import Testing
@testable import ArrangerLabCore

private final class KORGMediaProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [KORGMediaScanProgress] = []

    func append(_ value: KORGMediaScanProgress) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var snapshot: [KORGMediaScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Suite("KORG media inspector")
struct KORGMediaTests {
    @Test func recognizesEveryDocumentedExtensionCaseInsensitively() async throws {
        let fixture = try makeFixture(named: "Complete.SET")
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let resources: [(String, Data)] = [
            ("GLOBAL/Index.JBX", Data([0x01])),
            ("MULTISMP/Piano.kMp", Data([0x02])),
            ("PAD/Hit.PAD", Data([0x03])),
            ("SONGBOOK/SONGDB.SBD", Data([0x04])),
            ("STYLE/Ballad.sTy", Data([0x05])),
            ("KEYBOARDSET/Piano.PRF", Data([0x06])),
            ("VOICEPRESET/Lead.VOC", Data([0x07])),
            ("GUITARPRESET/Clean.GTR", Data([0x08])),
            ("SOUND/Factory.PCG", Data([0x09])),
            ("SYSTEM/RESOURCEBROWSER/Browser.TBL", Data([0x0A])),
            ("SYSTEM/RESOURCEBROWSER/Browser.XML", Data([0x0B])),
            ("Song.MID", Data([0x0C])),
            ("Audio.flac", Data([0x0D])),
            ("Checksums.MD5", Data([0x0E])),
            ("Inside.BKP", Data([0x0F])),
            ("KAOSSPRESET/Scene.KAO", Data([0x10]))
        ]
        for (relativePath, contents) in resources {
            try write(contents, to: fixture.source.appendingPathComponent(relativePath))
        }
        try write(Data([0xFF]), to: fixture.source.appendingPathComponent(".DS_Store"))
        try write(Data([0xFF]), to: fixture.source.appendingPathComponent("._Audio.flac"))
        try write(
            Data([0xFF]),
            to: fixture.source.appendingPathComponent("._Metadata/Ignored.STY")
        )

        let progress = KORGMediaProgressRecorder()
        let inventory = try await KORGMediaScanner().scan(at: fixture.source) {
            progress.append($0)
        }

        #expect(inventory.schemaVersion == 1)
        #expect(inventory.containerKind == .set)
        #expect(inventory.sourceName == "Complete.SET")
        #expect(inventory.items.count == resources.count)
        #expect(Set(inventory.items.map(\.resourceKind)) == Set(KORGMediaResourceKind.allCases.filter { $0 != .unknown }))
        #expect(inventory.items.first(where: { $0.relativePath == "SONGBOOK/SONGDB.SBD" })?.functionalDirectory == "SONGBOOK/SONGDB.SBD")
        #expect(inventory.items.first(where: { $0.resourceKind == .bkp })?.status == .opaque)
        #expect(inventory.items.first(where: { $0.resourceKind == .mid })?.status == .recognized)
        #expect(inventory.summary.itemCount == resources.count)
        #expect(inventory.summary.totalBytes == Int64(resources.count))
        #expect(inventory.summary.countsByKind["STY"] == 1)
        #expect(progress.snapshot.last?.discoveredItemCount == resources.count)
        #expect(progress.snapshot.last?.discoveredBytes == Int64(resources.count))
    }

    @Test func recordsUnknownFilesLayoutWarningsAndUnfollowedSymlinks() async throws {
        let fixture = try makeFixture(named: "Structure.set")
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        try write(Data([0x01]), to: fixture.source.appendingPathComponent("SOUND/Wrong.STY"))
        try write(Data([0x02]), to: fixture.source.appendingPathComponent("STYLE/Notes.txt"))

        let externalDirectory = fixture.base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try write(Data([0xAA]), to: externalDirectory.appendingPathComponent("Secret.STY"))
        let link = fixture.source.appendingPathComponent("LinkedOutside", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: externalDirectory)

        let inventory = try await KORGMediaScanner().scan(at: fixture.source)

        let wrong = try #require(inventory.items.first { $0.relativePath == "SOUND/Wrong.STY" })
        #expect(wrong.status == .opaque)
        #expect(wrong.warnings.contains { $0.contains("STYLE") })

        let unknown = try #require(inventory.items.first { $0.relativePath == "STYLE/Notes.txt" })
        #expect(unknown.resourceKind == .unknown)
        #expect(unknown.status == .unknown)

        let skippedLink = try #require(inventory.items.first { $0.relativePath == "LinkedOutside" })
        #expect(skippedLink.id == skippedLink.relativePath)
        #expect(skippedLink.status == .skipped)
        #expect(skippedLink.sizeBytes == 0)
        #expect(!inventory.items.contains { $0.relativePath.contains("Secret.STY") })
    }

    @Test func reportIsDeterministicAndDoesNotExposeAbsolutePathsOrReadFileContents() async throws {
        let fixture = try makeFixture(named: "Stable.SET")
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let resource = fixture.source.appendingPathComponent("STYLE/Original.STY")
        let originalData = Data([0x00, 0x7F, 0x80, 0xFF])
        try write(originalData, to: resource)
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: resource.path)

        let scanner = KORGMediaScanner()
        let inventory = try await scanner.scan(at: fixture.source)
        let firstJSON = try inventory.jsonData()
        let secondJSON = try inventory.jsonData()
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: resource.path)
        let sizeBefore = attributesBefore[.size] as? NSNumber
        let sizeAfter = attributesAfter[.size] as? NSNumber
        let modificationDateBefore = attributesBefore[.modificationDate] as? Date
        let modificationDateAfter = attributesAfter[.modificationDate] as? Date

        #expect(firstJSON == secondJSON)
        #expect(try Data(contentsOf: resource) == originalData)
        #expect(sizeBefore == sizeAfter)
        #expect(modificationDateBefore == modificationDateAfter)

        let report = try #require(String(data: firstJSON, encoding: .utf8))
        #expect(!report.contains(fixture.base.path))
        #expect(!report.contains("timestamp"))
        #expect(report.contains("\"schemaVersion\" : 1"))

        let decoded = try JSONDecoder().decode(KORGMediaInventory.self, from: firstJSON)
        #expect(decoded == inventory)
    }

    @Test func acceptsRecognizedStandaloneResourcesAndRejectsUnsafeInputs() async throws {
        let fixture = try makeFixture(named: "Inputs.SET")
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let standalone = fixture.base.appendingPathComponent("MyStyle.StY")
        try write(Data([0x01]), to: standalone)
        let standaloneInventory = try await KORGMediaScanner().scan(at: standalone)
        #expect(standaloneInventory.containerKind == .resource)
        #expect(standaloneInventory.items.first?.resourceKind == .sty)

        let backup = fixture.base.appendingPathComponent("Factory.BKP")
        try write(Data(), to: backup)
        await expectScannerError(.standaloneBackupNotSupported, scanning: backup)

        let firmware = fixture.base.appendingPathComponent("Operating_System.UPD")
        try write(Data(), to: firmware)
        await expectScannerError(.unsupportedStandaloneResource("UPD"), scanning: firmware)

        let ordinaryDirectory = fixture.base.appendingPathComponent("Ordinary", isDirectory: true)
        try FileManager.default.createDirectory(at: ordinaryDirectory, withIntermediateDirectories: true)
        await expectScannerError(.unsupportedDirectory, scanning: ordinaryDirectory)

        let fakeSETFile = fixture.base.appendingPathComponent("NotAFolder.SET")
        try write(Data(), to: fakeSETFile)
        await expectScannerError(.expectedSETDirectory, scanning: fakeSETFile)

        let rootLink = fixture.base.appendingPathComponent("Alias.SET")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: fixture.source)
        await expectScannerError(.symbolicLinkSourceNotAllowed, scanning: rootLink)
    }

    @Test func reportsProgressWithoutPublishingAnInventoryAfterCancellation() async throws {
        let fixture = try makeFixture(named: "Cancellation.SET")
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        for index in 0..<512 {
            try write(
                Data([UInt8(index % 255)]),
                to: fixture.source.appendingPathComponent("STYLE/\(index).STY")
            )
        }

        let task = Task {
            try await KORGMediaScanner().scan(at: fixture.source)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("A varredura cancelada não deveria publicar um inventário.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Erro inesperado após cancelamento: \(error)")
        }
    }

    private func expectScannerError(
        _ expected: KORGMediaScannerError,
        scanning url: URL
    ) async {
        do {
            _ = try await KORGMediaScanner().scan(at: url)
            Issue.record("Era esperado o erro \(expected).")
        } catch let error as KORGMediaScannerError {
            #expect(error == expected)
            #expect(!error.localizedDescription.isEmpty)
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }

    private func makeFixture(named name: String) throws -> (base: URL, source: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrangerlab-korg-media-\(UUID().uuidString)", isDirectory: true)
        let source = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return (base, source)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}
