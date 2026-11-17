import Foundation

/// How typed text is compared with place names, so a reader finds Øvre Dividal by typing
/// "ovre", Kujū by "kuju", Hawaiʻi by "hawaii" and シレトコ by しれとこ.
public enum SearchText {
    /// `text` folded for matching: case, accents and macrons, full- and half-width forms,
    /// and hiragana against katakana; the Nordic and Sámi letters that do not decompose
    /// spelled as a keyboard without them would type them; the ʻokina and apostrophes
    /// dropped; hyphens and dashes read as spaces, so "fuji hakone" finds Fuji-Hakone-Izu
    /// and "sor spitsbergen" Sør-Spitsbergen.
    ///
    /// Search folds every name on every keystroke, so plain ASCII — most names — takes a
    /// fast path, and the kana transform runs only on text that holds hiragana. The full
    /// path is about nine times slower.
    public static func fold(_ text: String) -> String {
        if text.utf8.allSatisfy({ $0 < 0x80 }) {
            var lower = text.lowercased()
            if lower.contains("'") {
                lower = lower.replacingOccurrences(of: "'", with: "")
            }
            return lower.contains("-") ? lower.replacingOccurrences(of: "-", with: " ") : lower
        }
        var folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if folded.unicodeScalars.contains(where: { (0x3040 ... 0x309F).contains($0.value) }) {
            folded = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        }
        var result = ""
        result.reserveCapacity(folded.count)
        for character in folded {
            if let spelled = spellings[character] {
                result += spelled
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Whether `text` holds `query`, both folded.
    public static func contains(_ text: String, _ query: String) -> Bool {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return needle.isEmpty || fold(text).contains(needle)
    }

    private static let spellings: [Character: String] = [
        "ø": "o", "æ": "ae", "œ": "oe", "đ": "d", "ð": "d", "ŋ": "n", "ŧ": "t",
        "-": " ", "‐": " ", "‑": " ", "–": " ", "—": " ",
        "þ": "th", "ß": "ss", "ł": "l",
        "ʻ": "", "’": "", "'": "",
    ]
}
