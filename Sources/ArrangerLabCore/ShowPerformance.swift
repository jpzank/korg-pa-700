import Foundation

public enum ShowKeyboardPart: String, CaseIterable, Codable, Identifiable, Sendable {
    case upper1 = "Upper 1"
    case upper2 = "Upper 2"
    case upper3 = "Upper 3"
    case lower = "Lower"

    public var id: String { rawValue }
}

public struct ShowPresetPart: Codable, Equatable, Identifiable, Sendable {
    public let part: ShowKeyboardPart
    public var displayName: String
    public var isEnabled: Bool
    /// Stable PA700 catalogue address identifier when the part was chosen from
    /// the sound browser. Older presets can keep this nil and still decode.
    public var soundID: String?
    public var soundLibrary: String?

    public var id: ShowKeyboardPart { part }

    public init(
        part: ShowKeyboardPart,
        displayName: String = "",
        isEnabled: Bool = true,
        soundID: String? = nil,
        soundLibrary: String? = nil
    ) {
        self.part = part
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.soundID = soundID
        self.soundLibrary = soundLibrary
    }

    public func validate() throws {
        if isEnabled, displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArrangerLabError.invalidValue("enabled show part must have a display name")
        }
    }
}

public enum ShowChartLineKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case section
    case chords
    case lyrics
    case space

    public var id: String { rawValue }
}

public struct ShowChartLine: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: ShowChartLineKind
    public var text: String

    public init(id: UUID = UUID(), kind: ShowChartLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }

    public func validate() throws {
        if kind != .space, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArrangerLabError.invalidValue("non-space show chart lines cannot be empty")
        }
    }

    public static func editorText(from lines: [ShowChartLine]) -> String {
        lines.map { line in
            switch line.kind {
            case .section: return "# \(line.text)"
            case .chords: return "> \(line.text)"
            case .lyrics: return line.text
            case .space: return ""
            }
        }
        .joined(separator: "\n")
    }

    public static func parseEditorText(_ text: String) -> [ShowChartLine] {
        text.components(separatedBy: .newlines).map { rawLine in
            if rawLine.isEmpty { return ShowChartLine(kind: .space, text: "") }
            if rawLine.hasPrefix("# ") {
                return ShowChartLine(kind: .section, text: String(rawLine.dropFirst(2)))
            }
            if rawLine.hasPrefix("> ") {
                return ShowChartLine(kind: .chords, text: String(rawLine.dropFirst(2)))
            }
            return ShowChartLine(kind: .lyrics, text: rawLine)
        }
    }
}

public struct ShowPresetSource: Codable, Equatable, Sendable {
    public var catalogID: String
    public var catalogSongID: String
    public var documentName: String
    public var startPage: Int
    public var endPage: Int
    public var sourceURL: String?

    public init(
        catalogID: String,
        catalogSongID: String,
        documentName: String,
        startPage: Int,
        endPage: Int,
        sourceURL: String? = nil
    ) {
        self.catalogID = catalogID
        self.catalogSongID = catalogSongID
        self.documentName = documentName
        self.startPage = startPage
        self.endPage = endPage
        self.sourceURL = sourceURL
    }

    public func validate() throws {
        guard !catalogID.isEmpty, !catalogSongID.isEmpty, !documentName.isEmpty,
              startPage >= 0, endPage >= startPage else {
            throw ArrangerLabError.invalidValue("invalid show preset source reference")
        }
        if let sourceURL {
            guard let components = URLComponents(string: sourceURL),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil else {
                throw ArrangerLabError.invalidValue("invalid show preset source URL")
            }
        }
    }
}

public struct ShowReaderSettings: Codable, Equatable, Sendable {
    public var showChords: Bool
    public var fontScale: Double

    public init(showChords: Bool = true, fontScale: Double = 1) {
        self.showChords = showChords
        self.fontScale = fontScale
    }

    public func validate() throws {
        guard (0.75...2).contains(fontScale) else {
            throw ArrangerLabError.invalidValue("show reader font scale must be 0.75...2")
        }
    }
}

public struct ShowPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var songTitle: String
    public var songBookNumber: Int?
    public var transposeSemitones: Int
    public var parts: [ShowPresetPart]
    public var effectsSummary: String
    public var notes: String
    public var originalKey: String
    public var source: ShowPresetSource?
    public var chartLines: [ShowChartLine]
    public var readerSettings: ShowReaderSettings
    public var confirmedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public var isConfirmed: Bool { confirmedAt != nil && songBookNumber != nil }

    public init(
        id: UUID = UUID(),
        songTitle: String,
        songBookNumber: Int? = nil,
        transposeSemitones: Int = 0,
        parts: [ShowPresetPart] = ShowPreset.defaultParts(),
        effectsSummary: String = "",
        notes: String = "",
        originalKey: String = "",
        source: ShowPresetSource? = nil,
        chartLines: [ShowChartLine] = [],
        readerSettings: ShowReaderSettings = .init(),
        confirmedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.songTitle = songTitle
        self.songBookNumber = songBookNumber
        self.transposeSemitones = transposeSemitones
        self.parts = parts
        self.effectsSummary = effectsSummary
        self.notes = notes
        self.originalKey = originalKey
        self.source = source
        self.chartLines = chartLines
        self.readerSettings = readerSettings
        self.confirmedAt = confirmedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, songTitle, songBookNumber, transposeSemitones, parts, effectsSummary, notes
        case originalKey, source, chartLines, readerSettings, confirmedAt, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        songTitle = try container.decode(String.self, forKey: .songTitle)
        songBookNumber = try container.decodeIfPresent(Int.self, forKey: .songBookNumber)
        transposeSemitones = try container.decode(Int.self, forKey: .transposeSemitones)
        parts = try container.decode([ShowPresetPart].self, forKey: .parts)
        effectsSummary = try container.decode(String.self, forKey: .effectsSummary)
        notes = try container.decode(String.self, forKey: .notes)
        originalKey = try container.decodeIfPresent(String.self, forKey: .originalKey) ?? ""
        source = try container.decodeIfPresent(ShowPresetSource.self, forKey: .source)
        chartLines = try container.decodeIfPresent([ShowChartLine].self, forKey: .chartLines) ?? []
        readerSettings = try container.decodeIfPresent(ShowReaderSettings.self, forKey: .readerSettings) ?? .init()
        confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public static func defaultParts() -> [ShowPresetPart] {
        ShowKeyboardPart.allCases.map { part in
            .init(part: part, displayName: part == .upper1 ? "Não informado" : "Desligado", isEnabled: part == .upper1)
        }
    }

    public func validate() throws {
        guard !songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArrangerLabError.invalidValue("show preset song title cannot be empty")
        }
        if let songBookNumber, !(0...9_999).contains(songBookNumber) {
            throw ArrangerLabError.invalidValue("show preset SongBook number must be 0...9999")
        }
        if confirmedAt != nil, songBookNumber == nil {
            throw ArrangerLabError.invalidValue("confirmed show preset must have a SongBook number")
        }
        guard (-12...12).contains(transposeSemitones) else {
            throw ArrangerLabError.invalidValue("show preset transpose must be -12...12")
        }
        guard parts.count == ShowKeyboardPart.allCases.count,
              Set(parts.map(\.part)) == Set(ShowKeyboardPart.allCases) else {
            throw ArrangerLabError.invalidValue("show preset must contain Upper 1, Upper 2, Upper 3 and Lower exactly once")
        }
        guard Set(chartLines.map(\.id)).count == chartLines.count else {
            throw ArrangerLabError.invalidValue("show chart contains duplicate line IDs")
        }
        try parts.forEach { try $0.validate() }
        try chartLines.forEach { try $0.validate() }
        try source?.validate()
        try readerSettings.validate()
    }

    public func hasSameOperationalReference(as other: ShowPreset) -> Bool {
        songBookNumber == other.songBookNumber
            && transposeSemitones == other.transposeSemitones
            && parts == other.parts
            && effectsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                == other.effectsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ShowSetListItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let presetID: UUID

    public init(id: UUID = UUID(), presetID: UUID) {
        self.id = id
        self.presetID = presetID
    }
}

public struct ShowSetList: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var items: [ShowSetListItem]
    public var sourceCatalogID: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        items: [ShowSetListItem] = [],
        sourceCatalogID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.sourceCatalogID = sourceCatalogID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, sourceCatalogID, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([ShowSetListItem].self, forKey: .items)
        sourceCatalogID = try container.decodeIfPresent(String.self, forKey: .sourceCatalogID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArrangerLabError.invalidValue("show set list name cannot be empty")
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw ArrangerLabError.invalidValue("show set list contains duplicate item IDs")
        }
    }
}

public struct ShowPresetFile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var presets: [ShowPreset]

    public init(schemaVersion: Int = 2, presets: [ShowPreset]) {
        self.schemaVersion = schemaVersion
        self.presets = presets
    }
}

public struct ShowSetListFile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var setLists: [ShowSetList]

    public init(schemaVersion: Int = 2, setLists: [ShowSetList]) {
        self.schemaVersion = schemaVersion
        self.setLists = setLists
    }
}

public enum ShowPresetStore {
    public static func save(_ presets: [ShowPreset], to url: URL) throws {
        try presets.forEach { try $0.validate() }
        try createParentDirectory(for: url)
        try encoder.encode(ShowPresetFile(presets: presets)).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> [ShowPreset] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try decoder.decode(ShowPresetFile.self, from: Data(contentsOf: url))
        guard (1...2).contains(file.schemaVersion) else {
            throw ArrangerLabError.corruptCapture("unsupported show preset schema")
        }
        try file.presets.forEach { try $0.validate() }
        return file.presets
    }
}

public enum ShowSetListStore {
    public static func save(_ setLists: [ShowSetList], to url: URL) throws {
        try setLists.forEach { try $0.validate() }
        try createParentDirectory(for: url)
        try encoder.encode(ShowSetListFile(setLists: setLists)).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> [ShowSetList] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try decoder.decode(ShowSetListFile.self, from: Data(contentsOf: url))
        guard (1...2).contains(file.schemaVersion) else {
            throw ArrangerLabError.corruptCapture("unsupported show set list schema")
        }
        try file.setLists.forEach { try $0.validate() }
        return file.setLists
    }
}

public struct BundledShowCatalogEntry: Codable, Equatable, Sendable {
    public let catalogSongID: String
    public let presetID: UUID
    public let songTitle: String
    public let artist: String?
    public let originalKey: String
    public let startPage: Int
    public let endPage: Int
    public let chartLines: [ShowChartLine]
}

public struct BundledShowCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let catalogID: String
    public let name: String
    public let sourceFileName: String
    public let sourceURL: String?
    public let entries: [BundledShowCatalogEntry]

    public static func botecoJul3() throws -> BundledShowCatalog {
        guard let url = Bundle.module.url(forResource: "boteco-jul3-gojam", withExtension: "json") else {
            throw ArrangerLabError.corruptCapture("bundled Boteco Jul3 catalog is missing")
        }
        let catalog = try decoder.decode(BundledShowCatalog.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1, catalog.entries.count == 57 else {
            throw ArrangerLabError.corruptCapture("bundled Boteco Jul3 catalog is invalid")
        }
        return catalog
    }

    public static func showboatJul23() throws -> BundledShowCatalog {
        guard let url = Bundle.module.url(forResource: "showboat-jul-23-gojam", withExtension: "json") else {
            throw ArrangerLabError.corruptCapture("bundled Showboat Jul 23 catalog is missing")
        }
        let catalog = try decoder.decode(BundledShowCatalog.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1, catalog.entries.count == 26 else {
            throw ArrangerLabError.corruptCapture("bundled Showboat Jul 23 catalog is invalid")
        }
        return catalog
    }

    public static func allBundled() throws -> [BundledShowCatalog] {
        [try botecoJul3(), try showboatJul23()]
    }

    public static func bundled(catalogID: String) throws -> BundledShowCatalog? {
        try allBundled().first { $0.catalogID == catalogID }
    }

    public func preset(for entry: BundledShowCatalogEntry, id: UUID? = nil, now: Date = Date()) -> ShowPreset {
        ShowPreset(
            id: id ?? entry.presetID,
            songTitle: entry.songTitle,
            songBookNumber: nil,
            notes: entry.artist.map { "Artista: \($0)" } ?? "",
            originalKey: entry.originalKey,
            source: .init(
                catalogID: catalogID,
                catalogSongID: entry.catalogSongID,
                documentName: sourceFileName,
                startPage: entry.startPage,
                endPage: entry.endPage,
                sourceURL: sourceURL
            ),
            chartLines: entry.chartLines,
            createdAt: now,
            updatedAt: now
        )
    }

    public func merging(
        presets existingPresets: [ShowPreset],
        setLists existingSetLists: [ShowSetList],
        now: Date = Date()
    ) -> (presets: [ShowPreset], setLists: [ShowSetList], importedCount: Int) {
        var presets = existingPresets
        var importedCount = 0
        var resolvedPresetIDs: [String: UUID] = [:]
        var usedIDs = Set(presets.map(\.id))

        for entry in entries {
            let sourceIndex = presets.firstIndex { preset in
                preset.source?.catalogID == catalogID && preset.source?.catalogSongID == entry.catalogSongID
            }
            let titleIndex = presets.firstIndex { preset in
                preset.source == nil && normalized(preset.songTitle) == normalized(entry.songTitle)
            }
            if let index = sourceIndex ?? titleIndex {
                var preset = presets[index]
                var changed = false
                if preset.source == nil {
                    preset.source = .init(
                        catalogID: catalogID,
                        catalogSongID: entry.catalogSongID,
                        documentName: sourceFileName,
                        startPage: entry.startPage,
                        endPage: entry.endPage,
                        sourceURL: sourceURL
                    )
                    changed = true
                }
                if preset.originalKey.isEmpty {
                    preset.originalKey = entry.originalKey
                    changed = true
                }
                if preset.chartLines.isEmpty {
                    preset.chartLines = entry.chartLines
                    changed = true
                }
                if changed {
                    preset.updatedAt = now
                    presets[index] = preset
                }
                resolvedPresetIDs[entry.catalogSongID] = preset.id
            } else {
                let id = usedIDs.contains(entry.presetID) ? UUID() : entry.presetID
                let preset = preset(for: entry, id: id, now: now)
                presets.append(preset)
                usedIDs.insert(id)
                resolvedPresetIDs[entry.catalogSongID] = id
                importedCount += 1
            }
        }

        var setLists = existingSetLists
        if let index = setLists.firstIndex(where: {
            $0.sourceCatalogID == catalogID || normalized($0.name) == normalized(name)
        }) {
            var changed = false
            if setLists[index].sourceCatalogID == nil {
                setLists[index].sourceCatalogID = catalogID
                changed = true
            }
            var presentPresetIDs = Set(setLists[index].items.map(\.presetID))
            for entry in entries {
                guard let presetID = resolvedPresetIDs[entry.catalogSongID], !presentPresetIDs.contains(presetID) else { continue }
                setLists[index].items.append(.init(presetID: presetID))
                presentPresetIDs.insert(presetID)
                changed = true
            }
            if changed {
                setLists[index].updatedAt = now
            }
        } else {
            let items: [ShowSetListItem] = entries.compactMap { entry -> ShowSetListItem? in
                guard let presetID = resolvedPresetIDs[entry.catalogSongID] else { return nil }
                return ShowSetListItem(presetID: presetID)
            }
            setLists.append(.init(name: name, items: items, sourceCatalogID: catalogID, createdAt: now, updatedAt: now))
        }
        return (presets, setLists, importedCount)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func createParentDirectory(for url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
}

private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()
