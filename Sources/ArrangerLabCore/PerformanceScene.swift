import Foundation

public struct PerformanceScenePart: Codable, Equatable, Identifiable, Sendable {
    public let target: KeyboardPartTarget
    public var presetID: String?
    public var volume: Double
    public var expression: Double
    public var pan: Double

    public var id: String { "\(target.zone.rawValue)-\(target.layer)" }

    public init(
        target: KeyboardPartTarget,
        presetID: String? = nil,
        volume: Double = 0.75,
        expression: Double = 1,
        pan: Double = 0
    ) {
        self.target = target
        self.presetID = presetID
        self.volume = volume
        self.expression = expression
        self.pan = pan
    }

    public func validate() throws {
        guard target.layer > 0 else { throw ArrangerLabError.invalidValue("scene part layer must be positive") }
        guard (0...1).contains(volume) else { throw ArrangerLabError.invalidValue("scene part volume must be 0...1") }
        guard (0...1).contains(expression) else { throw ArrangerLabError.invalidValue("scene part expression must be 0...1") }
        guard (-1...1).contains(pan) else { throw ArrangerLabError.invalidValue("scene part pan must be -1...1") }
        if let presetID, presetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArrangerLabError.invalidValue("scene preset ID cannot be empty")
        }
    }
}

public struct PerformanceScene: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var keyboardSetEntryID: String?
    public var styleID: String?
    public var variation: Int
    public var parts: [PerformanceScenePart]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        keyboardSetEntryID: String? = nil,
        styleID: String? = nil,
        variation: Int = 1,
        parts: [PerformanceScenePart] = PerformanceScene.defaultParts(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.keyboardSetEntryID = keyboardSetEntryID
        self.styleID = styleID
        self.variation = variation
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func defaultParts() -> [PerformanceScenePart] {
        [
            .init(target: try! .init(zone: .right, layer: 1)),
            .init(target: try! .init(zone: .right, layer: 2)),
            .init(target: try! .init(zone: .right, layer: 3)),
            .init(target: try! .init(zone: .left, layer: 1))
        ]
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArrangerLabError.invalidValue("scene name cannot be empty")
        }
        guard (1...4).contains(variation) else {
            throw ArrangerLabError.invalidValue("scene variation must be 1...4")
        }
        if let keyboardSetEntryID, keyboardSetEntryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArrangerLabError.invalidValue("scene Keyboard Set ID cannot be empty")
        }
        if let styleID, styleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArrangerLabError.invalidValue("scene Style ID cannot be empty")
        }
        guard Set(parts.map(\.target)).count == parts.count else {
            throw ArrangerLabError.invalidValue("scene contains duplicate keyboard parts")
        }
        try parts.forEach { try $0.validate() }
    }

    public func actions() throws -> [InstrumentAction] {
        try validate()
        var result: [InstrumentAction] = []
        if let styleID { result.append(.selectArrangerStyle(styleID: styleID)) }
        if let keyboardSetEntryID { result.append(.selectKeyboardSetLibraryEntry(entryID: keyboardSetEntryID)) }
        let variations: [ArrangerElement] = [.variation1, .variation2, .variation3, .variation4]
        result.append(.selectArrangerElement(variations[variation - 1]))
        for part in parts {
            if let presetID = part.presetID {
                result.append(.selectDevicePreset(target: part.target, presetID: presetID))
            }
            result.append(.setPartVolume(target: part.target, level: part.volume))
            result.append(.setPartExpression(target: part.target, level: part.expression))
            result.append(.setPartPan(target: part.target, position: part.pan))
        }
        return result
    }
}

public struct PerformanceSceneFile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var scenes: [PerformanceScene]

    public init(schemaVersion: Int = 1, scenes: [PerformanceScene]) {
        self.schemaVersion = schemaVersion
        self.scenes = scenes
    }
}

public enum PerformanceSceneStore {
    public static func save(_ scenes: [PerformanceScene], to url: URL) throws {
        try scenes.forEach { try $0.validate() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(PerformanceSceneFile(scenes: scenes)).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> [PerformanceScene] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try decoder.decode(PerformanceSceneFile.self, from: Data(contentsOf: url))
        guard file.schemaVersion == 1 else { throw ArrangerLabError.corruptCapture("unsupported scene schema") }
        try file.scenes.forEach { try $0.validate() }
        return file.scenes
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
