import Foundation

/// A single author of a paper.
public struct Author: Equatable, Hashable, Sendable {
    public var family: String
    public var given: String?

    public init(family: String, given: String? = nil) {
        self.family = family
        self.given = given
    }

    /// Lower-case name particles that belong to the family name ("van der Waals").
    static let particles: Set<String> = [
        "van", "von", "der", "den", "de", "del", "della", "di", "da", "dos", "das",
        "du", "la", "le", "ter", "ten", "zu", "zum", "zur", "bin", "al", "el", "y",
    ]

    static let suffixes: Set<String> = ["jr", "jr.", "sr", "sr.", "ii", "iii", "iv"]

    /// Parses a free-form name such as "Ashish Vaswani", "Vaswani, Ashish" or "Ludwig van Beethoven".
    public static func parse(fullName raw: String) -> Author? {
        var name = raw
            .replacingOccurrences(of: #"[0-9*∗†‡§¶#]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;.").union(.whitespacesAndNewlines))
        guard name.rangeOfCharacter(from: .letters) != nil else { return nil }

        if name.contains(",") {
            let parts = name.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let family = parts[0]
            let given = parts.count > 1 ? parts[1] : nil
            guard !family.isEmpty else { return nil }
            return Author(family: family, given: (given?.isEmpty ?? true) ? nil : given)
        }

        name = name.trimmingCharacters(in: .whitespaces)
        var words = name.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, suffixes.contains(last.lowercased()) {
            words.removeLast()
        }
        guard !words.isEmpty else { return nil }
        if words.count == 1 { return Author(family: words[0]) }

        var start = words.count - 1
        while start - 1 > 0, particles.contains(words[start - 1].lowercased()) {
            start -= 1
        }
        let family = words[start...].joined(separator: " ")
        let given = words[..<start].joined(separator: " ")
        return Author(family: family, given: given.isEmpty ? nil : given)
    }

    /// The family name with SHOUTING CAPS turned into normal capitalisation.
    public var displayFamily: String {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if letters.count > 2, trimmed == trimmed.uppercased() {
            return trimmed.capitalized
        }
        return trimmed
    }
}

/// Where a piece of metadata came from.
public enum MetadataSource: String, Equatable, Sendable {
    /// Looked up via the DOI printed in / embedded into the PDF.
    case doi
    /// Looked up via the arXiv identifier.
    case arxiv
    /// Found via a Crossref title search and verified against the PDF text.
    case crossrefSearch
    /// Only estimated from the PDF itself (no online confirmation).
    case offline
}

/// Bibliographic data used to build the file name.
public struct PaperMetadata: Equatable, Sendable {
    public var authors: [Author]
    public var year: String?
    public var title: String?
    public var source: MetadataSource
    /// DOI or arXiv identifier the data was retrieved with.
    public var identifier: String?
    /// Crossref work type (e.g. "journal-article"), if known.
    public var workType: String?

    public init(
        authors: [Author] = [],
        year: String? = nil,
        title: String? = nil,
        source: MetadataSource = .offline,
        identifier: String? = nil,
        workType: String? = nil
    ) {
        self.authors = authors
        self.year = year
        self.title = title
        self.source = source
        self.identifier = identifier
        self.workType = workType
    }

    /// True when the data was confirmed by an online source.
    public var isVerified: Bool { source != .offline }

    /// True when author, year and title are all present.
    public var isComplete: Bool {
        !authors.isEmpty && !(year ?? "").isEmpty && !(title ?? "").isEmpty
    }

    /// Fills missing fields from another (usually offline) result.
    public func filling(from other: PaperMetadata) -> PaperMetadata {
        var copy = self
        if copy.authors.isEmpty { copy.authors = other.authors }
        if (copy.year ?? "").isEmpty { copy.year = other.year }
        if (copy.title ?? "").isEmpty { copy.title = other.title }
        return copy
    }
}

/// Everything the resolver needs to know about a PDF. Produced by the app with PDFKit.
public struct PDFInfo: Sendable {
    public var fileName: String
    public var metadataTitle: String?
    public var metadataAuthor: String?
    public var metadataSubject: String?
    public var metadataKeywords: [String]
    public var creationYear: String?
    /// Text lines of the first page, in reading order, with font sizes.
    public var lines: [TextLine]
    /// Plain text of the first pages.
    public var text: String
    /// DOIs found in the embedded XMP metadata.
    public var xmpDOIs: [String]

    public init(
        fileName: String,
        metadataTitle: String? = nil,
        metadataAuthor: String? = nil,
        metadataSubject: String? = nil,
        metadataKeywords: [String] = [],
        creationYear: String? = nil,
        lines: [TextLine] = [],
        text: String = "",
        xmpDOIs: [String] = []
    ) {
        self.fileName = fileName
        self.metadataTitle = metadataTitle
        self.metadataAuthor = metadataAuthor
        self.metadataSubject = metadataSubject
        self.metadataKeywords = metadataKeywords
        self.creationYear = creationYear
        self.lines = lines
        self.text = text
        self.xmpDOIs = xmpDOIs
    }
}

/// One line of text on a PDF page.
public struct TextLine: Equatable, Sendable {
    public var text: String
    /// Dominant font size of the line in points.
    public var fontSize: Double
    /// Vertical position of the line's top edge: 0 = top of the page, 1 = bottom.
    public var top: Double

    public init(text: String, fontSize: Double, top: Double) {
        self.text = text
        self.fontSize = fontSize
        self.top = top
    }
}
