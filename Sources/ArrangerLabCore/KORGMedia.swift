import Foundation

public enum KORGMediaResourceKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case mid = "MID"
    case jbx = "JBX"
    case kmp = "KMP"
    case pad = "PAD"
    case sbd = "SBD"
    case sty = "STY"
    case prf = "PRF"
    case voc = "VOC"
    case gtr = "GTR"
    case pcg = "PCG"
    case tbl = "TBL"
    case xml = "XML"
    case flac = "FLAC"
    case md5 = "MD5"
    case bkp = "BKP"
    case kao = "KAO"
    case unknown = "unknown"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mid: return "MIDI"
        case .jbx: return "JBX"
        case .kmp: return "Korg Multisample"
        case .pad: return "Pad"
        case .sbd: return "SongBook"
        case .sty: return "Style"
        case .prf: return "Keyboard Set"
        case .voc: return "Voice Preset"
        case .gtr: return "Guitar Preset"
        case .pcg: return "Sound / PCG"
        case .tbl: return "Resource Table"
        case .xml: return "XML"
        case .flac: return "FLAC"
        case .md5: return "MD5"
        case .bkp: return "Backup"
        case .kao: return "KAOSS Preset"
        case .unknown: return "Desconhecido"
        }
    }

    public var isOpaque: Bool {
        switch self {
        case .jbx, .kmp, .pad, .sbd, .sty, .prf, .voc, .gtr, .pcg, .tbl, .bkp, .kao:
            return true
        case .mid, .xml, .flac, .md5, .unknown:
            return false
        }
    }

    public init(fileExtension: String) {
        let normalized = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .uppercased()
        self = Self.allCases.first(where: { $0 != .unknown && $0.rawValue == normalized }) ?? .unknown
    }
}

public enum KORGMediaItemStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case recognized
    case opaque
    case unknown
    case unreadable
    case skipped

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .recognized: return "Reconhecido"
        case .opaque: return "Proprietário"
        case .unknown: return "Desconhecido"
        case .unreadable: return "Ilegível"
        case .skipped: return "Ignorado"
        }
    }
}

public enum KORGMediaContainerKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case set
    case resource

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .set: return "Pasta .SET"
        case .resource: return "Recurso avulso"
        }
    }
}

public struct KORGMediaItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String { relativePath }

    public let relativePath: String
    public let fileExtension: String
    public let resourceKind: KORGMediaResourceKind
    public let sizeBytes: Int64
    public let functionalDirectory: String?
    public let status: KORGMediaItemStatus
    public let warnings: [String]

    public init(
        relativePath: String,
        fileExtension: String,
        resourceKind: KORGMediaResourceKind,
        sizeBytes: Int64,
        functionalDirectory: String?,
        status: KORGMediaItemStatus,
        warnings: [String] = []
    ) {
        self.relativePath = relativePath.precomposedStringWithCanonicalMapping
        self.fileExtension = fileExtension.uppercased()
        self.resourceKind = resourceKind
        self.sizeBytes = max(0, sizeBytes)
        self.functionalDirectory = functionalDirectory
        self.status = status
        self.warnings = Self.sortedUnique(warnings)
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted(by: KORGMediaOrdering.less)
    }
}

public struct KORGMediaSummary: Codable, Equatable, Sendable {
    public let itemCount: Int
    public let totalBytes: Int64
    public let countsByKind: [String: Int]

    public init(itemCount: Int, totalBytes: Int64, countsByKind: [String: Int]) {
        self.itemCount = itemCount
        self.totalBytes = max(0, totalBytes)
        self.countsByKind = countsByKind
    }
}

public struct KORGMediaInventory: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceName: String
    public let containerKind: KORGMediaContainerKind
    public let summary: KORGMediaSummary
    public let items: [KORGMediaItem]
    public let warnings: [String]

    public init(
        schemaVersion: Int = 1,
        sourceName: String,
        containerKind: KORGMediaContainerKind,
        items: [KORGMediaItem],
        warnings: [String] = []
    ) {
        let orderedItems = items.sorted {
            KORGMediaOrdering.less($0.relativePath, $1.relativePath)
        }
        var countsByKind: [String: Int] = [:]
        for item in orderedItems {
            countsByKind[item.resourceKind.rawValue, default: 0] += 1
        }

        self.schemaVersion = schemaVersion
        self.sourceName = sourceName.precomposedStringWithCanonicalMapping
        self.containerKind = containerKind
        self.summary = KORGMediaSummary(
            itemCount: orderedItems.count,
            totalBytes: orderedItems.reduce(0) { $0 + $1.sizeBytes },
            countsByKind: countsByKind
        )
        self.items = orderedItems
        self.warnings = Array(Set(warnings)).sorted(by: KORGMediaOrdering.less)
    }

    public func jsonData() throws -> Data {
        guard schemaVersion == 1 else {
            throw KORGMediaScannerError.unsupportedInventorySchema(schemaVersion)
        }
        let canonical = KORGMediaInventory(
            schemaVersion: schemaVersion,
            sourceName: sourceName,
            containerKind: containerKind,
            items: items,
            warnings: warnings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(canonical)
    }

    public func jsonString() throws -> String {
        guard let result = String(data: try jsonData(), encoding: .utf8) else {
            throw KORGMediaScannerError.couldNotEncodeReport
        }
        return result
    }
}

public struct KORGMediaScanProgress: Equatable, Sendable {
    public let discoveredItemCount: Int
    public let discoveredBytes: Int64
    public let currentRelativePath: String?

    public init(discoveredItemCount: Int, discoveredBytes: Int64, currentRelativePath: String?) {
        self.discoveredItemCount = discoveredItemCount
        self.discoveredBytes = discoveredBytes
        self.currentRelativePath = currentRelativePath
    }
}

public enum KORGMediaScannerError: LocalizedError, Equatable, Sendable {
    case sourceNotFound
    case sourceMustBeFileURL
    case symbolicLinkSourceNotAllowed
    case expectedSETDirectory
    case unsupportedDirectory
    case unsupportedStandaloneResource(String)
    case standaloneBackupNotSupported
    case unreadableSource
    case unsupportedInventorySchema(Int)
    case couldNotEncodeReport

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "A origem selecionada não existe."
        case .sourceMustBeFileURL:
            return "Selecione uma pasta ou arquivo local."
        case .symbolicLinkSourceNotAllowed:
            return "Links simbólicos não podem ser usados como origem da inspeção."
        case .expectedSETDirectory:
            return "Um item com extensão .SET precisa ser uma pasta."
        case .unsupportedDirectory:
            return "Selecione uma pasta com extensão .SET."
        case let .unsupportedStandaloneResource(fileExtension):
            let suffix = fileExtension.isEmpty ? "sem extensão" : ".\(fileExtension.uppercased())"
            return "O recurso avulso \(suffix) não é suportado pelo inspetor."
        case .standaloneBackupNotSupported:
            return "Arquivos .BKP avulsos não são aceitos; um BKP dentro de uma pasta .SET será apenas inventariado."
        case .unreadableSource:
            return "Não foi possível ler os metadados da origem selecionada."
        case let .unsupportedInventorySchema(version):
            return "A versão \(version) do relatório de mídia KORG não é suportada."
        case .couldNotEncodeReport:
            return "Não foi possível gerar o relatório JSON de mídia KORG."
        }
    }
}

public struct KORGMediaScanner: Sendable {
    public init() {}

    public func scan(
        at sourceURL: URL,
        progress: (@Sendable (KORGMediaScanProgress) -> Void)? = nil
    ) async throws -> KORGMediaInventory {
        try Task.checkCancellation()
        guard sourceURL.isFileURL else {
            throw KORGMediaScannerError.sourceMustBeFileURL
        }

        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let containerKind = try classifySource(sourceURL)
        try Task.checkCancellation()

        switch containerKind {
        case .resource:
            let item = makeItem(
                at: sourceURL,
                relativePath: sourceURL.lastPathComponent,
                containerKind: .resource
            )
            progress?(
                KORGMediaScanProgress(
                    discoveredItemCount: 1,
                    discoveredBytes: item.sizeBytes,
                    currentRelativePath: item.relativePath
                )
            )
            try Task.checkCancellation()
            return KORGMediaInventory(
                sourceName: sourceURL.lastPathComponent,
                containerKind: .resource,
                items: [item]
            )

        case .set:
            return try await scanSETDirectory(at: sourceURL, progress: progress)
        }
    }

    private func classifySource(_ sourceURL: URL) throws -> KORGMediaContainerKind {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw KORGMediaScannerError.sourceNotFound
        }

        let linkValues: URLResourceValues
        do {
            linkValues = try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        } catch {
            throw KORGMediaScannerError.unreadableSource
        }
        guard linkValues.isSymbolicLink != true else {
            throw KORGMediaScannerError.symbolicLinkSourceNotAllowed
        }

        let typeValues: URLResourceValues
        do {
            typeValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        } catch {
            throw KORGMediaScannerError.unreadableSource
        }

        let fileExtension = sourceURL.pathExtension
        let isSET = fileExtension.caseInsensitiveCompare("set") == .orderedSame
        if typeValues.isDirectory == true {
            guard isSET else { throw KORGMediaScannerError.unsupportedDirectory }
            return .set
        }

        if isSET {
            throw KORGMediaScannerError.expectedSETDirectory
        }
        guard typeValues.isRegularFile == true else {
            throw KORGMediaScannerError.unreadableSource
        }

        let resourceKind = KORGMediaResourceKind(fileExtension: fileExtension)
        if resourceKind == .bkp {
            throw KORGMediaScannerError.standaloneBackupNotSupported
        }
        guard resourceKind != .unknown else {
            throw KORGMediaScannerError.unsupportedStandaloneResource(fileExtension)
        }
        return .resource
    }

    private func scanSETDirectory(
        at rootURL: URL,
        progress: (@Sendable (KORGMediaScanProgress) -> Void)?
    ) async throws -> KORGMediaInventory {
        let fileManager = FileManager.default
        var enumerationWarnings: [String] = []
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { failedURL, error in
                let relativePath = Self.relativePath(of: failedURL, below: rootURL)
                    ?? failedURL.lastPathComponent
                let errorCode = (error as NSError).code
                enumerationWarnings.append(
                    "Não foi possível enumerar \(relativePath) (erro do sistema de arquivos \(errorCode))."
                )
                return true
            }
        ) else {
            throw KORGMediaScannerError.unreadableSource
        }

        var items: [KORGMediaItem] = []
        var totalBytes: Int64 = 0
        while let childURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard let relativePath = Self.relativePath(of: childURL, below: rootURL) else {
                enumerationWarnings.append("Um item fora da pasta .SET foi ignorado.")
                if let values = try? childURL.resourceValues(forKeys: Set(keys)),
                   values.isDirectory == true,
                   values.isSymbolicLink != true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let name = childURL.lastPathComponent
            if name == ".DS_Store" || name.hasPrefix("._") {
                if let values = try? childURL.resourceValues(forKeys: Set(keys)),
                   values.isDirectory == true,
                   values.isSymbolicLink != true {
                    enumerator.skipDescendants()
                }
                continue
            }

            do {
                let values = try childURL.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    let item = makeSkippedSymbolicLink(
                        at: childURL,
                        relativePath: relativePath
                    )
                    items.append(item)
                    progress?(
                        KORGMediaScanProgress(
                            discoveredItemCount: items.count,
                            discoveredBytes: totalBytes,
                            currentRelativePath: item.relativePath
                        )
                    )
                    continue
                }
                if values.isDirectory == true {
                    continue
                }
            } catch {
                let item = makeUnreadableItem(
                    at: childURL,
                    relativePath: relativePath,
                    error: error
                )
                items.append(item)
                progress?(
                    KORGMediaScanProgress(
                        discoveredItemCount: items.count,
                        discoveredBytes: totalBytes,
                        currentRelativePath: item.relativePath
                    )
                )
                continue
            }

            let item = makeItem(
                at: childURL,
                relativePath: relativePath,
                containerKind: .set
            )
            items.append(item)
            totalBytes += item.sizeBytes
            progress?(
                KORGMediaScanProgress(
                    discoveredItemCount: items.count,
                    discoveredBytes: totalBytes,
                    currentRelativePath: item.relativePath
                )
            )

            if items.count.isMultiple(of: 128) {
                await Task.yield()
            }
        }

        try Task.checkCancellation()
        return KORGMediaInventory(
            sourceName: rootURL.lastPathComponent,
            containerKind: .set,
            items: items,
            warnings: enumerationWarnings
        )
    }

    private func makeItem(
        at url: URL,
        relativePath: String,
        containerKind: KORGMediaContainerKind
    ) -> KORGMediaItem {
        let fileExtension = url.pathExtension.uppercased()
        let resourceKind = KORGMediaResourceKind(fileExtension: fileExtension)
        let functionalDirectory = Self.functionalDirectory(for: relativePath)
        var warnings: [String] = []

        if containerKind == .set,
           let expectedDirectories = Self.expectedDirectories[resourceKind],
           !expectedDirectories.contains(functionalDirectory ?? "") {
            let expected = expectedDirectories.sorted(by: KORGMediaOrdering.less).joined(separator: " ou ")
            warnings.append(
                "\(relativePath) está fora do diretório funcional esperado (\(expected))."
            )
        }

        do {
            let values = try url.resourceValues(
                forKeys: [.fileSizeKey, .isReadableKey, .isRegularFileKey]
            )
            guard values.isRegularFile == true else {
                warnings.append("\(relativePath) não é um arquivo regular e foi ignorado.")
                return KORGMediaItem(
                    relativePath: relativePath,
                    fileExtension: fileExtension,
                    resourceKind: resourceKind,
                    sizeBytes: 0,
                    functionalDirectory: functionalDirectory,
                    status: .skipped,
                    warnings: warnings
                )
            }
            guard values.isReadable != false else {
                warnings.append("Os metadados de \(relativePath) indicam que o arquivo não está legível.")
                return KORGMediaItem(
                    relativePath: relativePath,
                    fileExtension: fileExtension,
                    resourceKind: resourceKind,
                    sizeBytes: Int64(values.fileSize ?? 0),
                    functionalDirectory: functionalDirectory,
                    status: .unreadable,
                    warnings: warnings
                )
            }

            let status: KORGMediaItemStatus
            if resourceKind == .unknown {
                status = .unknown
            } else if resourceKind.isOpaque {
                status = .opaque
            } else {
                status = .recognized
            }
            return KORGMediaItem(
                relativePath: relativePath,
                fileExtension: fileExtension,
                resourceKind: resourceKind,
                sizeBytes: Int64(values.fileSize ?? 0),
                functionalDirectory: functionalDirectory,
                status: status,
                warnings: warnings
            )
        } catch {
            warnings.append(Self.metadataError(relativePath: relativePath, error: error))
            return KORGMediaItem(
                relativePath: relativePath,
                fileExtension: fileExtension,
                resourceKind: resourceKind,
                sizeBytes: 0,
                functionalDirectory: functionalDirectory,
                status: .unreadable,
                warnings: warnings
            )
        }
    }

    private func makeSkippedSymbolicLink(at url: URL, relativePath: String) -> KORGMediaItem {
        KORGMediaItem(
            relativePath: relativePath,
            fileExtension: url.pathExtension,
            resourceKind: KORGMediaResourceKind(fileExtension: url.pathExtension),
            sizeBytes: 0,
            functionalDirectory: Self.functionalDirectory(for: relativePath),
            status: .skipped,
            warnings: ["O link simbólico \(relativePath) não foi seguido."]
        )
    }

    private func makeUnreadableItem(
        at url: URL,
        relativePath: String,
        error: Error
    ) -> KORGMediaItem {
        KORGMediaItem(
            relativePath: relativePath,
            fileExtension: url.pathExtension,
            resourceKind: KORGMediaResourceKind(fileExtension: url.pathExtension),
            sizeBytes: 0,
            functionalDirectory: Self.functionalDirectory(for: relativePath),
            status: .unreadable,
            warnings: [Self.metadataError(relativePath: relativePath, error: error)]
        )
    }

    private static func metadataError(relativePath: String, error: Error) -> String {
        "Não foi possível ler os metadados de \(relativePath) (erro do sistema de arquivos \((error as NSError).code))."
    }

    private static func relativePath(of childURL: URL, below rootURL: URL) -> String? {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let childComponents = childURL.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              childComponents.starts(with: rootComponents)
        else {
            return nil
        }
        return childComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
            .precomposedStringWithCanonicalMapping
    }

    private static func functionalDirectory(for relativePath: String) -> String? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.uppercased() }
        guard let first = components.first else { return nil }

        if components.count == 2,
           first == "SONGBOOK",
           components[1] == "SONGDB.SBD" {
            return "SONGBOOK/SONGDB.SBD"
        }
        if components.count >= 2,
           first == "SYSTEM",
           components[1] == "RESOURCEBROWSER" {
            return "SYSTEM/RESOURCEBROWSER"
        }
        return canonicalTopLevelDirectories.contains(first) ? first : nil
    }

    private static let canonicalTopLevelDirectories: Set<String> = [
        "GLOBAL",
        "GUITARPRESET",
        "KEYBOARDSET",
        "MULTISMP",
        "PAD",
        "SONGBOOK",
        "SOUND",
        "STYLE",
        "SYSTEM",
        "VOICEPRESET",
        "KAOSSPRESET"
    ]

    private static let expectedDirectories: [KORGMediaResourceKind: Set<String>] = [
        .kmp: ["MULTISMP"],
        .pad: ["PAD"],
        .sbd: ["SONGBOOK", "SONGBOOK/SONGDB.SBD"],
        .sty: ["STYLE"],
        .prf: ["KEYBOARDSET"],
        .voc: ["VOICEPRESET"],
        .gtr: ["GUITARPRESET"],
        .pcg: ["SOUND"],
        .tbl: ["SYSTEM/RESOURCEBROWSER"],
        .kao: ["KAOSSPRESET"]
    ]
}

private enum KORGMediaOrdering {
    static func less(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedLHS = lhs.precomposedStringWithCanonicalMapping.lowercased()
        let normalizedRHS = rhs.precomposedStringWithCanonicalMapping.lowercased()
        if normalizedLHS == normalizedRHS {
            return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
        return normalizedLHS.utf8.lexicographicallyPrecedes(normalizedRHS.utf8)
    }
}
