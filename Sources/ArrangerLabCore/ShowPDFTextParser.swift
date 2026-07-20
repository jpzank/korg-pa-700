import Foundation

public enum ShowPDFTextParserError: LocalizedError {
    case noExtractableText(String)

    public var errorDescription: String? {
        switch self {
        case let .noExtractableText(name):
            return "\(name) não contém texto selecionável. Exporte-o com OCR antes de importar."
        }
    }
}

public enum ShowPDFTextParser {
    public static func makePreset(
        pageTexts: [String],
        sourceFileName: String,
        sourceFingerprint: String
    ) throws -> ShowPreset {
        let pageLines = pageTexts.map { pageText in
            pageText.components(separatedBy: .newlines)
                .map { normalizeWhitespace($0) }
                .filter { !$0.isEmpty }
        }
        let allLines = pageLines.flatMap { $0 }
        guard !allLines.isEmpty else {
            throw ShowPDFTextParserError.noExtractableText(sourceFileName)
        }

        let extractedKey = allLines.lazy.compactMap(extractKey).first ?? ""
        let fallback = URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent
        let title = detectedTitle(in: allLines, fallback: fallback)
        var chartLines: [ShowChartLine] = []
        for (pageIndex, lines) in pageLines.enumerated() {
            if pageIndex > 0, chartLines.last?.kind != .space {
                chartLines.append(.init(kind: .space, text: ""))
            }
            appendStructured(lines, title: title, to: &chartLines)
        }
        while chartLines.last?.kind == .space { chartLines.removeLast() }
        guard !chartLines.isEmpty else {
            throw ShowPDFTextParserError.noExtractableText(sourceFileName)
        }

        return ShowPreset(
            songTitle: title,
            songBookNumber: nil,
            originalKey: extractedKey,
            source: .init(
                catalogID: "external-pdf",
                catalogSongID: sourceFingerprint,
                documentName: sourceFileName,
                startPage: 1,
                endPage: max(1, pageTexts.count)
            ),
            chartLines: chartLines
        )
    }

    private static func appendStructured(_ lines: [String], title: String, to output: inout [ShowChartLine]) {
        for line in lines {
            if line.caseInsensitiveCompare(title) == .orderedSame || extractKey(line) != nil || line.allSatisfy(\.isNumber) {
                continue
            }
            if let section = splitSection(line) {
                appendSpaceIfNeeded(to: &output)
                output.append(.init(kind: .section, text: section.label))
                if !section.remainder.isEmpty {
                    output.append(.init(
                        kind: ShowMusicTheory.isChordLine(section.remainder) ? .chords : .lyrics,
                        text: section.remainder
                    ))
                }
            } else if isNamedSection(line) {
                appendSpaceIfNeeded(to: &output)
                output.append(.init(kind: .section, text: line))
            } else {
                output.append(.init(
                    kind: ShowMusicTheory.isChordLine(line) ? .chords : .lyrics,
                    text: line
                ))
            }
        }
    }

    private static func detectedTitle(in lines: [String], fallback: String) -> String {
        if let candidate = lines.first(where: { line in
            line.count <= 100
                && extractKey(line) == nil
                && splitSection(line) == nil
                && !isNamedSection(line)
                && !ShowMusicTheory.isChordLine(line)
        }) {
            return candidate
        }
        return normalizeFilename(fallback)
    }

    private static func extractKey(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:key|tom|tonalidade)\s*:\s*([A-G](?:#|b)?m?)(?=\s|$)"#
        ), let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    private static func splitSection(_ line: String) -> (label: String, remainder: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\[[^]]+\])\s*(.*)$"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let labelRange = Range(match.range(at: 1), in: line),
              let remainderRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[labelRange]), String(line[remainderRange]))
    }

    private static func isNamedSection(_ line: String) -> Bool {
        let normalized = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        let names = [
            "intro", "introducao", "primeira parte", "segunda parte", "terceira parte",
            "pre-refrao", "refrao", "ponte", "solo", "interludio", "final", "refrao final", "tab"
        ]
        return names.contains(normalized)
    }

    private static func appendSpaceIfNeeded(to output: inout [ShowChartLine]) {
        if !output.isEmpty, output.last?.kind != .space {
            output.append(.init(kind: .space, text: ""))
        }
    }

    private static func normalizeWhitespace(_ line: String) -> String {
        line.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeFilename(_ filename: String) -> String {
        filename.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
