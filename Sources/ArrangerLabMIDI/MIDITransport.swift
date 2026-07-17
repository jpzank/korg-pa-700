import ArrangerLabCore
import CoreAudio
import CoreMIDI
import Foundation

public struct MIDIEndpoint: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let ref: MIDIEndpointRef
    public init(id: Int32, name: String, ref: MIDIEndpointRef) { self.id = id; self.name = name; self.ref = ref }
}

public final class MIDITransport: @unchecked Sendable {
    public var onEndpointsChanged: (([MIDIEndpoint], [MIDIEndpoint]) -> Void)?
    public var onEvent: ((MIDIEvent) -> Void)?
    public var onFailure: ((Error) -> Void)?

    public private(set) var sources: [MIDIEndpoint] = []
    public private(set) var destinations: [MIDIEndpoint] = []
    public private(set) var selectedSource: MIDIEndpoint?
    public private(set) var selectedDestination: MIDIEndpoint?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private let decoder = MIDIStreamDecoder()
    private let sendQueue = DispatchQueue(label: "arrangerlab.midi.send", qos: .userInteractive)
    private var clockTimer: DispatchSourceTimer?
    private var isClosed = false
    private var isPanicking = false

    public init() throws {
        try check(MIDIClientCreateWithBlock("Arranger Lab" as CFString, &client) { [weak self] _ in self?.refreshEndpoints() })
        try check(MIDIInputPortCreateWithBlock(client, "Arranger Lab Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.receive(packetList)
        })
        try check(MIDIOutputPortCreate(client, "Arranger Lab Output" as CFString, &outputPort))
        refreshEndpoints()
    }

    deinit { close() }

    public func refreshEndpoints() {
        sources = (0..<MIDIGetNumberOfSources()).compactMap { endpoint(MIDIGetSource($0)) }
        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { endpoint(MIDIGetDestination($0)) }

        if let selectedSource, !sources.contains(where: { $0.id == selectedSource.id }) {
            try? panic()
            self.selectedSource = nil
            decoder.reset()
        }
        if let selectedDestination, !destinations.contains(where: { $0.id == selectedDestination.id }) {
            stopClock(sendStop: false)
            self.selectedDestination = nil
        }
        onEndpointsChanged?(sources, destinations)
    }

    public func connect(sourceID: Int32?, destinationID: Int32?) throws {
        stopClock()
        if let current = selectedSource { MIDIPortDisconnectSource(inputPort, current.ref) }
        selectedSource = sourceID.flatMap { id in sources.first(where: { $0.id == id }) }
        selectedDestination = destinationID.flatMap { id in destinations.first(where: { $0.id == id }) }
        if let source = selectedSource { try check(MIDIPortConnectSource(inputPort, source.ref, nil)) }
        decoder.reset()
    }

    public func autoConnectPA700() throws -> Bool {
        refreshEndpoints()
        guard let source = sources.first(where: { $0.name.localizedCaseInsensitiveContains("Pa700 KEYBOARD") }),
              let destination = destinations.first(where: { $0.name.localizedCaseInsensitiveContains("Pa700 SOUND") }) else { return false }
        try connect(sourceID: source.id, destinationID: destination.id)
        return true
    }

    public func send(_ message: MIDIMessage, timestamp: MIDITimeStamp = 0) throws {
        guard let destination = selectedDestination else { throw ArrangerLabError.endpointUnavailable }
        let bytes = message.canonicalBytes
        guard bytes.count <= 256 else { throw ArrangerLabError.invalidValue("MIDI 1.0 packet exceeds 256 bytes") }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = bytes.withUnsafeBufferPointer { pointer in
            MIDIPacketListAdd(&packetList, 1_024, packet, timestamp, bytes.count, pointer.baseAddress!)
        }
        let status = MIDISend(outputPort, destination.ref, &packetList)
        do { try check(status) }
        catch { if !isPanicking { onFailure?(error) }; throw error }
        onEvent?(.init(timestampNanoseconds: monotonicNanoseconds(), direction: .output, endpointUniqueID: destination.id, endpointName: destination.name, rawBytes: bytes, message: message))
    }

    public func sendScheduled(_ messages: [ScheduledMIDIMessage]) throws {
        guard messages.count <= 4_096 else { throw ArrangerLabError.queueFull }
        var previousOffset: UInt64 = 0
        for scheduled in messages {
            let delay = scheduled.offsetNanoseconds >= previousOffset ? scheduled.offsetNanoseconds - previousOffset : 0
            if delay > 0 { Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000) }
            try send(scheduled.message)
            previousOffset = scheduled.offsetNanoseconds
        }
    }

    public func replay(_ events: [MIDIEvent], speed: Double = 1, range: ClosedRange<UInt64>? = nil, allowKnownSysEx: Bool = false) throws {
        guard speed > 0 else { throw ArrangerLabError.invalidValue("replay speed must be positive") }
        let selected = events.filter { event in
            guard event.direction == .output else { return false }
            if let range, !range.contains(event.timestampNanoseconds) { return false }
            if case .systemExclusive = event.message, !allowKnownSysEx { return false }
            return true
        }
        guard let first = selected.first else { return }
        var previous = first.timestampNanoseconds
        defer { try? panic() }
        for event in selected {
            let delay = event.timestampNanoseconds - previous
            if delay > 0 { Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000 / speed) }
            if let message = event.message { try send(message) }
            previous = event.timestampNanoseconds
        }
    }

    public func startClock(bpm: Double = 120) throws {
        guard (20...300).contains(bpm) else { throw ArrangerLabError.invalidValue("BPM must be 20...300") }
        stopClock(sendStop: false)
        try send(.realtime(0xFA))
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        let interval = 60 / bpm / 24
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in try? self?.send(.realtime(0xF8)) }
        clockTimer = timer
        timer.resume()
    }

    public func stopClock(sendStop: Bool = true) {
        clockTimer?.cancel(); clockTimer = nil
        if sendStop { try? send(.realtime(0xFC)) }
        try? panic()
    }

    public func panic() throws {
        guard selectedDestination != nil else { return }
        guard !isPanicking else { return }
        isPanicking = true
        defer { isPanicking = false }
        for channel in UInt8(0)...15 {
            try? send(.controlChange(channel: channel, controller: 64, value: 0))
            try? send(.controlChange(channel: channel, controller: 123, value: 0))
            try? send(.controlChange(channel: channel, controller: 120, value: 0))
        }
        try? send(.realtime(0xFC))
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        stopClock()
        if let source = selectedSource { MIDIPortDisconnectSource(inputPort, source.ref) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        guard let source = selectedSource else { return }
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
            for decoded in decoder.feed(bytes) {
                let nanoseconds = packet.timeStamp == 0 ? monotonicNanoseconds() : AudioConvertHostTimeToNanos(packet.timeStamp)
                onEvent?(.init(timestampNanoseconds: nanoseconds, direction: .input, endpointUniqueID: source.id, endpointName: source.name, rawBytes: decoded.rawBytes, message: decoded.message))
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func endpoint(_ ref: MIDIEndpointRef) -> MIDIEndpoint? {
        guard ref != 0 else { return nil }
        var id: Int32 = 0
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &id) == noErr,
              MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &name) == noErr else { return nil }
        return MIDIEndpoint(id: id, name: name?.takeRetainedValue() as String? ?? "MIDI \(id)", ref: ref)
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
