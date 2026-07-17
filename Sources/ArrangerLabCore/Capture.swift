import Foundation

public struct DeviceStateSnapshot: Codable, Equatable, Sendable {
    public var model: String
    public var firmware: String
    public var midiPreset: String
    public var clockSource: String
    public var mode: String
    public var inputEndpoint: String
    public var outputEndpoint: String
    public init(model: String, firmware: String, midiPreset: String, clockSource: String, mode: String, inputEndpoint: String, outputEndpoint: String) {
        self.model = model; self.firmware = firmware; self.midiPreset = midiPreset; self.clockSource = clockSource; self.mode = mode; self.inputEndpoint = inputEndpoint; self.outputEndpoint = outputEndpoint
    }
}

public struct ManualConfirmation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let prompt: String
    public let confirmed: Bool
    public let note: String
    public init(id: UUID = UUID(), timestamp: Date = Date(), prompt: String, confirmed: Bool, note: String) {
        self.id = id; self.timestamp = timestamp; self.prompt = prompt; self.confirmed = confirmed; self.note = note
    }
}

public struct AudioMetrics: Codable, Equatable, Sendable {
    public let rms: Double
    public let peak: Double
    public let rmsDBFS: Double
    public let spectralCentroidHz: Double
    public let normalizedSpectrum: [Double]
    public init(rms: Double, peak: Double, rmsDBFS: Double, spectralCentroidHz: Double, normalizedSpectrum: [Double]) {
        self.rms = rms; self.peak = peak; self.rmsDBFS = rmsDBFS; self.spectralCentroidHz = spectralCentroidHz; self.normalizedSpectrum = normalizedSpectrum
    }
}

public struct AudioEvidenceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let relativePath: String
    public let sampleRate: Double
    public let channels: Int
    public let durationSeconds: Double
    public let metrics: AudioMetrics
    public init(id: UUID = UUID(), relativePath: String, sampleRate: Double, channels: Int, durationSeconds: Double, metrics: AudioMetrics) {
        self.id = id; self.relativePath = relativePath; self.sampleRate = sampleRate; self.channels = channels; self.durationSeconds = durationSeconds; self.metrics = metrics
    }
}

public struct ExperimentAnalysis: Codable, Equatable, Sendable {
    public var notes: [String]
    public var audioEvidence: [AudioEvidenceRecord]
    public var manualConfirmations: [ManualConfirmation]
    public var spectralDistances: [String: Double]
    public init(notes: [String], audioEvidence: [AudioEvidenceRecord], manualConfirmations: [ManualConfirmation], spectralDistances: [String: Double]) {
        self.notes = notes; self.audioEvidence = audioEvidence; self.manualConfirmations = manualConfirmations; self.spectralDistances = spectralDistances
    }
}

public struct ArrLabManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let experimentID: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var hypothesis: String
    public var mappingID: String?
    public var mappingStatus: MappingStatus
    public var deviceState: DeviceStateSnapshot
    public var annotations: [String]
    public init(schemaVersion: Int, experimentID: UUID, title: String, createdAt: Date, updatedAt: Date, hypothesis: String, mappingID: String?, mappingStatus: MappingStatus, deviceState: DeviceStateSnapshot, annotations: [String]) {
        self.schemaVersion = schemaVersion; self.experimentID = experimentID; self.title = title; self.createdAt = createdAt; self.updatedAt = updatedAt; self.hypothesis = hypothesis; self.mappingID = mappingID; self.mappingStatus = mappingStatus; self.deviceState = deviceState; self.annotations = annotations
    }
}

public struct ArrLabExperiment: Equatable, Sendable {
    public var manifest: ArrLabManifest
    public var events: [MIDIEvent]
    public var analysis: ExperimentAnalysis
    public init(manifest: ArrLabManifest, events: [MIDIEvent], analysis: ExperimentAnalysis) { self.manifest = manifest; self.events = events; self.analysis = analysis }
}

public struct MappingVerificationResult: Equatable, Sendable {
    public let mappingID: String
    public let checks: [String: Bool]

    public init(mappingID: String, checks: [String: Bool]) {
        self.mappingID = mappingID
        self.checks = checks
    }

    public var passed: Bool { !checks.isEmpty && checks.values.allSatisfy { $0 } }
    public var annotations: [String] {
        checks.keys.sorted().map { key in
            "\(key): \(checks[key] == true ? "passed" : "failed")"
        }
    }
}

public enum MappingEvidenceVerifier {
    public static func partVolume(
        events: [MIDIEvent],
        firmware: String,
        expectedFirmware: String,
        midiPreset: String,
        identityConfirmed: Bool,
        audioPasses: Bool,
        manualConfirmations: [ManualConfirmation]
    ) -> MappingVerificationResult {
        let expectedRawMessages: [[UInt8]] = [
            [0xB0, 0x07, 32],
            [0xB0, 0x07, 64],
            [0xB0, 0x07, 95]
        ]
        let hasExpectedRawMessages = expectedRawMessages.allSatisfy { expected in
            events.contains { $0.direction == .output && $0.rawBytes == expected }
        }
        let manualConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == "Volume right/layer 1 audibly changed"
        }
        return .init(mappingID: "partVolume", checks: [
            "audio evidence": audioPasses,
            "device identity": identityConfirmed,
            "firmware \(expectedFirmware)": firmware == expectedFirmware,
            "manual confirmation": manualConfirmed,
            "MIDI preset ArrangerLab": midiPreset == "ArrangerLab",
            "raw CC7 ch1 at 25/50/75%": hasExpectedRawMessages
        ])
    }

    public static func partExpression(
        events: [MIDIEvent],
        firmware: String,
        expectedFirmware: String,
        midiPreset: String,
        identityConfirmed: Bool,
        audioPasses: Bool,
        manualConfirmations: [ManualConfirmation]
    ) -> MappingVerificationResult {
        let expectedRawMessages: [[UInt8]] = [
            [0xB0, 0x0B, 32],
            [0xB0, 0x0B, 64],
            [0xB0, 0x0B, 95]
        ]
        let hasExpectedRawMessages = expectedRawMessages.allSatisfy { expected in
            events.contains { $0.direction == .output && $0.rawBytes == expected }
        }
        let manualConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == "Expression right/layer 1 audibly changed"
        }
        return .init(mappingID: "partExpression", checks: [
            "audio evidence": audioPasses,
            "device identity": identityConfirmed,
            "firmware \(expectedFirmware)": firmware == expectedFirmware,
            "manual confirmation": manualConfirmed,
            "MIDI preset ArrangerLab": midiPreset == "ArrangerLab",
            "raw CC11 ch1 at 25/50/75%": hasExpectedRawMessages
        ])
    }

    public static func partPan(
        events: [MIDIEvent],
        firmware: String,
        expectedFirmware: String,
        midiPreset: String,
        identityConfirmed: Bool,
        audioCaptured: Bool,
        manualConfirmations: [ManualConfirmation]
    ) -> MappingVerificationResult {
        let expectedRawMessages: [[UInt8]] = [
            [0xB0, 0x0A, 0],
            [0xB0, 0x0A, 64],
            [0xB0, 0x0A, 127]
        ]
        let hasExpectedRawMessages = expectedRawMessages.allSatisfy { expected in
            events.contains { $0.direction == .output && $0.rawBytes == expected }
        }
        let manualConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == "Pan right/layer 1 moved left, center and right"
        }
        return .init(mappingID: "partPan", checks: [
            "audio evidence captured": audioCaptured,
            "device identity": identityConfirmed,
            "firmware \(expectedFirmware)": firmware == expectedFirmware,
            "manual stereo confirmation": manualConfirmed,
            "MIDI preset ArrangerLab": midiPreset == "ArrangerLab",
            "raw CC10 ch1 left/center/right": hasExpectedRawMessages
        ])
    }

    public static func partDamper(
        events: [MIDIEvent],
        firmware: String,
        expectedFirmware: String,
        midiPreset: String,
        identityConfirmed: Bool,
        audibleComparisonCompleted: Bool,
        manualConfirmations: [ManualConfirmation]
    ) -> MappingVerificationResult {
        let outputBytes = events.filter { $0.direction == .output }.map(\.rawBytes)
        let off: [UInt8] = [0xB0, 0x40, 0]
        let on: [UInt8] = [0xB0, 0x40, 127]
        let hasSafeSequence: Bool
        if let firstOff = outputBytes.firstIndex(of: off),
           let onIndex = outputBytes[(firstOff + 1)...].firstIndex(of: on),
           outputBytes[(onIndex + 1)...].contains(off) {
            hasSafeSequence = true
        } else {
            hasSafeSequence = false
        }
        let manualConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == "Damper right/layer 1 sustained the second note and released on OFF"
        }
        return .init(mappingID: "partDamper", checks: [
            "audible OFF/ON/OFF comparison executed": audibleComparisonCompleted,
            "device identity": identityConfirmed,
            "firmware \(expectedFirmware)": firmware == expectedFirmware,
            "manual sustain confirmation": manualConfirmed,
            "MIDI preset ArrangerLab": midiPreset == "ArrangerLab",
            "raw CC64 ch1 OFF/ON/OFF": hasSafeSequence
        ])
    }

    public static func arrangerTransport(
        events: [MIDIEvent],
        firmware: String,
        expectedFirmware: String,
        midiPreset: String,
        identityConfirmed: Bool,
        externalUSBConfirmed: Bool,
        internalRestored: Bool,
        audioDurationSeconds: Double?,
        manualConfirmations: [ManualConfirmation]
    ) -> MappingVerificationResult {
        let outputBytes = events.filter { $0.direction == .output }.map(\.rawBytes)
        let clockCount = outputBytes.filter { $0 == [0xF8] }.count
        let startConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == "PA700 arranger started from external USB clock"
        }
        let stopConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == "PA700 arranger stopped from external USB clock"
        }
        return .init(mappingID: "arrangerTransport", checks: [
            "audio clip at least 2 seconds": (audioDurationSeconds ?? 0) >= 2,
            "Clock Source External USB confirmed": externalUSBConfirmed,
            "Clock Source Internal restored": internalRestored,
            "device identity": identityConfirmed,
            "firmware \(expectedFirmware)": firmware == expectedFirmware,
            "manual arranger Start confirmation": startConfirmed,
            "manual arranger Stop confirmation": stopConfirmed,
            "MIDI preset ArrangerLab": midiPreset == "ArrangerLab",
            "raw Start FA": outputBytes.contains([0xFA]),
            "raw Stop FC": outputBytes.contains([0xFC]),
            "received at least 48 MIDI clocks": clockCount >= 48
        ])
    }

    public static func songBook(
        events: [MIDIEvent],
        number: Int,
        expectedNumber: Int,
        displayedName: String,
        expectedName: String,
        firmware: String,
        expectedFirmware: String,
        midiPreset: String,
        identityConfirmed: Bool,
        stylePlayConfirmed: Bool,
        manualConfirmations: [ManualConfirmation]
    ) -> MappingVerificationResult {
        guard (0...9_999).contains(number) else {
            return .init(mappingID: "songBook", checks: ["valid SongBook number": false])
        }
        let expectedRawMessages: [[UInt8]] = [
            [0xBF, 99, 2],
            [0xBF, 98, 64],
            [0xBF, 6, UInt8(number / 100)],
            [0xBF, 38, UInt8(number % 100)]
        ]
        let hasExpectedRawMessages = expectedRawMessages.allSatisfy { expected in
            events.contains { $0.direction == .output && $0.rawBytes == expected }
        }
        let normalizedName = displayedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualPrompt = "Displayed SongBook entry matched requested number \(number): \(normalizedName)"
        let manualConfirmed = manualConfirmations.contains {
            $0.confirmed && $0.prompt == manualPrompt
        }
        return .init(mappingID: "songBook", checks: [
            "device identity": identityConfirmed,
            "displayed entry name": normalizedName == expectedName,
            "firmware \(expectedFirmware)": firmware == expectedFirmware,
            "manual SongBook confirmation": manualConfirmed,
            "MIDI preset ArrangerLab": midiPreset == "ArrangerLab",
            "raw NRPN and Data Entry on channel 16": hasExpectedRawMessages,
            "SongBook number \(number)": number == expectedNumber,
            "Style Play confirmed": stylePlayConfirmed
        ])
    }
}

public enum ArrLabPackage {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func save(_ experiment: ArrLabExperiment, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try encoder.encode(experiment.manifest).write(to: url.appendingPathComponent("manifest.json"), options: .atomic)
        try encoder.encode(experiment.analysis).write(to: url.appendingPathComponent("analysis.json"), options: .atomic)

        let lines = try experiment.events.map { event -> String in
            let data = try encoder.encode(event)
            guard let line = String(data: data, encoding: .utf8) else { throw ArrangerLabError.corruptCapture("event encoding") }
            return line.replacingOccurrences(of: "\n", with: "")
        }
        try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: url.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
    }

    public static func load(from url: URL) throws -> ArrLabExperiment {
        do {
            let manifest = try decoder.decode(ArrLabManifest.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
            guard manifest.schemaVersion == 1 else { throw ArrangerLabError.corruptCapture("unsupported schema") }
            let analysis = try decoder.decode(ExperimentAnalysis.self, from: Data(contentsOf: url.appendingPathComponent("analysis.json")))
            let content = try String(contentsOf: url.appendingPathComponent("events.jsonl"), encoding: .utf8)
            let events = try content.split(whereSeparator: \ .isNewline).map { line in
                guard let data = String(line).data(using: .utf8) else { throw ArrangerLabError.corruptCapture("invalid UTF-8") }
                return try decoder.decode(MIDIEvent.self, from: data)
            }
            return .init(manifest: manifest, events: events, analysis: analysis)
        } catch let error as ArrangerLabError { throw error }
        catch { throw ArrangerLabError.corruptCapture(error.localizedDescription) }
    }

    public static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Arranger Lab", isDirectory: true).appendingPathComponent("Experiments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

public struct CaptureDiffOptions: Sendable {
    public var includeNotes = false
    public var includeClock = false
    public var includeActiveSensing = false
    public init(includeNotes: Bool = false, includeClock: Bool = false, includeActiveSensing: Bool = false) {
        self.includeNotes = includeNotes; self.includeClock = includeClock; self.includeActiveSensing = includeActiveSensing
    }
}

public enum CaptureDiffKind: String, Codable, Sendable { case changed, added, removed }
public struct CaptureDiffItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: CaptureDiffKind
    public let label: String
    public let before: String?
    public let after: String?
}

public enum CaptureDiffer {
    public static func compare(_ a: [MIDIEvent], _ b: [MIDIEvent], options: CaptureDiffOptions = .init()) -> [CaptureDiffItem] {
        let left = normalized(a, options: options)
        let right = normalized(b, options: options)
        return Set(left.keys).union(right.keys).sorted().compactMap { key in
            switch (left[key], right[key]) {
            case let (old?, new?) where old != new: return .init(id: key, kind: .changed, label: key, before: old, after: new)
            case let (nil, new?): return .init(id: key, kind: .added, label: key, before: nil, after: new)
            case let (old?, nil): return .init(id: key, kind: .removed, label: key, before: old, after: nil)
            default: return nil
            }
        }
    }

    private static func normalized(_ events: [MIDIEvent], options: CaptureDiffOptions) -> [String: String] {
        var values: [String: String] = [:]
        for event in events {
            guard let message = event.message else { continue }
            switch message {
            case let .controlChange(channel, controller, value): values["CC ch\(channel + 1) #\(controller)"] = String(value)
            case let .programChange(channel, program): values["PC ch\(channel + 1)"] = String(program)
            case let .pitchBend(channel, value): values["Pitch Bend ch\(channel + 1)"] = String(value)
            case let .noteOn(channel, note, velocity) where options.includeNotes: values["Note ch\(channel + 1) #\(note)"] = "on \(velocity)"
            case let .noteOff(channel, note, velocity) where options.includeNotes: values["Note ch\(channel + 1) #\(note)"] = "off \(velocity)"
            case .realtime(0xF8) where options.includeClock: values["Clock"] = String((Int(values["Clock"] ?? "0") ?? 0) + 1)
            case .realtime(0xFE) where options.includeActiveSensing: values["Active Sensing"] = String((Int(values["Active Sensing"] ?? "0") ?? 0) + 1)
            case let .realtime(status) where status != 0xF8 && status != 0xFE: values["Realtime \(String(format: "%02X", status))"] = "present"
            case let .systemExclusive(bytes): values["SysEx \(bytes.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " "))"] = "\(bytes.count) bytes"
            case let .systemCommon(status, data): values["System \(String(format: "%02X", status))"] = data.map(String.init).joined(separator: ",")
            default: continue
            }
        }
        return values
    }
}

public enum CaptureExporter {
    public static func csv(events: [MIDIEvent], bpm: Double = 120, ppqn: Int = 480) -> String {
        guard let first = events.first?.timestampNanoseconds else { return "tick,status,data1,data2\n" }
        var rows = ["tick,status,data1,data2"]
        for event in events {
            let bytes = event.message?.canonicalBytes ?? event.rawBytes
            guard bytes.count >= 2, bytes[0] < 0xF0 else { continue }
            let seconds = Double(event.timestampNanoseconds - first) / 1_000_000_000
            let tick = Int((seconds * bpm * Double(ppqn) / 60).rounded())
            rows.append("\(tick),\(bytes[0]),\(bytes[1]),\(bytes.count > 2 ? bytes[2] : 0)")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func smf(events: [MIDIEvent], bpm: Double = 120, ppqn: UInt16 = 480) -> Data {
        guard let first = events.first?.timestampNanoseconds else { return emptySMF(ppqn: ppqn) }
        var track: [UInt8] = [0, 0xFF, 0x51, 3]
        let micros = Int(60_000_000 / bpm)
        track += [UInt8((micros >> 16) & 0xFF), UInt8((micros >> 8) & 0xFF), UInt8(micros & 0xFF)]
        var previousTick = 0
        for event in events {
            let bytes = event.message?.canonicalBytes ?? event.rawBytes
            guard let status = bytes.first, status < 0xF0 else { continue }
            let seconds = Double(event.timestampNanoseconds - first) / 1_000_000_000
            let tick = Int((seconds * bpm * Double(ppqn) / 60).rounded())
            track += variableLength(max(0, tick - previousTick)) + bytes
            previousTick = tick
        }
        track += [0, 0xFF, 0x2F, 0]
        var data = Data("MThd".utf8)
        data += be32(6) + be16(0) + be16(1) + be16(ppqn)
        data += Data("MTrk".utf8) + be32(UInt32(track.count)) + Data(track)
        return data
    }

    private static func emptySMF(ppqn: UInt16) -> Data {
        let track: [UInt8] = [0, 0xFF, 0x2F, 0]
        return Data("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(ppqn) + Data("MTrk".utf8) + be32(4) + Data(track)
    }
    private static func variableLength(_ value: Int) -> [UInt8] {
        var value = value
        var buffer = [UInt8(value & 0x7F)]
        while value >> 7 > 0 { value >>= 7; buffer.insert(UInt8((value & 0x7F) | 0x80), at: 0) }
        return buffer
    }
    private static func be16(_ value: UInt16) -> Data { Data([UInt8(value >> 8), UInt8(value & 0xFF)]) }
    private static func be32(_ value: UInt32) -> Data { Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]) }
}

private extension Data {
    static func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }
}
