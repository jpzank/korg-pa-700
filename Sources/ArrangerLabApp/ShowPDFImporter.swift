import ArrangerLabCore
import CryptoKit
import Foundation
import PDFKit

enum ShowPDFImportError: LocalizedError {
    case cannotOpen(String)
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case let .cannotOpen(name): return "Não foi possível abrir \(name)."
        case let .unsupportedFile(name): return "\(name) não é um arquivo PDF regular."
        }
    }
}

enum ShowPDFImporter {
    static func extractPreset(
        from url: URL,
        limits: ShowDocumentImportLimits = .communityDefault
    ) async throws -> ShowPreset {
        try await Task.detached(priority: .userInitiated) {
            try extractPresetSynchronously(from: url, limits: limits)
        }.value
    }

    private static func extractPresetSynchronously(
        from url: URL,
        limits: ShowDocumentImportLimits
    ) throws -> ShowPreset {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else {
            throw ShowPDFImportError.unsupportedFile(url.lastPathComponent)
        }
        if let fileSize = values.fileSize {
            try limits.validate(fileBytes: fileSize)
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try limits.validate(fileBytes: data.count)
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw ShowPDFImportError.cannotOpen(url.lastPathComponent)
        }
        try limits.validate(pageCount: document.pageCount)

        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)
        var extractedTextBytes = 0
        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            let text = document.page(at: pageIndex)?.string ?? ""
            extractedTextBytes += text.utf8.count
            try limits.validate(extractedTextBytes: extractedTextBytes)
            pageTexts.append(text)
        }
        return try ShowPDFTextParser.makePreset(
            pageTexts: pageTexts,
            sourceFileName: url.lastPathComponent,
            sourceFingerprint: fingerprint
        )
    }
}
