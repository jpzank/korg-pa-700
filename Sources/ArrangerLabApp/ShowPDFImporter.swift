import ArrangerLabCore
import CryptoKit
import Foundation
import PDFKit

enum ShowPDFImportError: LocalizedError {
    case cannotOpen(String)

    var errorDescription: String? {
        switch self {
        case let .cannotOpen(name): return "Não foi possível abrir \(name)."
        }
    }
}

enum ShowPDFImporter {
    static func extractPreset(from url: URL) throws -> ShowPreset {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw ShowPDFImportError.cannotOpen(url.lastPathComponent)
        }

        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let pageTexts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        return try ShowPDFTextParser.makePreset(
            pageTexts: pageTexts,
            sourceFileName: url.lastPathComponent,
            sourceFingerprint: fingerprint
        )
    }
}
