import Foundation

public struct MusicalIntentMatch: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct MusicalIntentTranslation: Equatable, Sendable {
    public let keyboardSet: MusicalIntentMatch?
    public let style: MusicalIntentMatch?
    public let variation: Int?

    public init(keyboardSet: MusicalIntentMatch? = nil, style: MusicalIntentMatch? = nil, variation: Int? = nil) {
        self.keyboardSet = keyboardSet
        self.style = style
        self.variation = variation
    }

    public var isEmpty: Bool {
        keyboardSet == nil && style == nil && variation == nil
    }
}

public enum MusicalIntentTranslator {
    public static func translate(
        _ command: String,
        keyboardSets: [KeyboardSetLibraryEntry],
        styles: [ArrangerStyle]
    ) -> MusicalIntentTranslation {
        let normalizedCommand = normalized(command)
        guard !normalizedCommand.isEmpty else { return .init() }

        let keyboardSet = longestMatch(
            in: normalizedCommand,
            candidates: keyboardSets.map { ($0.id, $0.displayName) }
        )
        let style = longestMatch(
            in: normalizedCommand,
            candidates: styles.map { ($0.id, $0.displayName) }
        )

        return .init(
            keyboardSet: keyboardSet,
            style: style,
            variation: variation(in: normalizedCommand)
        )
    }

    private static func longestMatch(
        in command: String,
        candidates: [(id: String, displayName: String)]
    ) -> MusicalIntentMatch? {
        let paddedCommand = " \(command) "
        return candidates
            .map { candidate in
                (candidate: candidate, normalizedName: normalized(candidate.displayName))
            }
            .filter { !$0.normalizedName.isEmpty && paddedCommand.contains(" \($0.normalizedName) ") }
            .sorted(by: {
                if $0.normalizedName.count != $1.normalizedName.count {
                    return $0.normalizedName.count > $1.normalizedName.count
                }
                return $0.candidate.displayName.localizedStandardCompare($1.candidate.displayName) == .orderedAscending
            })
            .first
            .map { .init(id: $0.candidate.id, displayName: $0.candidate.displayName) }
    }

    private static func variation(in command: String) -> Int? {
        let patterns = [
            #"\b(?:variacao|variation|var)\s*([1-4])\b"#,
            #"\bv\s*([1-4])\b"#
        ]
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: command, range: range),
                  let captureRange = Range(match.range(at: 1), in: command),
                  let result = Int(command[captureRange]) else { continue }
            return result
        }

        let words = ["um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4]
        for (word, number) in words where command.contains(" variacao \(word) ") || command.hasSuffix(" variacao \(word)") {
            return number
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
        let words = folded.unicodeScalars.split { scalar in
            !CharacterSet.alphanumerics.contains(scalar)
        }
        return words.map(String.init).joined(separator: " ")
    }
}
