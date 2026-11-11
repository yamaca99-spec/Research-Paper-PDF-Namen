import Foundation

/// Helpers for comparing titles and names with messy PDF text.
public enum TextTools {
    /// Lower-cased, accent-free, ligature-free words (letters and digits only).
    public static func tokens(_ text: String) -> [String] {
        let folded = text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
        var result: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// All letters and digits of the text concatenated, lower-cased (used for substring checks).
    public static func compact(_ text: String) -> String {
        tokens(text).joined()
    }

    /// Joins words that were hyphenated at a line break ("learn-\ning" -> "learning").
    public static func dehyphenate(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(\p{L})[-­‐]\s*\n\s*(\p{Ll})"#,
            with: "$1$2",
            options: .regularExpression
        )
    }

    /// Jaccard similarity of the word sets of two strings (0...1).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let sa = Set(tokens(a))
        let sb = Set(tokens(b))
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
    }

    /// Collapses all whitespace (including line breaks) into single spaces.
    public static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes HTML/MathML tags and decodes the most common entities (Crossref titles contain them).
    public static func stripMarkup(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
            "&apos;": "'", "&nbsp;": " ", "&#x27;": "'", "&ndash;": "–", "&mdash;": "—",
        ]
        for (entity, value) in entities {
            s = s.replacingOccurrences(of: entity, with: value)
        }
        return collapseWhitespace(s)
    }

    /// Turns an ALL-CAPS title into normal capitalisation; leaves other titles untouched.
    public static func fixShoutingCase(_ text: String) -> String {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 8 else { return text }
        let upper = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        guard Double(upper) / Double(letters.count) > 0.9 else { return text }
        let lower = text.lowercased()
        guard let first = lower.first else { return text }
        return String(first).uppercased() + lower.dropFirst()
    }
}

/// The searchable text of a PDF, used to verify that metadata found online belongs to this PDF.
public struct PageEvidence {
    public let tokenSet: Set<String>
    public let compactText: String
    public let tokenCount: Int

    public init(text: String) {
        let dehyphenated = TextTools.dehyphenate(text)
        let tokensA = TextTools.tokens(dehyphenated)
        let tokensB = TextTools.tokens(text)
        tokenSet = Set(tokensA).union(tokensB)
        compactText = tokensA.joined()
        tokenCount = tokensA.count
    }

    /// Scanned PDFs without (much) text cannot be used for verification.
    public var isSparse: Bool { tokenCount < 40 }

    /// Share of the title's words that occur in the PDF text (0...1).
    public func coverage(of title: String?) -> Double {
        guard let title = title else { return 0 }
        let words = TextTools.tokens(title)
        guard !words.isEmpty else { return 0 }
        let compactTitle = words.joined()
        if compactTitle.count >= 12, compactText.contains(compactTitle) { return 1 }
        let found = words.filter { tokenSet.contains($0) }.count
        return Double(found) / Double(words.count)
    }

    /// True if the (family) name occurs in the PDF text.
    public func contains(name: String) -> Bool {
        let words = TextTools.tokens(name)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { tokenSet.contains($0) }
    }
}
