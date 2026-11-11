import Foundation

/// Offline guesses of title, authors and year from the PDF itself.
public enum TextHeuristics {
    public struct DetectedTitle: Equatable {
        public var title: String
        /// Index (in the input lines) of the last line belonging to the title.
        public var lastLineIndex: Int
        public var fontSize: Double
    }

    // MARK: - Title

    private static let rejectedFragments = [
        "arxiv:", "doi:", "doi.org", "http", "www.", "©", "@", "issn", "isbn",
        "journal homepage", "contents lists available", "sciencedirect", "creative commons",
        "downloaded from", "all rights reserved",
    ]

    private static let rejectedPrefixes = [
        "received", "accepted", "published", "available online", "citation", "vol.", "volume ",
        "proceedings", "journal of", "copyright", "to cite", "cite this", "editor", "correspondence",
    ]

    private static let rejectedHeadings: Set<String> = [
        "abstract", "article", "research article", "original article", "review", "review article",
        "letter", "letters", "research", "open access", "original research", "research paper",
        "short communication", "technical report", "preprint", "article info", "articleinfo",
        "keywords", "introduction", "article history", "highlights", "full paper", "communication",
        "brief report", "perspective", "commentary", "editorial", "report", "articles",
    ]

    static func isTitleCandidate(_ text: String) -> Bool {
        let lower = text.lowercased()
        if rejectedFragments.contains(where: { lower.contains($0) }) { return false }
        if rejectedPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        let bare = lower.trimmingCharacters(in: CharacterSet.letters.inverted)
        if rejectedHeadings.contains(bare) { return false }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters >= 2
    }

    static func joinLines(_ parts: [String]) -> String {
        var result = ""
        for part in parts {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if result.isEmpty {
                result = piece
            } else if result.hasSuffix("-"), let first = piece.unicodeScalars.first,
                      CharacterSet.lowercaseLetters.contains(first) {
                result.removeLast()
                result += piece
            } else {
                result += " " + piece
            }
        }
        return result
    }

    static func cleanTitle(_ title: String) -> String {
        var t = TextTools.collapseWhitespace(title)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "*∗†‡§¶ ,;"))
        return t
    }

    static func isPlausibleTitle(_ title: String) -> Bool {
        let words = title.split(separator: " ")
        guard title.count >= 10, title.count <= 350, words.count >= 2 else { return false }
        let letters = title.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return Double(letters) / Double(title.count) >= 0.6
    }

    /// The body text font size (the size with the most characters).
    static func bodyFontSize(_ lines: [TextLine]) -> Double {
        var weight: [Double: Int] = [:]
        for line in lines {
            weight[(line.fontSize * 2).rounded() / 2, default: 0] += line.text.count
        }
        return weight.max { $0.value < $1.value }?.key ?? 0
    }

    /// Detects the title as the largest text in the upper part of the first page.
    public static func detectTitle(lines: [TextLine]) -> DetectedTitle? {
        guard !lines.isEmpty else { return nil }
        let body = bodyFontSize(lines)

        let candidateIndices = lines.indices.filter { i in
            lines[i].top <= 0.65 && isTitleCandidate(lines[i].text)
        }
        let sizes = Set(candidateIndices.map { (lines[$0].fontSize * 2).rounded() / 2 })
            .filter { $0 >= body * 1.12 }
            .sorted(by: >)

        for size in sizes.prefix(5) {
            let tolerance = max(0.6, size * 0.04)
            var index = 0
            while index < lines.count {
                guard abs(lines[index].fontSize - size) <= tolerance,
                      lines[index].top <= 0.65,
                      isTitleCandidate(lines[index].text) else {
                    index += 1
                    continue
                }
                // Collect the run of consecutive lines with (about) this size.
                var parts: [String] = []
                var last = index
                var j = index
                while j < lines.count,
                      abs(lines[j].fontSize - size) <= tolerance,
                      isTitleCandidate(lines[j].text) || parts.isEmpty {
                    parts.append(lines[j].text)
                    last = j
                    j += 1
                    if parts.count >= 6 { break }
                }
                let title = cleanTitle(joinLines(parts))
                if isPlausibleTitle(title) {
                    return DetectedTitle(title: title, lastLineIndex: last, fontSize: size)
                }
                index = j
            }
        }
        return nil
    }

    /// Whether the title stored in the PDF's document info looks like a real paper title.
    public static func isPlausibleMetadataTitle(_ raw: String?) -> Bool {
        guard let raw = raw else { return false }
        let title = TextTools.collapseWhitespace(raw)
        let lower = title.lowercased()
        let junk = [
            "microsoft word", "untitled", ".doc", ".pdf", ".tex", ".dvi", "pii:", "pii ",
            "doi:", "http", "\\", "layout", "template", "manuscript", "title", "slides",
        ]
        if junk.contains(where: { lower.contains($0) }) { return false }
        if lower.hasPrefix("doi") || lower.hasPrefix("10.") { return false }
        if title.range(of: #"^[\w\-]+\.(indd|qxd|fm|p65)$"#, options: .regularExpression) != nil { return false }
        return isPlausibleTitle(title)
    }

    // MARK: - Authors

    private static let affiliationWords = [
        "university", "universität", "universitat", "université", "universidad", "institut",
        "department", "dept", "school", "college", "laborator", "center", "centre", "inc.",
        "corp", "gmbh", "abstract", "email", "e-mail", "@", "http", "received", "keywords",
        "journal", "vol.", "©", "faculty", "hospital", "research", "academy", "group", "ltd",
        "foundation", "national", "google", "microsoft", "meta ", "openai", "deepmind",
    ]

    private static let nameWordRegex = try! NSRegularExpression(
        pattern: #"^(?:\p{Lu}[\p{L}'’\-]*\.?|\p{Lu}\.(?:-?\p{Lu}\.)*|(?:van|von|der|den|de|del|della|di|da|du|la|le|ter|ten|zu))$"#
    )

    static func isNameWord(_ word: String) -> Bool {
        let range = NSRange(word.startIndex..<word.endIndex, in: word)
        return nameWordRegex.firstMatch(in: word, options: [], range: range) != nil
    }

    /// Parses one author segment like "Jane A. Doe" into an author, if it looks like a name.
    static func parseNameSegment(_ segment: String) -> Author? {
        let cleaned = segment
            .replacingOccurrences(of: #"[0-9*∗†‡§¶#,]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Single lower-case letters are affiliation markers ("Anna Müller a,b").
        let words = cleaned.split(separator: " ").map(String.init).filter {
            !($0.count == 1 && $0 == $0.lowercased())
        }
        guard (2...5).contains(words.count), words.allSatisfy(isNameWord) else { return nil }
        guard let author = Author.parse(fullName: words.joined(separator: " ")) else { return nil }
        // The family name must not be an initial.
        guard author.family.count >= 2, !author.family.hasSuffix(".") else { return nil }
        return author
    }

    /// Splits a byline into individual name segments.
    static func splitByline(_ line: String) -> [String] {
        var normalized = line
        for separator in [" and ", " & ", " und ", ";", "·", "•", "  ", "\t"] {
            normalized = normalized.replacingOccurrences(of: separator, with: ",")
        }
        // Footnote markers between names ("Doe1, Smith2" / "Vaswani∗ Shazeer∗") act as separators too.
        normalized = normalized.replacingOccurrences(
            of: #"(?<=\p{L})(?:[0-9*∗†‡§¶]+)\s+(?=\p{Lu})"#, with: ",", options: .regularExpression
        )
        return normalized.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    /// Guesses the authors from the lines directly below the title.
    public static func authorsFromLines(_ lines: [TextLine], after title: DetectedTitle?) -> [Author] {
        guard let title = title else { return [] }
        var start = title.lastLineIndex + 1
        var inspected = 0
        while start < lines.count, inspected < 4 {
            let line = lines[start]
            start += 1
            inspected += 1
            let lower = line.text.lowercased()
            if affiliationWords.contains(where: { lower.contains($0) }) { break }
            if line.fontSize > title.fontSize { continue }
            let authors = splitByline(line.text).compactMap(parseNameSegment)
            if !authors.isEmpty { return authors }
        }
        return []
    }

    /// Parses the author field of the PDF document info ("Doe, J.; Smith, A." or "Jane Doe and John Smith").
    public static func authorsFromMetadata(_ raw: String?) -> [Author] {
        guard let raw = raw else { return [] }
        let value = TextTools.collapseWhitespace(raw)
        let lower = value.lowercased()
        let junkWords: Set<String> = [
            "admin", "administrator", "user", "owner", "unknown", "author", "authors", "elsevier",
            "springer", "ieee", "wiley", "latex", "tex", "microsoft", "windows", "pdf", "acrobat",
            "word", "editor", "publisher", "copyright", "ltd", "inc", "gmbh", "press", "journal",
            "society", "acm", "default", "anonymous", "staff", "office",
        ]
        if value.count < 3 { return [] }
        if ["@", "http", "©"].contains(where: { lower.contains($0) }) { return [] }
        if TextTools.tokens(value).contains(where: { junkWords.contains($0) }) { return [] }
        if value.rangeOfCharacter(from: .letters) == nil { return [] }

        var segments: [String]
        if value.contains(";") {
            segments = value.components(separatedBy: ";")
        } else if lower.contains(" and ") || value.contains("&") || lower.contains(" und ") {
            segments = value
                .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
                .replacingOccurrences(of: " und ", with: ",", options: .caseInsensitive)
                .replacingOccurrences(of: "&", with: ",")
                .components(separatedBy: ",")
        } else if value.contains(",") {
            let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            // "Doe, Jane" (one author) vs. "Jane Doe, John Smith" (list)
            let multiWord = parts.filter { $0.split(separator: " ").count >= 2 }.count
            segments = multiWord == parts.count ? parts : [value]
        } else {
            segments = [value]
        }
        return segments
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(Author.parse(fullName:))
            .filter { $0.family.count >= 2 && !$0.family.hasSuffix(".") }
    }

    // MARK: - Year

    public static func isPlausibleYear(_ year: Int, now: Date = Date()) -> Bool {
        let current = Calendar(identifier: .gregorian).component(.year, from: now)
        return year >= 1900 && year <= current + 1
    }

    private static func firstYear(matching pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            guard let r = Range(match.range(at: 1), in: text), let year = Int(text[r]) else { continue }
            if isPlausibleYear(year) { return String(year) }
        }
        return nil
    }

    /// Estimates the publication year from the text (copyright line, publication dates, arXiv id).
    public static func detectYear(text: String, arxivID: String?, creationYear: String?) -> String? {
        let patterns = [
            #"(?:©|\(c\)|copyright)[^\n]{0,80}?\b((?:19|20)\d{2})\b"#,
            #"published(?: online)?\s*:?[^\n]{0,40}?\b((?:19|20)\d{2})\b"#,
            #"accepted\s*:?[^\n]{0,40}?\b((?:19|20)\d{2})\b"#,
            #"available online\s*:?[^\n]{0,40}?\b((?:19|20)\d{2})\b"#,
            #"received\s*:?[^\n]{0,40}?\b((?:19|20)\d{2})\b"#,
        ]
        for pattern in patterns {
            if let year = firstYear(matching: pattern, in: text) { return year }
        }
        if let id = arxivID, let year = IdentifierExtractor.year(fromArxivID: id) { return year }
        if let created = creationYear, let year = Int(created), isPlausibleYear(year) { return created }
        return nil
    }
}
