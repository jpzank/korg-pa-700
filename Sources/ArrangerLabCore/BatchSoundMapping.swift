import Foundation

public enum BatchSoundEntrySource: String, Codable, Equatable, Sendable {
    case midiCapture
    case officialManual
}

public enum BatchSoundVerificationBasis: String, Codable, Equatable, Sendable {
    /// The exact preset was auditioned and confirmed by name and sound.
    case individualAudition
    /// The preset belongs to an official/captured catalogue whose addressing was
    /// verified bank-by-bank and whose entries were accepted from user samples.
    case catalogSampling
}

public struct BatchSoundEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let selection: MIDIProgramSelection
    public var displayName: String
    public var occurrenceCount: Int
    public let firstCapturedAt: Date
    public var lastCapturedAt: Date
    public var status: MappingStatus
    public var library: String?
    public var category: String?
    public var source: BatchSoundEntrySource?
    public var isFavorite: Bool
    public var lastAuditionedAt: Date?
    public var verificationExperimentPath: String?
    public var verificationBasis: BatchSoundVerificationBasis?

    public init(
        selection: MIDIProgramSelection,
        displayName: String = "",
        occurrenceCount: Int = 1,
        firstCapturedAt: Date = Date(),
        lastCapturedAt: Date = Date(),
        status: MappingStatus = .draft,
        library: String? = nil,
        category: String? = nil,
        source: BatchSoundEntrySource? = .midiCapture,
        isFavorite: Bool = false,
        lastAuditionedAt: Date? = nil,
        verificationExperimentPath: String? = nil,
        verificationBasis: BatchSoundVerificationBasis? = nil
    ) {
        id = Self.identifier(for: selection)
        self.selection = selection
        self.displayName = displayName
        self.occurrenceCount = occurrenceCount
        self.firstCapturedAt = firstCapturedAt
        self.lastCapturedAt = lastCapturedAt
        self.status = status
        self.library = library
        self.category = category
        self.source = source
        self.isFavorite = isFavorite
        self.lastAuditionedAt = lastAuditionedAt
        self.verificationExperimentPath = verificationExperimentPath
        self.verificationBasis = verificationBasis
    }

    private enum CodingKeys: String, CodingKey {
        case id, selection, displayName, occurrenceCount, firstCapturedAt, lastCapturedAt
        case status, library, category, source, isFavorite, lastAuditionedAt, verificationExperimentPath, verificationBasis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decode(MIDIProgramSelection.self, forKey: .selection)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? Self.identifier(for: selection)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount) ?? 0
        firstCapturedAt = try container.decodeIfPresent(Date.self, forKey: .firstCapturedAt) ?? .distantPast
        lastCapturedAt = try container.decodeIfPresent(Date.self, forKey: .lastCapturedAt) ?? firstCapturedAt
        status = try container.decodeIfPresent(MappingStatus.self, forKey: .status) ?? .draft
        library = try container.decodeIfPresent(String.self, forKey: .library)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        source = try container.decodeIfPresent(BatchSoundEntrySource.self, forKey: .source)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        lastAuditionedAt = try container.decodeIfPresent(Date.self, forKey: .lastAuditionedAt)
        verificationExperimentPath = try container.decodeIfPresent(String.self, forKey: .verificationExperimentPath)
        verificationBasis = try container.decodeIfPresent(BatchSoundVerificationBasis.self, forKey: .verificationBasis)
    }

    public static func identifier(for selection: MIDIProgramSelection) -> String {
        "ch\(selection.channel + 1)-\(selection.bankMSB)-\(selection.bankLSB)-\(selection.program)"
    }

    public var effectiveName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "PA700 \(selection.bankMSB).\(selection.bankLSB).\(selection.program)" : trimmed
    }
}

public struct BatchSoundImportSummary: Equatable, Sendable {
    public let inserted: Int
    public let enriched: Int
    public let preservedCapturedNames: Int

    public init(inserted: Int, enriched: Int, preservedCapturedNames: Int) {
        self.inserted = inserted
        self.enriched = enriched
        self.preservedCapturedNames = preservedCapturedNames
    }
}

public enum BatchSoundFastValidationPlan {
    /// Exercises every distinct CC0/CC32 bank once, then every captured User sound.
    /// This validates catalogue addressing without pretending that every displayed
    /// name received an individual physical confirmation.
    public static func representatives(from entries: [BatchSoundEntry]) -> [BatchSoundEntry] {
        let sorted = entries.sorted { lhs, rhs in
            let a = lhs.selection
            let b = rhs.selection
            return (a.bankMSB, a.bankLSB, a.program, a.channel)
                < (b.bankMSB, b.bankLSB, b.program, b.channel)
        }

        var result: [BatchSoundEntry] = []
        var selectedIDs = Set<String>()
        var seenBanks = Set<String>()

        for entry in sorted {
            let selection = entry.selection
            let bankID = "\(selection.channel)-\(selection.bankMSB)-\(selection.bankLSB)"
            guard seenBanks.insert(bankID).inserted else { continue }
            result.append(entry)
            selectedIDs.insert(entry.id)
        }

        for entry in sorted where isCapturedUser(entry) && selectedIDs.insert(entry.id).inserted {
            result.append(entry)
        }
        return result
    }

    public static func bankCount(in entries: [BatchSoundEntry]) -> Int {
        Set(entries.map {
            "\($0.selection.channel)-\($0.selection.bankMSB)-\($0.selection.bankLSB)"
        }).count
    }

    public static func capturedUserCount(in entries: [BatchSoundEntry]) -> Int {
        entries.filter(isCapturedUser).count
    }

    private static func isCapturedUser(_ entry: BatchSoundEntry) -> Bool {
        entry.source == .midiCapture
            && entry.selection.bankMSB == 121
            && (64...67).contains(entry.selection.bankLSB)
    }
}

public struct BatchSoundScreenCapture: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var label: String
    public let startedAt: Date
    public var endedAt: Date?
    public var entryIDs: [String]

    public init(
        id: UUID = UUID(),
        label: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        entryIDs: [String] = []
    ) {
        self.id = id
        self.label = label
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.entryIDs = entryIDs
    }

    public var isOpen: Bool { endedAt == nil }
}

public struct BatchSoundCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let model: String
    public let firmware: String
    public let midiPreset: String
    public let startedAt: Date
    public var updatedAt: Date
    public var captureCount: Int
    public var entries: [BatchSoundEntry]
    public var screens: [BatchSoundScreenCapture]

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        model: String,
        firmware: String,
        midiPreset: String,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        captureCount: Int = 0,
        entries: [BatchSoundEntry] = [],
        screens: [BatchSoundScreenCapture] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.model = model
        self.firmware = firmware
        self.midiPreset = midiPreset
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.captureCount = captureCount
        self.entries = entries
        self.screens = screens
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, model, firmware, midiPreset, startedAt, updatedAt, captureCount, entries, screens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        firmware = try container.decode(String.self, forKey: .firmware)
        midiPreset = try container.decode(String.self, forKey: .midiPreset)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        captureCount = try container.decode(Int.self, forKey: .captureCount)
        entries = try container.decode([BatchSoundEntry].self, forKey: .entries)
        screens = try container.decodeIfPresent([BatchSoundScreenCapture].self, forKey: .screens) ?? []
    }
}

public enum BatchSoundAssignmentError: Error, Equatable, LocalizedError, Sendable {
    case screenNotFound
    case screenStillOpen
    case countMismatch(expected: Int, received: Int)
    case conflictingName(address: String, existing: String, received: String)

    public var errorDescription: String? {
        switch self {
        case .screenNotFound:
            return "A tela capturada não foi encontrada."
        case .screenStillOpen:
            return "Encerre a captura desta tela antes de cadastrar os nomes."
        case let .countMismatch(expected, received):
            return "A tela tem \(expected) timbres, mas foram informados \(received) nomes. Nada foi alterado."
        case let .conflictingName(address, existing, received):
            return "Conflito em \(address): já estava como “\(existing)” e a foto informa “\(received)”. Nada foi alterado."
        }
    }
}

public struct BatchSoundCollector: Sendable {
    public private(set) var catalog: BatchSoundCatalog
    private var bankMSB: [UInt8: UInt8] = [:]
    private var bankLSB: [UInt8: UInt8] = [:]

    public init(catalog: BatchSoundCatalog) {
        var normalized = catalog
        normalized.screens.removeAll { !$0.isOpen && $0.entryIDs.isEmpty }
        for index in normalized.entries.indices where normalized.entries[index].source == nil {
            if normalized.entries[index].occurrenceCount > 0 {
                normalized.entries[index].source = .midiCapture
            }
        }
        for index in normalized.entries.indices
        where normalized.entries[index].status == .verified && normalized.entries[index].verificationBasis == nil {
            normalized.entries[index].verificationBasis = .individualAudition
        }
        self.catalog = normalized
    }

    public var activeScreen: BatchSoundScreenCapture? {
        catalog.screens.last(where: \.isOpen)
    }

    @discardableResult
    public mutating func beginScreen(now: Date = Date()) -> BatchSoundScreenCapture {
        if let index = catalog.screens.lastIndex(where: \.isOpen) {
            catalog.screens[index].endedAt = now
        }
        let screen = BatchSoundScreenCapture(
            label: String(format: "Tela %02d", catalog.screens.count + 1),
            startedAt: now
        )
        catalog.screens.append(screen)
        catalog.updatedAt = now
        return screen
    }

    @discardableResult
    public mutating func endScreen(now: Date = Date()) -> BatchSoundScreenCapture? {
        guard let index = catalog.screens.lastIndex(where: \.isOpen) else { return nil }
        catalog.screens[index].endedAt = now
        catalog.updatedAt = now
        let screen = catalog.screens[index]
        if screen.entryIDs.isEmpty {
            catalog.screens.remove(at: index)
        }
        return screen
    }

    @discardableResult
    public mutating func consume(
        _ event: MIDIEvent,
        channel requiredChannel: UInt8 = 0,
        suggestedName: (MIDIProgramSelection) -> String? = { _ in nil },
        now: Date = Date()
    ) -> BatchSoundEntry? {
        guard event.direction == .input,
              let message = event.message,
              event.rawBytes == message.canonicalBytes else { return nil }

        switch message {
        case let .controlChange(channel, 0, value) where channel == requiredChannel:
            bankMSB[channel] = value
        case let .controlChange(channel, 32, value) where channel == requiredChannel:
            bankLSB[channel] = value
        case let .programChange(channel, program) where channel == requiredChannel:
            guard let msb = bankMSB[channel], let lsb = bankLSB[channel] else { return nil }
            let selection = MIDIProgramSelection(channel: channel, bankMSB: msb, bankLSB: lsb, program: program)
            catalog.captureCount += 1
            catalog.updatedAt = now
            let id = BatchSoundEntry.identifier(for: selection)
            if let index = catalog.entries.firstIndex(where: { $0.id == id }) {
                catalog.entries[index].occurrenceCount += 1
                catalog.entries[index].lastCapturedAt = now
                catalog.entries[index].source = .midiCapture
                appendToActiveScreen(entryID: id)
                return catalog.entries[index]
            }
            let entry = BatchSoundEntry(
                selection: selection,
                displayName: suggestedName(selection) ?? "",
                firstCapturedAt: now,
                lastCapturedAt: now
            )
            catalog.entries.append(entry)
            appendToActiveScreen(entryID: id)
            return entry
        default:
            return nil
        }
        return nil
    }

    @discardableResult
    public mutating func importOfficialSounds(
        _ sounds: [PA700OfficialSound],
        now: Date = Date()
    ) -> BatchSoundImportSummary {
        var inserted = 0
        var enriched = 0
        var preservedCapturedNames = 0

        for sound in sounds {
            let selection = sound.selection
            let id = BatchSoundEntry.identifier(for: selection)
            if let index = catalog.entries.firstIndex(where: { $0.id == id }) {
                let currentName = catalog.entries[index].displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentName.isEmpty {
                    catalog.entries[index].displayName = sound.name
                } else if currentName != sound.name {
                    preservedCapturedNames += 1
                }
                catalog.entries[index].library = sound.library
                catalog.entries[index].category = sound.category
                if catalog.entries[index].source == nil, catalog.entries[index].occurrenceCount > 0 {
                    catalog.entries[index].source = .midiCapture
                }
                enriched += 1
                continue
            }

            catalog.entries.append(BatchSoundEntry(
                selection: selection,
                displayName: sound.name,
                occurrenceCount: 0,
                firstCapturedAt: now,
                lastCapturedAt: now,
                status: .draft,
                library: sound.library,
                category: sound.category,
                source: .officialManual
            ))
            inserted += 1
        }

        catalog.updatedAt = now
        return BatchSoundImportSummary(
            inserted: inserted,
            enriched: enriched,
            preservedCapturedNames: preservedCapturedNames
        )
    }

    public mutating func rename(id: String, displayName: String, now: Date = Date()) {
        guard let index = catalog.entries.firstIndex(where: { $0.id == id }) else { return }
        catalog.entries[index].displayName = displayName
        catalog.updatedAt = now
    }

    public mutating func setFavorite(id: String, isFavorite: Bool, now: Date = Date()) {
        guard let index = catalog.entries.firstIndex(where: { $0.id == id }) else { return }
        catalog.entries[index].isFavorite = isFavorite
        catalog.updatedAt = now
    }

    public mutating func markAuditioned(id: String, now: Date = Date()) {
        guard let index = catalog.entries.firstIndex(where: { $0.id == id }) else { return }
        catalog.entries[index].lastAuditionedAt = now
        catalog.updatedAt = now
    }

    public mutating func markVerified(id: String, experimentPath: String, now: Date = Date()) {
        guard let index = catalog.entries.firstIndex(where: { $0.id == id }) else { return }
        catalog.entries[index].status = .verified
        catalog.entries[index].verificationExperimentPath = experimentPath
        catalog.entries[index].verificationBasis = .individualAudition
        catalog.entries[index].lastAuditionedAt = now
        catalog.updatedAt = now
    }

    /// Promotes the remaining catalogue after a representative bank sweep and
    /// explicit user acceptance of multiple samples. Existing individual
    /// verifications retain their stronger evidence and original package path.
    @discardableResult
    public mutating func markAllVerifiedBySampling(experimentPath: String, now: Date = Date()) -> Int {
        var promoted = 0
        for index in catalog.entries.indices where catalog.entries[index].status != .verified {
            catalog.entries[index].status = .verified
            catalog.entries[index].verificationExperimentPath = experimentPath
            catalog.entries[index].verificationBasis = .catalogSampling
            promoted += 1
        }
        catalog.updatedAt = now
        return promoted
    }

    public mutating func undoLastScreenCapture(now: Date = Date()) -> BatchSoundEntry? {
        guard let screenIndex = catalog.screens.lastIndex(where: \.isOpen),
              let entryID = catalog.screens[screenIndex].entryIDs.popLast(),
              let entryIndex = catalog.entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        catalog.captureCount = max(0, catalog.captureCount - 1)
        catalog.entries[entryIndex].occurrenceCount -= 1
        let removed = catalog.entries[entryIndex]
        if catalog.entries[entryIndex].occurrenceCount <= 0 {
            catalog.entries.remove(at: entryIndex)
        }
        catalog.updatedAt = now
        return removed
    }

    public mutating func assignNames(
        screenID: UUID,
        names: [String],
        now: Date = Date()
    ) throws {
        guard let screen = catalog.screens.first(where: { $0.id == screenID }) else {
            throw BatchSoundAssignmentError.screenNotFound
        }
        guard !screen.isOpen else { throw BatchSoundAssignmentError.screenStillOpen }
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cleaned.count == screen.entryIDs.count else {
            throw BatchSoundAssignmentError.countMismatch(expected: screen.entryIDs.count, received: cleaned.count)
        }
        for (entryID, name) in zip(screen.entryIDs, cleaned) {
            guard let entry = catalog.entries.first(where: { $0.id == entryID }) else { continue }
            let existing = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !existing.isEmpty, existing != name {
                throw BatchSoundAssignmentError.conflictingName(
                    address: "\(entry.selection.bankMSB).\(entry.selection.bankLSB).\(entry.selection.program)",
                    existing: existing,
                    received: name
                )
            }
        }
        for (entryID, name) in zip(screen.entryIDs, cleaned) {
            rename(id: entryID, displayName: name, now: now)
        }
        catalog.updatedAt = now
    }

    private mutating func appendToActiveScreen(entryID: String) {
        guard let index = catalog.screens.lastIndex(where: \.isOpen) else { return }
        catalog.screens[index].entryIDs.append(entryID)
    }
}

public struct BatchSoundDraftExport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceCatalogID: UUID
    public let model: String
    public let firmware: String
    public let generatedAt: Date
    public let presets: [DevicePreset]
}

public enum BatchSoundCatalogStore {
    public static func save(_ catalog: BatchSoundCatalog, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(catalog).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> BatchSoundCatalog {
        let catalog = try decoder.decode(BatchSoundCatalog.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1 else {
            throw ArrangerLabError.corruptCapture("unsupported batch catalog schema \(catalog.schemaVersion)")
        }
        return catalog
    }

    public static func draftExport(from catalog: BatchSoundCatalog, generatedAt: Date = Date()) -> BatchSoundDraftExport {
        let formatter = ISO8601DateFormatter()
        let presets = catalog.entries.map { entry in
            let selection = entry.selection
            let bytes: [UInt8] = [
                0xB0 | selection.channel, 0x00, selection.bankMSB,
                0xB0 | selection.channel, 0x20, selection.bankLSB,
                0xC0 | selection.channel, selection.program
            ]
            let isOfficialManual = entry.source == .officialManual
            return DevicePreset(
                id: "pa700-\(selection.bankMSB)-\(selection.bankLSB)-\(selection.program)",
                displayName: entry.effectiveName,
                bankMSB: selection.bankMSB,
                bankLSB: selection.bankLSB,
                program: selection.program,
                status: .draft,
                evidence: [
                    ProfileEvidence(
                        kind: isOfficialManual ? "official-manual" : "bulk-midi-capture",
                        firmware: catalog.firmware,
                        bytes: bytes,
                        note: isOfficialManual
                            ? "Imported from the official KORG PA700 v1.5 sound table; physical name and audio still require verification."
                            : "Captured passively with MIDI preset \(catalog.midiPreset); physical name and audio still require verification.",
                        capturedAt: formatter.string(from: entry.firstCapturedAt)
                    )
                ]
            )
        }
        return .init(
            schemaVersion: 1,
            sourceCatalogID: catalog.id,
            model: catalog.model,
            firmware: catalog.firmware,
            generatedAt: generatedAt,
            presets: presets
        )
    }

    public static func saveDraftExport(_ export: BatchSoundDraftExport, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(export).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
