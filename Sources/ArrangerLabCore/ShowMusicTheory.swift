import Foundation

public enum ShowMusicTheory {
    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let pitchClasses: [String: Int] = [
        "C": 0, "B#": 0,
        "C#": 1, "Db": 1,
        "D": 2,
        "D#": 3, "Eb": 3,
        "E": 4, "Fb": 4,
        "E#": 5, "F": 5,
        "F#": 6, "Gb": 6,
        "G": 7,
        "G#": 8, "Ab": 8,
        "A": 9,
        "A#": 10, "Bb": 10,
        "B": 11, "Cb": 11
    ]

    public static func transposedKey(_ key: String, by semitones: Int) -> String? {
        guard let parsed = parseKey(key) else { return nil }
        return noteName(for: parsed.pitchClass + semitones, preferFlats: parsed.preferFlats) + parsed.suffix
    }

    public static func transposeChart(_ lines: [ShowChartLine], by semitones: Int, preferFlats: Bool? = nil) -> [ShowChartLine] {
        guard semitones != 0 else { return lines }
        return lines.map { line in
            guard line.kind == .chords else { return line }
            var updated = line
            updated.text = transposeChordLine(line.text, by: semitones, preferFlats: preferFlats)
            return updated
        }
    }

    public static func transposeChordLine(_ line: String, by semitones: Int, preferFlats: Bool? = nil) -> String {
        guard semitones != 0,
              let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9])([A-G])([#b]?)"#) else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, range: range).reversed()
        var output = line
        for match in matches {
            guard let rootRange = Range(match.range(at: 1), in: output),
                  let accidentalRange = Range(match.range(at: 2), in: output) else { continue }
            let note = String(output[rootRange]) + String(output[accidentalRange])
            guard let pitchClass = pitchClasses[note] else { continue }
            let useFlats = preferFlats ?? note.contains("b")
            let replacement = noteName(for: pitchClass + semitones, preferFlats: useFlats)
            guard let fullRange = Range(match.range(at: 0), in: output) else { continue }
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }

    public static func isChordLine(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return false }
        let chordCount = tokens.reduce(into: 0) { count, token in
            if isChordToken(String(token)) { count += 1 }
        }
        return Double(chordCount) / Double(tokens.count) >= 0.65
    }

    private static func parseKey(_ rawKey: String) -> (pitchClass: Int, suffix: String, preferFlats: Bool)? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^([A-G])([#b]?)(m?)$"#),
              let match = regex.firstMatch(in: key, range: NSRange(key.startIndex..<key.endIndex, in: key)),
              let rootRange = Range(match.range(at: 1), in: key),
              let accidentalRange = Range(match.range(at: 2), in: key),
              let suffixRange = Range(match.range(at: 3), in: key) else { return nil }
        let note = String(key[rootRange]) + String(key[accidentalRange])
        guard let pitchClass = pitchClasses[note] else { return nil }
        return (pitchClass, String(key[suffixRange]), note.contains("b"))
    }

    private static func noteName(for rawPitchClass: Int, preferFlats: Bool) -> String {
        let pitchClass = ((rawPitchClass % 12) + 12) % 12
        return (preferFlats ? flatNames : sharpNames)[pitchClass]
    }

    private static func isChordToken(_ rawToken: String) -> Bool {
        var token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "|,:;[]{}"))
        while token.hasPrefix("(") && token.hasSuffix(")") && token.count > 2 {
            token.removeFirst()
            token.removeLast()
        }
        guard let rootMatch = token.range(of: #"^[A-G](?:#|b)?"#, options: .regularExpression) else { return false }
        var remainder = String(token[rootMatch.upperBound...])
        if let bassRange = remainder.range(of: #"/[A-G](?:#|b)?$"#, options: .regularExpression) {
            remainder.removeSubrange(bassRange)
        }
        let recognizedWords = ["maj", "min", "dim", "aug", "sus", "add", "omit", "m", "M"]
        for word in recognizedWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.range(of: #"^[0-9()+°º#b/\-]*$"#, options: .regularExpression) != nil
    }
}
