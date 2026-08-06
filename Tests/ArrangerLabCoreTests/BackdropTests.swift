import Foundation
import Testing
@testable import ArrangerLabCore

@Suite("Backdrop")
struct BackdropTests {
    private func input(
        _ message: MIDIMessage,
        timestamp: UInt64,
        rawBytes: [UInt8]? = nil
    ) -> MIDIEvent {
        MIDIEvent(
            timestampNanoseconds: timestamp,
            direction: .input,
            endpointUniqueID: 1,
            endpointName: "Pa700 KEYBOARD",
            rawBytes: rawBytes ?? message.canonicalBytes,
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

    @Test func mapsPitchVelocityAndPartChannelsDeterministically() throws {
        let cue = BackdropCue(presetID: UUID(), intensity: 0.7, persistence: 0.5, sensitivity: 0.6)
        var reducer = BackdropEventReducer()
        reducer.activate(cue, at: 1)

        let consumedLow = reducer.consume(input(.noteOn(channel: 0, note: 36, velocity: 40), timestamp: 10))
        let consumedHigh = reducer.consume(input(.noteOn(channel: 3, note: 84, velocity: 120), timestamp: 200_000_000))
        #expect(consumedLow)
        #expect(consumedHigh)
        let low = try #require(reducer.state.strokes.first)
        let high = try #require(reducer.state.strokes.last)

        #expect(low.normalizedX < high.normalizedX)
        #expect(low.normalizedY < high.normalizedY)
        #expect(low.radius < high.radius)
        #expect(low.luminosity < high.luminosity)
        #expect(low.pitchClass == 0)
        #expect(high.channel == 3)
    }

    @Test func acceptsRunningStatusPayloadButRejectsMalformedAndOutgoingEvents() {
        let cue = BackdropCue(presetID: UUID())
        var reducer = BackdropEventReducer()
        reducer.activate(cue, at: 1)

        let runningStatus = input(
            .noteOn(channel: 0, note: 60, velocity: 100),
            timestamp: 2,
            rawBytes: [60, 100]
        )
        let consumedRunningStatus = reducer.consume(runningStatus)
        let consumedOutput = reducer.consume(output(.noteOn(channel: 0, note: 61, velocity: 100), timestamp: 3))
        let consumedMalformed = reducer.consume(input(
            .noteOn(channel: 0, note: 62, velocity: 100),
            timestamp: 4,
            rawBytes: [0]
        ))
        let consumedUnsupportedChannel = reducer.consume(
            input(.noteOn(channel: 4, note: 63, velocity: 100), timestamp: 5)
        )
        #expect(consumedRunningStatus)
        #expect(!consumedOutput)
        #expect(!consumedMalformed)
        #expect(!consumedUnsupportedChannel)
        #expect(reducer.state.strokes.count == 1)
    }

    @Test func sustainDefersReleaseUntilPedalUp() throws {
        let cue = BackdropCue(presetID: UUID())
        var reducer = BackdropEventReducer()
        reducer.activate(cue, at: 1)

        _ = reducer.consume(input(.noteOn(channel: 0, note: 60, velocity: 100), timestamp: 10))
        let strokeID = try #require(reducer.state.strokes.first?.id)
        let sustainEngaged = reducer.consume(
            input(.controlChange(channel: 0, controller: 64, value: 127), timestamp: 20)
        )
        let noteReleasedUnderSustain = reducer.consume(
            input(.noteOff(channel: 0, note: 60, velocity: 0), timestamp: 30)
        )
        #expect(sustainEngaged)
        #expect(noteReleasedUnderSustain)
        #expect(reducer.state.strokes.first(where: { $0.id == strokeID })?.releasedAtNanoseconds == nil)
        #expect(reducer.state.sustainedChannels == [0])

        let sustainReleased = reducer.consume(
            input(.controlChange(channel: 0, controller: 64, value: 0), timestamp: 40)
        )
        #expect(sustainReleased)
        #expect(reducer.state.strokes.first(where: { $0.id == strokeID })?.releasedAtNanoseconds == 40)
        #expect(reducer.state.sustainedChannels.isEmpty)
    }

    @Test func clusteredNotesCreateAChordBloom() {
        let cue = BackdropCue(presetID: UUID())
        var reducer = BackdropEventReducer()
        reducer.activate(cue, at: 1)

        _ = reducer.consume(input(.noteOn(channel: 0, note: 60, velocity: 90), timestamp: 10))
        _ = reducer.consume(input(.noteOn(channel: 0, note: 64, velocity: 90), timestamp: 30_000_000))
        _ = reducer.consume(input(.noteOn(channel: 0, note: 67, velocity: 90), timestamp: 60_000_000))

        #expect(reducer.state.strokes.filter { $0.kind == .note }.count == 3)
        let bloom = reducer.state.strokes.first { $0.kind == .chordBloom }
        #expect(bloom?.clusterSize == 3)
        #expect(bloom?.note == 63)
    }

    @Test func capsStrokeHistoryAndDisconnectKeepsTheCueInAmbientMode() {
        let cue = BackdropCue(presetID: UUID())
        var reducer = BackdropEventReducer(maximumStrokes: 12)
        reducer.activate(cue, at: 1)

        for index in 0..<30 {
            let note = UInt8(40 + index % 30)
            let time = UInt64(index + 1) * 200_000_000
            _ = reducer.consume(input(.noteOn(channel: 0, note: note, velocity: 80), timestamp: time))
            _ = reducer.consume(input(.noteOff(channel: 0, note: note, velocity: 0), timestamp: time + 1))
        }
        #expect(reducer.state.strokes.count <= 12)

        reducer.disconnect(at: 10_000_000_000)
        #expect(reducer.state.activePresetID == cue.presetID)
        #expect(reducer.state.cue == cue)
        #expect(!reducer.state.isBlackout)
        #expect(reducer.state.sustainedChannels.isEmpty)
    }

    @Test func blackoutAndPanicStyleReturnAreExplicit() {
        let cue = BackdropCue(presetID: UUID())
        var reducer = BackdropEventReducer()
        reducer.activate(cue, at: 1)
        _ = reducer.consume(input(.noteOn(channel: 0, note: 60, velocity: 100), timestamp: 2))

        reducer.blackout(at: 3)
        #expect(reducer.state.isBlackout)
        #expect(reducer.state.strokes.isEmpty)
        let consumedDuringBlackout = reducer.consume(
            input(.noteOn(channel: 0, note: 61, velocity: 100), timestamp: 4)
        )
        #expect(!consumedDuringBlackout)

        reducer.returnToAmbient(at: 5)
        #expect(!reducer.state.isBlackout)
        #expect(reducer.state.activePresetID == cue.presetID)
    }

    @Test func cueStoreRoundTripsSeparatelyFromShowPresets() throws {
        let preset = ShowPreset(songTitle: "Example Song")
        let cue = BackdropCue(
            presetID: preset.id,
            palette: .orchid,
            intensity: 0.8,
            persistence: 0.7,
            sensitivity: 0.6,
            ambientMode: .breathing,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backdrop-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try BackdropCueStore.save([cue], to: url)
        #expect(try BackdropCueStore.load(from: url) == [cue])
        #expect(preset == ShowPreset(
            id: preset.id,
            songTitle: "Example Song",
            createdAt: preset.createdAt,
            updatedAt: preset.updatedAt
        ))
    }
}
