import Testing
@testable import ArrangerLabCore

@Suite("MIDI stream decoder safety")
struct MIDIStreamDecoderSafetyTests {
    @Test func oversizedSysExIsDroppedAndTheDecoderRecovers() {
        let decoder = MIDIStreamDecoder(maximumSysExBytes: 4)
        var issues: [MIDIStreamDecoderIssue] = []

        let messages = decoder.feed(
            [0xF0, 0x01, 0x02, 0x03, 0x04, 0x90, 60, 100],
            onIssue: { issues.append($0) }
        )

        #expect(issues == [.systemExclusiveTooLarge(limit: 4)])
        #expect(messages == [
            .init(message: .noteOn(channel: 0, note: 60, velocity: 100), rawBytes: [0x90, 60, 100])
        ])
    }

    @Test func completeSysExAtTheLimitIsAccepted() {
        let decoder = MIDIStreamDecoder(maximumSysExBytes: 4)
        let messages = decoder.feed([0xF0, 0x01, 0x02, 0xF7])

        #expect(messages == [
            .init(message: .systemExclusive([0xF0, 0x01, 0x02, 0xF7]), rawBytes: [0xF0, 0x01, 0x02, 0xF7])
        ])
    }
}
