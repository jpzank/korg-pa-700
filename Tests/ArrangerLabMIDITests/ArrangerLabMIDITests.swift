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

    @Test func transportMatcherRecognizesLiveAndFirmwarePA700Names() throws {
        let identity = try pa700Identity()
        let live = TransportMatcher.matches(
            identity: identity,
            sources: [endpoint(1, "Pa700 KEYBOARD", manufacturer: "KORG Inc.", model: "PA700")],
            destinations: [endpoint(2, "Pa700 SOUND", manufacturer: "KORG", model: "PA700")]
        )
        let firmware = TransportMatcher.matches(
            identity: identity,
            sources: [endpoint(3, "Pa700 _ KEYBOARD")],
            destinations: [endpoint(4, "Pa700 _ SOUND")]
        )

        #expect(live.count == 1)
        #expect(live[0].variant.id == "standard")
        #expect(live[0].evidence == [.endpointNames, .manufacturer, .model])
        #expect(firmware.count == 1)
        #expect(firmware[0].variant.id == "standard")
        #expect(firmware[0].evidence == [.endpointNames])
    }

    @Test func transportMatcherKeepsStandardAndOrientalEndpointsInTheirVariants() throws {
        let identity = try pa700Identity()
        let standardOnly = TransportMatcher.matches(
            identity: identity,
            sources: [
                endpoint(1, "Pa700 KEYBOARD"),
                endpoint(2, "Pa700 Oriental KEYBOARD")
            ],
            destinations: [endpoint(3, "Pa700 SOUND")]
        )
        let oriental = TransportMatcher.matches(
            identity: identity,
            sources: [endpoint(4, "PA700 Oriental _ KEYBOARD")],
            destinations: [endpoint(5, "pa700 oriental sound")]
        )

        #expect(standardOnly.count == 1)
        #expect(standardOnly[0].variant.id == "standard")
        #expect(standardOnly[0].source.id == 1)
        #expect(oriental.count == 1)
        #expect(oriental[0].variant.id == "oriental")
    }

    @Test func transportMatcherRejectsPartialAndSimilarNames() throws {
        let identity = try pa700Identity()

        #expect(
            TransportMatcher.matches(
                identity: identity,
                sources: [endpoint(1, "My Pa700 KEYBOARD Controller")],
                destinations: [endpoint(2, "Pa700 SOUND")]
            ).isEmpty
        )
        #expect(
            TransportMatcher.matches(
                identity: identity,
                sources: [endpoint(3, "Pa700 KEYBOARD")],
                destinations: [endpoint(4, "Different SOUND")]
            ).isEmpty
        )
    }

    @Test func transportMatcherReportsEveryCandidateForAmbiguityHandling() throws {
        let identity = try pa700Identity()
        let matches = TransportMatcher.matches(
            identity: identity,
            sources: [
                endpoint(1, "Pa700 KEYBOARD"),
                endpoint(2, "Pa700 _ KEYBOARD")
            ],
            destinations: [
                endpoint(3, "Pa700 SOUND"),
                endpoint(4, "Pa700 _ SOUND")
            ]
        )

        #expect(matches.count == 4)
        #expect(Set(matches.map(\.source.id)) == [1, 2])
        #expect(Set(matches.map(\.destination.id)) == [3, 4])
    }

    private func pa700Identity() throws -> TransportIdentity {
        try #require(InstrumentProfile.bundledPA700().transportIdentity)
    }

    private func endpoint(
        _ id: Int32,
        _ name: String,
        manufacturer: String? = nil,
        model: String? = nil
    ) -> MIDIEndpoint {
        MIDIEndpoint(id: id, name: name, ref: 0, manufacturer: manufacturer, model: model)
    }
}
