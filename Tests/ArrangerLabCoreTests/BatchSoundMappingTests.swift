import Foundation
import Testing
@testable import ArrangerLabCore

@Suite("Batch sound mapping")
struct BatchSoundMappingTests {
    @Test func existingAddressesAreRecapturedAndImportedWithoutReordering() {
        let selection = MIDIProgramSelection(channel: 0, bankMSB: 121, bankLSB: 40, program: 16)
        let captured = BatchSoundEntry(
            selection: selection,
            displayName: "Captured Organ",
            occurrenceCount: 1,
            source: .midiCapture
        )
        let untouched = BatchSoundEntry(
            selection: .init(channel: 0, bankMSB: 121, bankLSB: 40, program: 17),
            displayName: "Untouched",
            occurrenceCount: 0,
            source: .officialManual
        )
        var collector = BatchSoundCollector(catalog: catalog(entries: [captured, untouched]))

        _ = collector.consume(input(.controlChange(channel: 0, controller: 0, value: 121)))
        _ = collector.consume(input(.controlChange(channel: 0, controller: 32, value: 40)))
        let recaptured = collector.consume(
            input(.programChange(channel: 0, program: 16)),
            now: Date(timeIntervalSince1970: 10)
        )
        let summary = collector.importOfficialSounds(
            [
                officialSound(
                    name: "Official Organ",
                    selection: selection
                ),
                officialSound(
                    name: "New Organ",
                    selection: .init(channel: 0, bankMSB: 121, bankLSB: 40, program: 18)
                )
            ],
            now: Date(timeIntervalSince1970: 11)
        )

        #expect(recaptured?.id == captured.id)
        #expect(collector.catalog.entries.map(\.id) == [
            captured.id,
            untouched.id,
            BatchSoundEntry.identifier(
                for: .init(channel: 0, bankMSB: 121, bankLSB: 40, program: 18)
            )
        ])
        #expect(collector.catalog.entries[0].occurrenceCount == 2)
        #expect(collector.catalog.entries[0].displayName == "Captured Organ")
        #expect(collector.catalog.entries[0].library == "Factory")
        #expect(summary == .init(inserted: 1, enriched: 1, preservedCapturedNames: 1))
    }

    @Test func removingAnEntryRebuildsShiftedIndexes() {
        let removableSelection = MIDIProgramSelection(channel: 0, bankMSB: 121, bankLSB: 1, program: 0)
        let survivorSelection = MIDIProgramSelection(channel: 0, bankMSB: 121, bankLSB: 1, program: 1)
        let removable = BatchSoundEntry(
            selection: removableSelection,
            displayName: "Removable",
            occurrenceCount: 0,
            source: .officialManual
        )
        let survivor = BatchSoundEntry(
            selection: survivorSelection,
            displayName: "Survivor",
            occurrenceCount: 0,
            source: .officialManual
        )
        var collector = BatchSoundCollector(catalog: catalog(entries: [removable, survivor]))

        _ = collector.beginScreen(now: Date(timeIntervalSince1970: 20))
        _ = collector.consume(input(.controlChange(channel: 0, controller: 0, value: 121)))
        _ = collector.consume(input(.controlChange(channel: 0, controller: 32, value: 1)))
        _ = collector.consume(
            input(.programChange(channel: 0, program: 0)),
            now: Date(timeIntervalSince1970: 21)
        )
        let removed = collector.undoLastScreenCapture(now: Date(timeIntervalSince1970: 22))

        collector.rename(
            id: removable.id,
            displayName: "Must remain removed",
            now: Date(timeIntervalSince1970: 23)
        )
        collector.rename(
            id: survivor.id,
            displayName: "Renamed survivor",
            now: Date(timeIntervalSince1970: 24)
        )
        let summary = collector.importOfficialSounds(
            [officialSound(name: "Restored", selection: removableSelection)],
            now: Date(timeIntervalSince1970: 25)
        )
        collector.setFavorite(
            id: removable.id,
            isFavorite: true,
            now: Date(timeIntervalSince1970: 26)
        )

        #expect(removed?.id == removable.id)
        #expect(collector.catalog.entries.count == 2)
        #expect(collector.catalog.entries[0].id == survivor.id)
        #expect(collector.catalog.entries[0].displayName == "Renamed survivor")
        #expect(collector.catalog.entries[1].id == removable.id)
        #expect(collector.catalog.entries[1].displayName == "Restored")
        #expect(collector.catalog.entries[1].isFavorite)
        #expect(summary == .init(inserted: 1, enriched: 0, preservedCapturedNames: 0))
    }

    @Test func duplicateIdentityKeepsFirstEntrySemantics() {
        let selection = MIDIProgramSelection(channel: 0, bankMSB: 121, bankLSB: 2, program: 3)
        let first = BatchSoundEntry(
            selection: selection,
            displayName: "First",
            occurrenceCount: 1
        )
        let second = BatchSoundEntry(
            selection: selection,
            displayName: "Second",
            occurrenceCount: 4
        )
        var collector = BatchSoundCollector(catalog: catalog(entries: [first, second]))

        collector.rename(id: first.id, displayName: "Renamed first")
        _ = collector.consume(input(.controlChange(channel: 0, controller: 0, value: 121)))
        _ = collector.consume(input(.controlChange(channel: 0, controller: 32, value: 2)))
        _ = collector.consume(input(.programChange(channel: 0, program: 3)))

        #expect(collector.catalog.entries[0].displayName == "Renamed first")
        #expect(collector.catalog.entries[0].occurrenceCount == 2)
        #expect(collector.catalog.entries[1].displayName == "Second")
        #expect(collector.catalog.entries[1].occurrenceCount == 4)
    }

    private func catalog(entries: [BatchSoundEntry]) -> BatchSoundCatalog {
        BatchSoundCatalog(
            model: "PA700",
            firmware: "1.5.0",
            midiPreset: "ArrangerLab",
            entries: entries
        )
    }

    private func officialSound(
        name: String,
        selection: MIDIProgramSelection
    ) -> PA700OfficialSound {
        PA700OfficialSound(
            name: name,
            bankMSB: selection.bankMSB,
            bankLSB: selection.bankLSB,
            program: selection.program,
            library: "Factory",
            category: "Keyboard"
        )
    }

    private func input(_ message: MIDIMessage) -> MIDIEvent {
        MIDIEvent(
            timestampNanoseconds: 1,
            direction: .input,
            endpointUniqueID: 1,
            endpointName: "Test",
            rawBytes: message.canonicalBytes,
            message: message
        )
    }
}
