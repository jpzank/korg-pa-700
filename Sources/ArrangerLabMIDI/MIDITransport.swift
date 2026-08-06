import ArrangerLabCore
import CoreAudio
import CoreMIDI
import Foundation

public struct MIDIEndpoint: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let ref: MIDIEndpointRef
    public let manufacturer: String?
    public let model: String?

    public init(
        id: Int32,
        name: String,
        ref: MIDIEndpointRef,
        manufacturer: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.ref = ref
        self.manufacturer = manufacturer
        self.model = model
    }
}

public enum TransportMatchEvidence: String, Codable, Equatable, Sendable {
    case endpointNames
    case manufacturer
    case model
}

public struct TransportMatch: Equatable, Sendable {
    public let identityID: String
    public let variant: TransportVariant
    public let source: MIDIEndpoint
    public let destination: MIDIEndpoint
    public let evidence: [TransportMatchEvidence]

    public init(
        identityID: String,
        variant: TransportVariant,
        source: MIDIEndpoint,
        destination: MIDIEndpoint,
        evidence: [TransportMatchEvidence]
    ) {
        self.identityID = identityID
        self.variant = variant
        self.source = source
        self.destination = destination
        self.evidence = evidence
    }
}

public enum TransportMatchResult: Equatable, Sendable {
    case connected(TransportMatch)
    case notFound
    case ambiguous([TransportMatch])
}

public enum TransportMatcher {
    public static func matches(
        identity: TransportIdentity,
        sources: [MIDIEndpoint],
        destinations: [MIDIEndpoint]
    ) -> [TransportMatch] {
        let manufacturerAliases = [identity.manufacturer]
        var matches: [TransportMatch] = []

        for variant in identity.variants {
            let sourceAliases = Set(variant.sourceAliases.map(TransportNameNormalizer.normalize))
            let destinationAliases = Set(variant.destinationAliases.map(TransportNameNormalizer.normalize))
            let matchingSources = sources.filter {
                sourceAliases.contains(TransportNameNormalizer.normalize($0.name))
            }
            let matchingDestinations = destinations.filter {
                destinationAliases.contains(TransportNameNormalizer.normalize($0.name))
            }

            for source in matchingSources {
                for destination in matchingDestinations {
                    var evidence: [TransportMatchEvidence] = [.endpointNames]
                    if metadataMatches(
                        values: [source.manufacturer, destination.manufacturer],
                        aliases: manufacturerAliases
                    ) {
                        evidence.append(.manufacturer)
                    }
                    if metadataMatches(
                        values: [source.model, destination.model],
                        aliases: variant.modelAliases
                    ) {
                        evidence.append(.model)
                    }
                    matches.append(
                        TransportMatch(
                            identityID: identity.id,
                            variant: variant,
                            source: source,
                            destination: destination,
                            evidence: evidence
                        )
                    )
                }
            }
        }

        return matches.sorted {
            if $0.variant.id != $1.variant.id { return $0.variant.id < $1.variant.id }
            if $0.source.id != $1.source.id { return $0.source.id < $1.source.id }
            return $0.destination.id < $1.destination.id
        }
    }

    private static func metadataMatches(values: [String?], aliases: [String]) -> Bool {
        let normalizedAliases = aliases
            .map(TransportNameNormalizer.normalize)
            .filter { !$0.isEmpty }
        return values.compactMap { $0 }.contains { value in
            let normalizedValue = TransportNameNormalizer.normalize(value)
            guard !normalizedValue.isEmpty else { return false }
            return normalizedAliases.contains {
                normalizedValue == $0 || normalizedValue.contains($0) || $0.contains(normalizedValue)
            }
        }
    }
}

private final class MIDIConnectionContext: @unchecked Sendable {
    let source: MIDIEndpoint
    let generation: UInt64
    let sessionID: UUID

    init(source: MIDIEndpoint, generation: UInt64, sessionID: UUID) {
        self.source = source
        self.generation = generation
        self.sessionID = sessionID
    }
}

public final class MIDITransport: @unchecked Sendable {
    public var onEndpointsChanged: (([MIDIEndpoint], [MIDIEndpoint]) -> Void)?
    public var onEvent: ((MIDIEvent) -> Void)?
    public var onFailure: ((Error) -> Void)?

    public var sources: [MIDIEndpoint] { withStateLock { storedSources } }
    public var destinations: [MIDIEndpoint] { withStateLock { storedDestinations } }
    public var selectedSource: MIDIEndpoint? { withStateLock { storedSelectedSource } }
    public var selectedDestination: MIDIEndpoint? { withStateLock { storedSelectedDestination } }
    public var isCurrentConnectionAuthorized: Bool {
        withStateLock {
            !requiresSessionAuthorization
                || (authorizedGeneration == connectionGeneration
                    && authorizedSessionID == currentSessionID
                    && storedSelectedSource != nil
                    && storedSelectedDestination != nil)
        }
    }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private let decoder = MIDIStreamDecoder()
    private let stateLock = NSRecursiveLock()
    private let sendQueue = DispatchQueue(label: "arrangerlab.midi.send", qos: .userInteractive)
    private let requiresSessionAuthorization: Bool
    private var storedSources: [MIDIEndpoint] = []
    private var storedDestinations: [MIDIEndpoint] = []
    private var storedSelectedSource: MIDIEndpoint?
    private var storedSelectedDestination: MIDIEndpoint?
    private var connectionGeneration: UInt64 = 0
    private var currentSessionID = UUID()
    private var authorizedGeneration: UInt64?
    private var authorizedSessionID: UUID?
    private var scheduleEpoch: UInt64 = 0
    private var activeScheduleID: UUID?
    private var connectionContexts: [MIDIConnectionContext] = []
    private var clockTimer: DispatchSourceTimer?
    private var isClosed = false
    private var isPanicking = false

    public init(requiresSessionAuthorization: Bool = false) throws {
        self.requiresSessionAuthorization = requiresSessionAuthorization
        try check(MIDIClientCreateWithBlock("Arranger Lab" as CFString, &client) { [weak self] _ in self?.refreshEndpoints() })
        try check(MIDIInputPortCreateWithBlock(client, "Arranger Lab Input" as CFString, &inputPort) { [weak self] packetList, refCon in
            let context = refCon.map {
                Unmanaged<MIDIConnectionContext>.fromOpaque($0).takeUnretainedValue()
            }
            self?.receive(packetList, context: context)
        })
        try check(MIDIOutputPortCreate(client, "Arranger Lab Output" as CFString, &outputPort))
        refreshEndpoints()
    }

    deinit { close() }

    public func refreshEndpoints() {
        guard withStateLock({ !isClosed }) else { return }
        let refreshedSources = (0..<MIDIGetNumberOfSources()).compactMap { endpoint(MIDIGetSource($0)) }
        let refreshedDestinations = (0..<MIDIGetNumberOfDestinations()).compactMap { endpoint(MIDIGetDestination($0)) }
        var timerToCancel: DispatchSourceTimer?
        var refreshFailure: Error?
        var didRefresh = false

        withStateLock {
            guard !isClosed else { return }
            let refreshedSource = storedSelectedSource.flatMap { selected in
                refreshedSources.first(where: { $0.id == selected.id })
            }
            let refreshedDestination = storedSelectedDestination.flatMap { selected in
                refreshedDestinations.first(where: { $0.id == selected.id })
            }
            let sourceChanged = storedSelectedSource.map {
                refreshedSource == nil || refreshedSource?.ref != $0.ref
            } ?? false
            let destinationChanged = storedSelectedDestination.map {
                refreshedDestination == nil || refreshedDestination?.ref != $0.ref
            } ?? false

            if sourceChanged || destinationChanged {
                do { try panic() }
                catch { refreshFailure = error }
                if let source = storedSelectedSource {
                    MIDIPortDisconnectSource(inputPort, source.ref)
                }
                timerToCancel = clockTimer
                clockTimer = nil
                storedSelectedSource = nil
                storedSelectedDestination = nil
                invalidateSessionLocked()
                decoder.reset()
            } else {
                if let refreshedSource { storedSelectedSource = refreshedSource }
                if let refreshedDestination { storedSelectedDestination = refreshedDestination }
            }
            storedSources = refreshedSources
            storedDestinations = refreshedDestinations
            didRefresh = true
        }

        timerToCancel?.cancel()
        guard didRefresh else { return }
        if let refreshFailure { onFailure?(refreshFailure) }
        onEndpointsChanged?(refreshedSources, refreshedDestinations)
    }

    public func connect(sourceID: Int32?, destinationID: Int32?) throws {
        let hadDestination = selectedDestination != nil
        if let stopError = stopClock(sendStop: false), hadDestination {
            throw stopError
        }
        try withStateLock {
            guard !isClosed else { throw ArrangerLabError.endpointUnavailable }
            if let current = storedSelectedSource {
                MIDIPortDisconnectSource(inputPort, current.ref)
            }
            invalidateSessionLocked()
            storedSelectedSource = sourceID.flatMap { id in storedSources.first(where: { $0.id == id }) }
            storedSelectedDestination = destinationID.flatMap { id in storedDestinations.first(where: { $0.id == id }) }
            if let source = storedSelectedSource {
                let context = MIDIConnectionContext(
                    source: source,
                    generation: connectionGeneration,
                    sessionID: currentSessionID
                )
                do {
                    try check(
                        MIDIPortConnectSource(
                            inputPort,
                            source.ref,
                            Unmanaged.passUnretained(context).toOpaque()
                        )
                    )
                    connectionContexts.append(context)
                } catch {
                    storedSelectedSource = nil
                    storedSelectedDestination = nil
                    invalidateSessionLocked()
                    throw error
                }
            }
            decoder.reset()
        }
    }

    public func autoConnect(matching identity: TransportIdentity) throws -> TransportMatchResult {
        refreshEndpoints()
        let matches = TransportMatcher.matches(identity: identity, sources: sources, destinations: destinations)
        guard !matches.isEmpty else { return .notFound }
        guard matches.count == 1, let match = matches.first else { return .ambiguous(matches) }
        try connect(sourceID: match.source.id, destinationID: match.destination.id)
        return .connected(match)
    }

    public func authorizeCurrentConnection() throws {
        try withStateLock {
            guard !isClosed,
                  storedSelectedSource != nil,
                  storedSelectedDestination != nil else {
                throw ArrangerLabError.endpointUnavailable
            }
            authorizedGeneration = connectionGeneration
            authorizedSessionID = currentSessionID
        }
    }

    public func authorizeCurrentConnection(from identityEvent: MIDIEvent) throws {
        try withStateLock {
            guard !isClosed,
                  identityEvent.direction == .input,
                  identityEvent.transportSessionID == currentSessionID,
                  identityEvent.endpointUniqueID == storedSelectedSource?.id,
                  storedSelectedDestination != nil else {
                throw ArrangerLabError.deviceIdentityRequired
            }
            authorizedGeneration = connectionGeneration
            authorizedSessionID = currentSessionID
        }
    }

    public func isEventFromCurrentSession(_ event: MIDIEvent) -> Bool {
        withStateLock { event.transportSessionID == currentSessionID }
    }

    public func sendUniversalIdentityRequest() throws {
        try sendNow(
            .systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]),
            timestamp: 0,
            requiresAuthorization: false
        )
    }

    public func send(_ message: MIDIMessage, timestamp: MIDITimeStamp = 0) throws {
        try sendNow(message, timestamp: timestamp, requiresAuthorization: true)
    }

    public func sendScheduled(_ messages: [ScheduledMIDIMessage]) throws {
        let schedule = stableSchedule(messages)
        let context = try beginSchedule(messageCount: schedule.count)
        defer { endSchedule(context.id) }
        var previousOffset: UInt64 = 0
        for scheduled in schedule {
            try validateSchedule(context)
            let delay = scheduled.offsetNanoseconds - previousOffset
            if delay > 0 {
                Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000)
            }
            try sendScheduledMessage(scheduled.message, context: context)
            previousOffset = scheduled.offsetNanoseconds
        }
    }

    public func sendScheduledAsync(_ messages: [ScheduledMIDIMessage]) async throws {
        let schedule = stableSchedule(messages)
        let context = try beginSchedule(messageCount: schedule.count)
        defer { endSchedule(context.id) }
        var previousOffset: UInt64 = 0
        for scheduled in schedule {
            try Task.checkCancellation()
            try validateSchedule(context)
            let delay = scheduled.offsetNanoseconds - previousOffset
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
                try Task.checkCancellation()
            }
            try sendScheduledMessage(scheduled.message, context: context)
            previousOffset = scheduled.offsetNanoseconds
        }
    }

    public func cancelScheduledSends() {
        withStateLock { cancelSchedulesLocked() }
    }

    public func replay(_ events: [MIDIEvent], speed: Double = 1, range: ClosedRange<UInt64>? = nil, allowKnownSysEx: Bool = false) throws {
        guard speed > 0 else { throw ArrangerLabError.invalidValue("replay speed must be positive") }
        let selected = events.enumerated().filter { _, event in
            guard event.direction == .output else { return false }
            if let range, !range.contains(event.timestampNanoseconds) { return false }
            if case .systemExclusive = event.message, !allowKnownSysEx { return false }
            return true
        }.sorted { left, right in
            if left.element.timestampNanoseconds != right.element.timestampNanoseconds {
                return left.element.timestampNanoseconds < right.element.timestampNanoseconds
            }
            return left.offset < right.offset
        }.map(\.element)
        guard let first = selected.first else { return }
        var previous = first.timestampNanoseconds
        do {
            for event in selected {
                let delay = event.timestampNanoseconds - previous
                if delay > 0 { Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000 / speed) }
                if let message = event.message { try send(message) }
                previous = event.timestampNanoseconds
            }
        } catch {
            let replayError = error
            do { try panic() }
            catch { throw error }
            throw replayError
        }
        try panic()
    }

    public func startClock(bpm: Double = 120) throws {
        guard (20...300).contains(bpm) else { throw ArrangerLabError.invalidValue("BPM must be 20...300") }
        if let stopError = stopClock(sendStop: false) {
            throw stopError
        }
        try send(.realtime(0xFA))
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        let interval = 60 / bpm / 24
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            do {
                try self.send(.realtime(0xF8))
            } catch {
                self.cancelClock(timer, after: error)
            }
        }
        withStateLock { clockTimer = timer }
        timer.resume()
    }

    @discardableResult
    public func stopClock(sendStop: Bool = true) -> Error? {
        let timer = withStateLock {
            let current = clockTimer
            clockTimer = nil
            return current
        }
        timer?.cancel()
        var firstError: Error?
        if sendStop {
            do { try send(.realtime(0xFC)) }
            catch { firstError = error }
        }
        do { try panic() }
        catch {
            if firstError == nil { firstError = error }
        }
        return firstError
    }

    public func panic() throws {
        let shouldSend = try withStateLock { () throws -> Bool in
            guard !isClosed, storedSelectedDestination != nil else {
                throw ArrangerLabError.endpointUnavailable
            }
            guard !isPanicking else { return false }
            isPanicking = true
            cancelSchedulesLocked()
            return true
        }
        guard shouldSend else { return }
        defer { withStateLock { isPanicking = false } }

        var failures: [Error] = []
        for channel in UInt8(0)...15 {
            for message in [
                MIDIMessage.controlChange(channel: channel, controller: 64, value: 0),
                .controlChange(channel: channel, controller: 123, value: 0),
                .controlChange(channel: channel, controller: 120, value: 0)
            ] {
                do {
                    try sendNow(message, timestamp: 0, requiresAuthorization: false)
                } catch {
                    failures.append(error)
                }
            }
        }
        do {
            try sendNow(.realtime(0xFC), timestamp: 0, requiresAuthorization: false)
        } catch {
            failures.append(error)
        }
        if let first = failures.first {
            throw ArrangerLabError.panicDeliveryFailed(
                failureCount: failures.count,
                firstError: first.localizedDescription
            )
        }
    }

    public func close(sendPanic: Bool = true) {
        guard withStateLock({ !isClosed }) else { return }
        if sendPanic {
            let timer = withStateLock {
                let current = clockTimer
                clockTimer = nil
                return current
            }
            timer?.cancel()
            try? panic()
        } else {
            let timer = withStateLock {
                let current = clockTimer
                clockTimer = nil
                cancelSchedulesLocked()
                return current
            }
            timer?.cancel()
        }
        withStateLock {
            guard !isClosed else { return }
            isClosed = true
            authorizedGeneration = nil
            authorizedSessionID = nil
            if let source = storedSelectedSource {
                MIDIPortDisconnectSource(inputPort, source.ref)
            }
            if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
            if outputPort != 0 { MIDIPortDispose(outputPort); outputPort = 0 }
            if client != 0 { MIDIClientDispose(client); client = 0 }
            storedSelectedSource = nil
            storedSelectedDestination = nil
            connectionContexts.removeAll()
            decoder.reset()
        }
    }

    private func receive(
        _ packetList: UnsafePointer<MIDIPacketList>,
        context: MIDIConnectionContext?
    ) {
        guard let context else { return }
        var decoderIssues: [MIDIStreamDecoderIssue] = []
        let decodedEvents = withStateLock { () -> [MIDIEvent] in
            guard !isClosed,
                  context.generation == connectionGeneration,
                  context.sessionID == currentSessionID,
                  storedSelectedSource?.id == context.source.id else { return [] }

            let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)
                ?? MemoryLayout<UInt32>.size
            let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)
                ?? (MemoryLayout<MIDITimeStamp>.size + MemoryLayout<UInt16>.size)
            var packetPointer = UnsafeMutablePointer<MIDIPacket>(
                mutating: UnsafeRawPointer(packetList)
                    .advanced(by: packetOffset)
                    .assumingMemoryBound(to: MIDIPacket.self)
            )
            var events: [MIDIEvent] = []
            for _ in 0..<packetList.pointee.numPackets {
                let packet = packetPointer.pointee
                let length = Int(packet.length)
                let dataPointer = UnsafeRawPointer(packetPointer)
                    .advanced(by: dataOffset)
                    .assumingMemoryBound(to: UInt8.self)
                let bytes = Array(UnsafeBufferPointer(start: dataPointer, count: length))
                let nanoseconds = packet.timeStamp == 0
                    ? monotonicNanoseconds()
                    : AudioConvertHostTimeToNanos(packet.timeStamp)
                for decoded in decoder.feed(bytes, onIssue: { decoderIssues.append($0) }) {
                    events.append(
                        .init(
                            timestampNanoseconds: nanoseconds,
                            direction: .input,
                            endpointUniqueID: context.source.id,
                            endpointName: context.source.name,
                            rawBytes: decoded.rawBytes,
                            message: decoded.message,
                            transportSessionID: context.sessionID
                        )
                    )
                }
                packetPointer = MIDIPacketNext(packetPointer)
            }
            return events
        }
        decoderIssues.forEach { onFailure?($0) }
        decodedEvents.forEach { onEvent?($0) }
    }

    private struct ScheduleContext {
        let id: UUID
        let connectionGeneration: UInt64
        let scheduleEpoch: UInt64
    }

    private func sendNow(
        _ message: MIDIMessage,
        timestamp: MIDITimeStamp,
        requiresAuthorization: Bool,
        scheduleContext: ScheduleContext? = nil
    ) throws {
        let result: Result<MIDIEvent, Error> = withStateLock {
            do {
                if let scheduleContext {
                    try validateScheduleLocked(scheduleContext)
                }
                guard !isClosed, let destination = storedSelectedDestination else {
                    throw ArrangerLabError.endpointUnavailable
                }
                if requiresAuthorization,
                   self.requiresSessionAuthorization,
                   (authorizedGeneration != connectionGeneration
                    || authorizedSessionID != currentSessionID) {
                    throw ArrangerLabError.deviceIdentityRequired
                }
                let bytes = message.canonicalBytes
                guard !bytes.isEmpty, bytes.count <= 256 else {
                    throw ArrangerLabError.invalidValue("MIDI 1.0 packet must contain 1...256 bytes")
                }
                var packetList = MIDIPacketList()
                let packet = MIDIPacketListInit(&packetList)
                _ = bytes.withUnsafeBufferPointer { pointer in
                    MIDIPacketListAdd(
                        &packetList,
                        MemoryLayout<MIDIPacketList>.size,
                        packet,
                        timestamp,
                        bytes.count,
                        pointer.baseAddress!
                    )
                }
                try check(MIDISend(outputPort, destination.ref, &packetList))
                return .success(
                    .init(
                        timestampNanoseconds: monotonicNanoseconds(),
                        direction: .output,
                        endpointUniqueID: destination.id,
                        endpointName: destination.name,
                        rawBytes: bytes,
                        message: message,
                        transportSessionID: currentSessionID
                    )
                )
            } catch {
                return .failure(error)
            }
        }

        switch result {
        case let .success(event):
            onEvent?(event)
        case let .failure(error):
            let shouldNotify = withStateLock { !isPanicking }
            if shouldNotify { onFailure?(error) }
            throw error
        }
    }

    private func sendScheduledMessage(
        _ message: MIDIMessage,
        context: ScheduleContext
    ) throws {
        try sendNow(
            message,
            timestamp: 0,
            requiresAuthorization: true,
            scheduleContext: context
        )
    }

    private func stableSchedule(_ messages: [ScheduledMIDIMessage]) -> [ScheduledMIDIMessage] {
        messages.enumerated().sorted { left, right in
            if left.element.offsetNanoseconds != right.element.offsetNanoseconds {
                return left.element.offsetNanoseconds < right.element.offsetNanoseconds
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    private func beginSchedule(messageCount: Int) throws -> ScheduleContext {
        try withStateLock {
            guard messageCount <= 4_096 else { throw ArrangerLabError.queueFull }
            guard !isClosed, storedSelectedDestination != nil else {
                throw ArrangerLabError.endpointUnavailable
            }
            if requiresSessionAuthorization,
               (authorizedGeneration != connectionGeneration
                || authorizedSessionID != currentSessionID) {
                throw ArrangerLabError.deviceIdentityRequired
            }
            guard activeScheduleID == nil else { throw ArrangerLabError.queueFull }
            let id = UUID()
            activeScheduleID = id
            return .init(
                id: id,
                connectionGeneration: connectionGeneration,
                scheduleEpoch: scheduleEpoch
            )
        }
    }

    private func validateSchedule(_ context: ScheduleContext) throws {
        try withStateLock { try validateScheduleLocked(context) }
    }

    private func validateScheduleLocked(_ context: ScheduleContext) throws {
        guard !isClosed, storedSelectedDestination != nil else {
            throw ArrangerLabError.endpointUnavailable
        }
        guard activeScheduleID == context.id,
              connectionGeneration == context.connectionGeneration,
              scheduleEpoch == context.scheduleEpoch else {
            throw CancellationError()
        }
        if requiresSessionAuthorization,
           (authorizedGeneration != connectionGeneration
            || authorizedSessionID != currentSessionID) {
            throw ArrangerLabError.deviceIdentityRequired
        }
    }

    private func endSchedule(_ id: UUID) {
        withStateLock {
            if activeScheduleID == id { activeScheduleID = nil }
        }
    }

    private func invalidateSessionLocked() {
        connectionGeneration &+= 1
        currentSessionID = UUID()
        authorizedGeneration = nil
        authorizedSessionID = nil
        cancelSchedulesLocked()
    }

    private func cancelSchedulesLocked() {
        scheduleEpoch &+= 1
        activeScheduleID = nil
    }

    private func cancelClock(_ timer: DispatchSourceTimer, after error: Error) {
        let isCurrentTimer = withStateLock {
            guard let current = clockTimer, current === timer else { return false }
            clockTimer = nil
            return true
        }
        guard isCurrentTimer else { return }
        timer.cancel()
        onFailure?(error)
    }

    @discardableResult
    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func endpoint(_ ref: MIDIEndpointRef) -> MIDIEndpoint? {
        guard ref != 0 else { return nil }
        var id: Int32 = 0
        guard MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &id) == noErr,
              let name = stringProperty(ref, kMIDIPropertyDisplayName) else { return nil }
        return MIDIEndpoint(
            id: id,
            name: name,
            ref: ref,
            manufacturer: stringProperty(ref, kMIDIPropertyManufacturer),
            model: stringProperty(ref, kMIDIPropertyModel)
        )
    }

    private func stringProperty(_ ref: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(ref, property, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
