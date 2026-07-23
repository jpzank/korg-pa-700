import Foundation
import Testing
@testable import ArrangerLabCore

@Suite("PA700 live state")
struct PA700LiveStateTests {
    private func input(_ message: MIDIMessage, timestamp: UInt64) -> MIDIEvent {
        MIDIEvent(
            timestampNanoseconds: timestamp,
            direction: .input,
            endpointUniqueID: 1,
            endpointName: "Pa700 KEYBOARD",
            rawBytes: message.canonicalBytes,
            message: message
        )
    }

    private func output(_ message: MIDIMessage, timestamp: UInt64) -> MIDIEvent {
        MIDIEvent(
            timestampNanoseconds: timestamp,
            direction: .output,
            endpointUniqueID: 2,
            endpointName: "Pa700 SOUND",
            rawBytes: message.canonicalBytes,
            message: message
        )
    }

    @Test func assemblesPartSoundsAndIgnoresOutputEvents() throws {
        let profile = try InstrumentProfile.bundledPA700()
        let sound = try #require(PA700OfficialSoundCatalog.bundled().sounds.first)
        var reducer = PA700LiveStateReducer(profile: profile, sounds: [sound])

        let bankMSBChanged = reducer.consume(input(.controlChange(channel: 0, controller: 0, value: sound.bankMSB), timestamp: 1))
        let bankLSBChanged = reducer.consume(input(.controlChange(channel: 0, controller: 32, value: sound.bankLSB), timestamp: 2))
        let soundChanged = reducer.consume(input(.programChange(channel: 0, program: sound.program), timestamp: 3))
        #expect(!bankMSBChanged)
        #expect(!bankLSBChanged)
        #expect(soundChanged)
        #expect(reducer.state.parts[.upper1]?.sound.currentValue?.displayName == sound.name)
        #expect(reducer.state.parts[.upper1]?.sound.certainty == .observed)

        let beforeOutput = reducer.state
        let outputChanged = reducer.consume(output(.programChange(channel: 0, program: sound.program &+ 1), timestamp: 4))
        #expect(!outputChanged)
        #expect(reducer.state == beforeOutput)
    }

    @Test func keepsBankAssemblyIndependentPerPartChannel() throws {
        let profile = try InstrumentProfile.bundledPA700()
        var reducer = PA700LiveStateReducer(profile: profile)

        _ = reducer.consume(input(.controlChange(channel: 0, controller: 0, value: 121), timestamp: 1))
        _ = reducer.consume(input(.controlChange(channel: 1, controller: 0, value: 120), timestamp: 2))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 32, value: 4), timestamp: 3))
        _ = reducer.consume(input(.controlChange(channel: 1, controller: 32, value: 5), timestamp: 4))
        _ = reducer.consume(input(.programChange(channel: 1, program: 9), timestamp: 5))
        _ = reducer.consume(input(.programChange(channel: 0, program: 7), timestamp: 6))

        #expect(reducer.state.parts[.upper1]?.sound.currentValue?.address == "121.4.7")
        #expect(reducer.state.parts[.upper2]?.sound.currentValue?.address == "120.5.9")
    }

    @Test func assemblesSongBookNRPNAndPartControls() throws {
        let profile = try InstrumentProfile.bundledPA700()
        var reducer = PA700LiveStateReducer(profile: profile)
        let control: UInt8 = 15

        for (index, message) in [
            MIDIMessage.controlChange(channel: control, controller: 99, value: 2),
            .controlChange(channel: control, controller: 98, value: 64),
            .controlChange(channel: control, controller: 6, value: 90),
            .controlChange(channel: control, controller: 38, value: 0)
        ].enumerated() {
            _ = reducer.consume(input(message, timestamp: UInt64(index + 1)))
        }
        #expect(reducer.state.songBookEntry.currentValue == 9_000)
        #expect(reducer.state.songBookEntry.certainty == .observed)

        _ = reducer.consume(input(.controlChange(channel: 0, controller: 7, value: 95), timestamp: 10))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 11, value: 80), timestamp: 11))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 10, value: 64), timestamp: 12))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 64, value: 127), timestamp: 13))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 91, value: 42), timestamp: 14))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 93, value: 43), timestamp: 15))
        let upper1 = try #require(reducer.state.parts[.upper1])
        #expect(upper1.volume.currentValue == 95)
        #expect(upper1.expression.currentValue == 80)
        #expect(upper1.pan.currentValue == 64)
        #expect(upper1.damper.currentValue == true)
        #expect(upper1.effectSend1.currentValue == 42)
        #expect(upper1.effectSend2.currentValue == 43)
        #expect(reducer.state.hasCurrentIdentifier)
    }

    @Test func controlOnlyTrafficDoesNotPretendToIdentifyThePanel() throws {
        let profile = try InstrumentProfile.bundledPA700()
        var reducer = PA700LiveStateReducer(profile: profile)
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 7, value: 95), timestamp: 1))

        #expect(reducer.state.hasCurrentValues)
        #expect(!reducer.state.hasCurrentIdentifier)
    }

    @Test func observesTransposeAndMarksStateStale() throws {
        let profile = try InstrumentProfile.bundledPA700()
        var reducer = PA700LiveStateReducer(profile: profile)
        let transpose = MIDIMessage.systemExclusive([0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, 61, 0xF7])

        let transposeChanged = reducer.consume(input(transpose, timestamp: 100))
        #expect(transposeChanged)
        #expect(reducer.state.transpose.currentValue == -3)
        #expect(reducer.state.transpose.observedAtNanoseconds == 100)
        reducer.markStale()
        #expect(reducer.state.transpose.currentValue == nil)
        #expect(reducer.state.transpose.value == -3)
        #expect(reducer.state.transpose.certainty == .stale)
        #expect(reducer.state.hasStaleIdentifier)
    }

    @Test func commandedStateKeepsTheExactSentSnapshotAndCanBecomeStale() {
        var preset = ShowPreset(
            songTitle: "Te Vivo",
            arrangerStyleID: "user-jpd-1",
            keyboardSetSlot: 1,
            transposeSemitones: -3
        )
        let itemID = UUID()
        let sentAt = Date(timeIntervalSince1970: 100)
        var commanded = PA700CommandedShowState(
            preset: preset,
            setListItemID: itemID,
            sentAt: sentAt
        )

        preset.transposeSemitones = 4
        #expect(commanded.preset.transposeSemitones == -3)
        #expect(commanded.presetID == preset.id)
        #expect(commanded.setListItemID == itemID)
        #expect(commanded.sentAt == sentAt)
        #expect(commanded.status == .current)

        commanded.markStale()
        #expect(commanded.status == .stale)
        #expect(commanded.preset.transposeSemitones == -3)
    }

    @Test func comparisonChecksOnlyObservedSoundsWithStableIDs() throws {
        let profile = try InstrumentProfile.bundledPA700()
        let sounds = try PA700OfficialSoundCatalog.bundled().sounds
        let concert = try #require(sounds.first)
        let different = try #require(sounds.first(where: {
            $0.bankMSB != concert.bankMSB
                || $0.bankLSB != concert.bankLSB
                || $0.program != concert.program
        }))
        let concertID = "pa700-\(concert.bankMSB)-\(concert.bankLSB)-\(concert.program)"
        var reducer = PA700LiveStateReducer(profile: profile, sounds: [concert, different])
        var parts = ShowPreset.defaultParts()
        let upper1Index = try #require(parts.firstIndex(where: { $0.part == .upper1 }))
        parts[upper1Index].soundID = concertID
        parts[upper1Index].displayName = concert.name
        let preset = ShowPreset(songTitle: "Som", parts: parts)

        let unknown = PA700LiveComparator.compare(state: reducer.state, expected: preset)
        #expect(unknown.status == .unknown)
        #expect(unknown.mismatchedFields.isEmpty)

        _ = reducer.consume(input(.controlChange(channel: 0, controller: 0, value: concert.bankMSB), timestamp: 1))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 32, value: concert.bankLSB), timestamp: 2))
        _ = reducer.consume(input(.programChange(channel: 0, program: concert.program), timestamp: 3))
        let matching = PA700LiveComparator.compare(state: reducer.state, expected: preset)
        #expect(matching.status == .matches)
        #expect(matching.matchedFields == ["Upper 1"])

        _ = reducer.consume(input(.controlChange(channel: 0, controller: 0, value: different.bankMSB), timestamp: 4))
        _ = reducer.consume(input(.controlChange(channel: 0, controller: 32, value: different.bankLSB), timestamp: 5))
        _ = reducer.consume(input(.programChange(channel: 0, program: different.program), timestamp: 6))
        let mismatch = PA700LiveComparator.compare(state: reducer.state, expected: preset)
        #expect(mismatch.status == .mismatch)
        #expect(mismatch.mismatchedFields == ["Upper 1"])
    }

    @Test func infersStyleAndKeyboardSlotThenComparesWithSong() throws {
        let profile = try InstrumentProfile.bundledPA700()
        let style = ArrangerStyle(id: "user-jpd-1", displayName: "JPD", category: "User", bankMSB: 2, bankLSB: 10, program: 0)
        var reducer = PA700LiveStateReducer(profile: profile, styles: [style])

        _ = reducer.consume(input(.controlChange(channel: 15, controller: 0, value: 2), timestamp: 1))
        _ = reducer.consume(input(.controlChange(channel: 15, controller: 32, value: 10), timestamp: 2))
        _ = reducer.consume(input(.programChange(channel: 15, program: 0), timestamp: 3))
        _ = reducer.consume(input(.programChange(channel: 15, program: 64), timestamp: 4))
        _ = reducer.consume(input(.systemExclusive([0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, 61, 0xF7]), timestamp: 5))

        #expect(reducer.state.style.currentValue?.id == style.id)
        #expect(reducer.state.style.certainty == .inferred)
        #expect(reducer.state.keyboardSetSlot.currentValue == 1)
        #expect(reducer.state.keyboardSetSlot.certainty == .inferred)

        let preset = ShowPreset(
            songTitle: "Te Vivo",
            arrangerStyleID: style.id,
            keyboardSetSlot: 1,
            transposeSemitones: -3
        )
        let matching = PA700LiveComparator.compare(state: reducer.state, expected: preset)
        #expect(matching.status == .matches)
        #expect(matching.inferredFields == ["Style", "Keyboard Set"])

        _ = reducer.consume(input(.systemExclusive([0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, 62, 0xF7]), timestamp: 6))
        let mismatch = PA700LiveComparator.compare(state: reducer.state, expected: preset)
        #expect(mismatch.status == .mismatch)
        #expect(mismatch.mismatchedFields == ["Transpose"])
    }

    @Test func doesNotInferStyleFromPartialBankUpdate() throws {
        let profile = try InstrumentProfile.bundledPA700()
        let style = ArrangerStyle(id: "user-jpd-1", displayName: "JPD", category: "User", bankMSB: 2, bankLSB: 10, program: 0)
        var reducer = PA700LiveStateReducer(profile: profile, styles: [style])

        _ = reducer.consume(input(.controlChange(channel: 15, controller: 0, value: 2), timestamp: 1))
        _ = reducer.consume(input(.programChange(channel: 15, program: 0), timestamp: 2))
        #expect(reducer.state.style.currentValue == nil)

        _ = reducer.consume(input(.controlChange(channel: 15, controller: 0, value: 2), timestamp: 3))
        _ = reducer.consume(input(.controlChange(channel: 15, controller: 32, value: 10), timestamp: 4))
        _ = reducer.consume(input(.programChange(channel: 15, program: 0), timestamp: 5))
        #expect(reducer.state.style.currentValue?.id == style.id)
    }

    @Test func discoveryUsesCanonicalInputAndRequiresThreeIdenticalSamples() {
        let useful = input(.programChange(channel: 15, program: 64), timestamp: 1)
        let clock = input(.realtime(0xF8), timestamp: 2)
        let sensing = input(.realtime(0xFE), timestamp: 3)
        let outgoing = output(.programChange(channel: 15, program: 65), timestamp: 4)
        let malformed = MIDIEvent(
            timestampNanoseconds: 5,
            direction: .input,
            endpointUniqueID: 1,
            endpointName: "Pa700 KEYBOARD",
            rawBytes: [0],
            message: .programChange(channel: 15, program: 64)
        )

        let messages = PA700LiveDiscovery.canonicalInputMessages(from: [clock, useful, sensing, outgoing, malformed])
        #expect(messages == [[0xCF, 64]])
        let samples = (1...3).map {
            PA700LiveDiscoverySample(target: .keyboardSet, repetition: $0, messages: messages)
        }
        #expect(PA700LiveDiscovery.hasThreeMatchingSamples(samples, for: .keyboardSet))

        let changed = samples.dropLast() + [
            PA700LiveDiscoverySample(target: .keyboardSet, repetition: 3, messages: [[0xCF, 65]])
        ]
        #expect(!PA700LiveDiscovery.hasThreeMatchingSamples(Array(changed), for: .keyboardSet))
    }
}
