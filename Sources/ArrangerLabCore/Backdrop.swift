import Foundation

public enum BackdropPalette: String, CaseIterable, Codable, Identifiable, Sendable {
    case forestLight
    case deepLagoon
    case ember
    case orchid
    case paper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .forestLight: return "Luz da floresta"
        case .deepLagoon: return "Lagoa profunda"
        case .ember: return "Brasa"
        case .orchid: return "Orquídea"
        case .paper: return "Papel claro"
        }
    }

    public var summary: String {
        switch self {
        case .forestLight: return "Verdes, turquesa e âmbar sobre fundo escuro"
        case .deepLagoon: return "Azuis e ciano com profundidade suave"
        case .ember: return "Coral, cobre e magenta com calor controlado"
        case .orchid: return "Violeta, rosa e azul em baixa luminosidade"
        case .paper: return "Pigmentos sobre uma tela clara suavemente tingida"
        }
    }

    public var usesLightBackground: Bool { self == .paper }
}

public enum BackdropAmbientMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case quiet
    case flowing
    case breathing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .quiet: return "Quase parado"
        case .flowing: return "Fluxo lento"
        case .breathing: return "Respiração"
        }
    }
}

public struct BackdropCue: Codable, Equatable, Identifiable, Sendable {
    public let presetID: UUID
    public var palette: BackdropPalette
    public var intensity: Double
    public var persistence: Double
    public var sensitivity: Double
    public var ambientMode: BackdropAmbientMode
    public var isEnabled: Bool
    public var updatedAt: Date

    public var id: UUID { presetID }

    public init(
        presetID: UUID,
        palette: BackdropPalette = .forestLight,
        intensity: Double = 0.62,
        persistence: Double = 0.66,
        sensitivity: Double = 0.58,
        ambientMode: BackdropAmbientMode = .flowing,
        isEnabled: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.presetID = presetID
        self.palette = palette
        self.intensity = intensity
        self.persistence = persistence
        self.sensitivity = sensitivity
        self.ambientMode = ambientMode
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard (0...1).contains(intensity),
              (0...1).contains(persistence),
              (0...1).contains(sensitivity) else {
            throw ArrangerLabError.invalidValue("backdrop cue controls must be between 0 and 1")
        }
    }
}

public enum BackdropStrokeKind: String, Codable, Equatable, Sendable {
    case note
    case chordBloom
}

public struct BackdropStroke: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: BackdropStrokeKind
    public let note: UInt8
    public let channel: UInt8
    public let pitchClass: Int
    public let normalizedX: Double
    public let normalizedY: Double
    public let radius: Double
    public let luminosity: Double
    public let persistenceSeconds: Double
    public let clusterSize: Int
    public let bornAtNanoseconds: UInt64
    public var releasedAtNanoseconds: UInt64?

    public init(
        id: UUID = UUID(),
        kind: BackdropStrokeKind,
        note: UInt8,
        channel: UInt8,
        pitchClass: Int,
        normalizedX: Double,
        normalizedY: Double,
        radius: Double,
        luminosity: Double,
        persistenceSeconds: Double,
        clusterSize: Int,
        bornAtNanoseconds: UInt64,
        releasedAtNanoseconds: UInt64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.note = note
        self.channel = channel
        self.pitchClass = pitchClass
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.radius = radius
        self.luminosity = luminosity
        self.persistenceSeconds = persistenceSeconds
        self.clusterSize = clusterSize
        self.bornAtNanoseconds = bornAtNanoseconds
        self.releasedAtNanoseconds = releasedAtNanoseconds
    }
}

public struct BackdropRenderState: Equatable, Sendable {
    public var cue: BackdropCue?
    public var activePresetID: UUID?
    public var strokes: [BackdropStroke]
    public var sustainedChannels: Set<UInt8>
    public var isBlackout: Bool
    public var lastEventAtNanoseconds: UInt64?

    public init(
        cue: BackdropCue? = nil,
        activePresetID: UUID? = nil,
        strokes: [BackdropStroke] = [],
        sustainedChannels: Set<UInt8> = [],
        isBlackout: Bool = false,
        lastEventAtNanoseconds: UInt64? = nil
    ) {
        self.cue = cue
        self.activePresetID = activePresetID
        self.strokes = strokes
        self.sustainedChannels = sustainedChannels
        self.isBlackout = isBlackout
        self.lastEventAtNanoseconds = lastEventAtNanoseconds
    }
}

public struct BackdropEventReducer: Sendable {
    public private(set) var state: BackdropRenderState
    public let maximumStrokes: Int

    private struct NoteKey: Hashable, Sendable {
        let channel: UInt8
        let note: UInt8
    }

    private struct RecentNote: Sendable {
        let channel: UInt8
        let note: UInt8
        let timestamp: UInt64
    }

    private var activeStrokeIDs: [NoteKey: UUID] = [:]
    private var sustainedKeys: Set<NoteKey> = []
    private var recentNotes: [RecentNote] = []

    public init(state: BackdropRenderState = .init(), maximumStrokes: Int = 512) {
        self.state = state
        self.maximumStrokes = max(8, maximumStrokes)
    }

    public mutating func activate(_ cue: BackdropCue, at timestamp: UInt64) {
        state.cue = cue
        state.activePresetID = cue.presetID
        state.isBlackout = !cue.isEnabled
        state.lastEventAtNanoseconds = timestamp
        clearPerformanceState(releaseAt: timestamp, removeStrokes: true)
    }

    public mutating func updateActiveCue(_ cue: BackdropCue, at timestamp: UInt64) {
        guard state.activePresetID == cue.presetID else { return }
        state.cue = cue
        state.isBlackout = !cue.isEnabled
        state.lastEventAtNanoseconds = timestamp
        if !cue.isEnabled {
            clearPerformanceState(releaseAt: timestamp, removeStrokes: true)
        }
    }

    public mutating func deactivate(at timestamp: UInt64) {
        state.cue = nil
        state.activePresetID = nil
        state.isBlackout = false
        state.lastEventAtNanoseconds = timestamp
        clearPerformanceState(releaseAt: timestamp, removeStrokes: true)
    }

    public mutating func blackout(at timestamp: UInt64) {
        state.isBlackout = true
        state.lastEventAtNanoseconds = timestamp
        clearPerformanceState(releaseAt: timestamp, removeStrokes: true)
    }

    public mutating func returnToAmbient(at timestamp: UInt64) {
        state.isBlackout = state.cue?.isEnabled == false
        state.lastEventAtNanoseconds = timestamp
        clearPerformanceState(releaseAt: timestamp, removeStrokes: true)
    }

    public mutating func disconnect(at timestamp: UInt64) {
        releaseAll(at: timestamp)
        state.sustainedChannels.removeAll()
        sustainedKeys.removeAll()
        recentNotes.removeAll()
        state.lastEventAtNanoseconds = timestamp
    }

    @discardableResult
    public mutating func consume(_ event: MIDIEvent) -> Bool {
        guard state.cue?.isEnabled == true,
              !state.isBlackout,
              event.direction == .input,
              let message = event.message,
              isCanonicalChannelEvent(event, message: message) else { return false }

        switch message {
        case let .noteOn(channel, note, velocity) where channel < 4:
            if velocity == 0 {
                return release(channel: channel, note: note, at: event.timestampNanoseconds)
            }
            return trigger(channel: channel, note: note, velocity: velocity, at: event.timestampNanoseconds)
        case let .noteOff(channel, note, _) where channel < 4:
            return release(channel: channel, note: note, at: event.timestampNanoseconds)
        case let .controlChange(channel, controller, value) where channel < 4 && controller == 64:
            return updateSustain(channel: channel, engaged: value >= 64, at: event.timestampNanoseconds)
        default:
            return false
        }
    }

    private mutating func trigger(channel: UInt8, note: UInt8, velocity: UInt8, at timestamp: UInt64) -> Bool {
        guard let cue = state.cue else { return false }
        let key = NoteKey(channel: channel, note: note)
        if let previousID = activeStrokeIDs[key] {
            markReleased(previousID, at: timestamp)
        }
        sustainedKeys.remove(key)

        let clusterWindow: UInt64 = 90_000_000
        recentNotes.removeAll { timestamp >= $0.timestamp && timestamp - $0.timestamp > clusterWindow }
        recentNotes.append(.init(channel: channel, note: note, timestamp: timestamp))
        let cluster = recentNotes.filter {
            timestamp >= $0.timestamp && timestamp - $0.timestamp <= clusterWindow
        }
        let clusterSize = min(6, cluster.count)
        let stroke = makeStroke(
            kind: .note,
            channel: channel,
            note: note,
            velocity: velocity,
            clusterSize: clusterSize,
            cue: cue,
            timestamp: timestamp
        )
        state.strokes.append(stroke)
        activeStrokeIDs[key] = stroke.id

        if clusterSize >= 3 {
            let averageNote = UInt8(
                min(127, max(0, cluster.map { Int($0.note) }.reduce(0, +) / cluster.count))
            )
            state.strokes.append(
                makeStroke(
                    kind: .chordBloom,
                    channel: channel,
                    note: averageNote,
                    velocity: velocity,
                    clusterSize: clusterSize,
                    cue: cue,
                    timestamp: timestamp
                )
            )
        }

        state.lastEventAtNanoseconds = timestamp
        enforceBound()
        return true
    }

    private mutating func release(channel: UInt8, note: UInt8, at timestamp: UInt64) -> Bool {
        let key = NoteKey(channel: channel, note: note)
        guard let strokeID = activeStrokeIDs[key] else { return false }
        if state.sustainedChannels.contains(channel) {
            sustainedKeys.insert(key)
        } else {
            activeStrokeIDs.removeValue(forKey: key)
            markReleased(strokeID, at: timestamp)
        }
        state.lastEventAtNanoseconds = timestamp
        return true
    }

    private mutating func updateSustain(channel: UInt8, engaged: Bool, at timestamp: UInt64) -> Bool {
        if engaged {
            let inserted = state.sustainedChannels.insert(channel).inserted
            if inserted { state.lastEventAtNanoseconds = timestamp }
            return inserted
        }

        let removed = state.sustainedChannels.remove(channel) != nil
        let keysToRelease = sustainedKeys.filter { $0.channel == channel }
        for key in keysToRelease {
            if let strokeID = activeStrokeIDs.removeValue(forKey: key) {
                markReleased(strokeID, at: timestamp)
            }
            sustainedKeys.remove(key)
        }
        if removed || !keysToRelease.isEmpty { state.lastEventAtNanoseconds = timestamp }
        return removed || !keysToRelease.isEmpty
    }

    private func makeStroke(
        kind: BackdropStrokeKind,
        channel: UInt8,
        note: UInt8,
        velocity: UInt8,
        clusterSize: Int,
        cue: BackdropCue,
        timestamp: UInt64
    ) -> BackdropStroke {
        let velocityUnit = Double(velocity) / 127
        let noteUnit = min(1, max(0, (Double(note) - 24) / 84))
        let channelY = [0.62, 0.48, 0.34, 0.78][Int(channel)]
        let pitchMovement = (Double(Int(note) % 12) - 5.5) * 0.006
        let sensitivityScale = 0.72 + cue.sensitivity * 0.7
        let chordScale = kind == .chordBloom ? 1.7 + Double(clusterSize) * 0.08 : 1
        let radius = min(0.22, (0.028 + velocityUnit * 0.075) * sensitivityScale * chordScale)
        let luminosity = min(1, (0.32 + velocityUnit * 0.58) * (0.55 + cue.intensity * 0.65))
        let persistence = (1.6 + cue.persistence * 5.8) * (kind == .chordBloom ? 1.16 : 1)
        return BackdropStroke(
            kind: kind,
            note: note,
            channel: channel,
            pitchClass: Int(note % 12),
            normalizedX: noteUnit,
            normalizedY: min(0.92, max(0.08, channelY + pitchMovement)),
            radius: radius,
            luminosity: luminosity,
            persistenceSeconds: persistence,
            clusterSize: clusterSize,
            bornAtNanoseconds: timestamp
        )
    }

    private mutating func releaseAll(at timestamp: UInt64) {
        for strokeID in activeStrokeIDs.values {
            markReleased(strokeID, at: timestamp)
        }
        activeStrokeIDs.removeAll()
    }

    private mutating func clearPerformanceState(releaseAt timestamp: UInt64, removeStrokes: Bool) {
        if removeStrokes {
            state.strokes.removeAll(keepingCapacity: true)
        } else {
            releaseAll(at: timestamp)
        }
        activeStrokeIDs.removeAll()
        sustainedKeys.removeAll()
        recentNotes.removeAll()
        state.sustainedChannels.removeAll()
    }

    private mutating func markReleased(_ id: UUID, at timestamp: UInt64) {
        guard let index = state.strokes.firstIndex(where: { $0.id == id }),
              state.strokes[index].releasedAtNanoseconds == nil else { return }
        state.strokes[index].releasedAtNanoseconds = timestamp
    }

    private mutating func enforceBound() {
        guard state.strokes.count > maximumStrokes else { return }
        let overflow = state.strokes.count - maximumStrokes
        let removable = state.strokes.indices.filter {
            state.strokes[$0].releasedAtNanoseconds != nil
                || !activeStrokeIDs.values.contains(state.strokes[$0].id)
        }
        let selected = Array(removable.prefix(overflow))
        if selected.count < overflow {
            let selectedSet = Set(selected)
            let additional = state.strokes.indices
                .filter { !selectedSet.contains($0) }
                .prefix(overflow - selected.count)
            removeStrokeIndices(selected + additional)
        } else {
            removeStrokeIndices(selected)
        }
    }

    private mutating func removeStrokeIndices<S: Sequence>(_ indices: S) where S.Element == Int {
        let ids = Set(indices.map { state.strokes[$0].id })
        state.strokes.removeAll { ids.contains($0.id) }
        activeStrokeIDs = activeStrokeIDs.filter { !ids.contains($0.value) }
        sustainedKeys = sustainedKeys.filter { activeStrokeIDs[$0] != nil }
    }

    private func isCanonicalChannelEvent(_ event: MIDIEvent, message: MIDIMessage) -> Bool {
        let canonical = message.canonicalBytes
        guard event.rawBytes == canonical || event.rawBytes == Array(canonical.dropFirst()) else { return false }
        switch message {
        case .noteOn, .noteOff, .controlChange:
            return true
        default:
            return false
        }
    }
}

public struct BackdropCueFile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var cues: [BackdropCue]

    public init(schemaVersion: Int = 1, cues: [BackdropCue]) {
        self.schemaVersion = schemaVersion
        self.cues = cues
    }
}

public enum BackdropCueStore {
    public static func save(_ cues: [BackdropCue], to url: URL) throws {
        guard Set(cues.map(\.presetID)).count == cues.count else {
            throw ArrangerLabError.invalidValue("backdrop cues contain duplicate preset IDs")
        }
        try cues.forEach { try $0.validate() }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(BackdropCueFile(cues: cues)).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> [BackdropCue] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try decoder.decode(BackdropCueFile.self, from: Data(contentsOf: url))
        guard file.schemaVersion == 1 else {
            throw ArrangerLabError.corruptCapture("unsupported backdrop cue schema")
        }
        guard Set(file.cues.map(\.presetID)).count == file.cues.count else {
            throw ArrangerLabError.corruptCapture("duplicate backdrop cue preset IDs")
        }
        try file.cues.forEach { try $0.validate() }
        return file.cues
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
