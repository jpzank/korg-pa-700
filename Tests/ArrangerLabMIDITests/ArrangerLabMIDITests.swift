import Testing
@testable import ArrangerLabCore
@testable import ArrangerLabMIDI

@Suite("ArrangerLabMIDI")
struct ArrangerLabMIDITests {
    @Test func decoderPreservesRealtimeInsideFragmentedSysEx() {
        let decoder = MIDIStreamDecoder()
        #expect(decoder.feed([0xF0, 0x7E, 0x7F]).isEmpty)
        let messages = decoder.feed([0xF8, 0x06, 0x01, 0xF7])
        #expect(messages.map(\.message) == [
            .realtime(0xF8),
            .systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
        ])
    }
}
