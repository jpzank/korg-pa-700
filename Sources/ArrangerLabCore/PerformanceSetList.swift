import Foundation

public struct PerformanceSetListItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sceneID: UUID

    public init(id: UUID = UUID(), sceneID: UUID) {
        self.id = id
        self.sceneID = sceneID
    }
}

public struct PerformanceSetList: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var items: [PerformanceSetListItem]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        items: [PerformanceSetListItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArrangerLabError.invalidValue("set list name cannot be empty")
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw ArrangerLabError.invalidValue("set list contains duplicate item IDs")
        }
    }
}

public struct PerformanceSetListFile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var setLists: [PerformanceSetList]

    public init(schemaVersion: Int = 1, setLists: [PerformanceSetList]) {
        self.schemaVersion = schemaVersion
        self.setLists = setLists
    }
}

public enum PerformanceSetListStore {
    public static func save(_ setLists: [PerformanceSetList], to url: URL) throws {
        try setLists.forEach { try $0.validate() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(PerformanceSetListFile(setLists: setLists)).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> [PerformanceSetList] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try decoder.decode(PerformanceSetListFile.self, from: Data(contentsOf: url))
        guard file.schemaVersion == 1 else { throw ArrangerLabError.corruptCapture("unsupported set list schema") }
        try file.setLists.forEach { try $0.validate() }
        return file.setLists
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
