import Foundation
import Testing
@testable import ArrangerLabCore

@Suite("Capture export ordering")
struct CaptureOrderingTests {
    @Test func csvSortsOutOfOrderEventsWithoutUnsignedUnderflow() {
        let later = event(timestamp: 2_000_000_000, note: 62)
        let earlier = event(timestamp: 1_000_000_000, note: 60)

        let csv = CaptureExporter.csv(events: [later, earlier], bpm: 60, ppqn: 100)

        #expect(csv.contains("0,144,60,100"))
        #expect(csv.contains("100,144,62,100"))
        #expect(csv.range(of: "0,144,60,100")!.lowerBound < csv.range(of: "100,144,62,100")!.lowerBound)
    }

    @Test func equalTimestampsPreserveArrivalOrder() {
        let first = event(timestamp: 1_000_000_000, note: 62)
        let second = event(timestamp: 1_000_000_000, note: 60)

        let csv = CaptureExporter.csv(events: [first, second], bpm: 60, ppqn: 100)

        #expect(csv.range(of: "0,144,62,100")!.lowerBound < csv.range(of: "0,144,60,100")!.lowerBound)
        #expect(CaptureExporter.smf(events: [first, second]).starts(with: Data("MThd".utf8)))
    }

    private func event(timestamp: UInt64, note: UInt8) -> MIDIEvent {
        MIDIEvent(
            timestampNanoseconds: timestamp,
            direction: .output,
            endpointUniqueID: 1,
            endpointName: "Test",
            rawBytes: [0x90, note, 100],
            message: .noteOn(channel: 0, note: note, velocity: 100)
        )
    }
}
