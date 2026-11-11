import Foundation

/// A DOI found in a PDF together with how much we trust it to be the PDF's own DOI.
public struct DOICandidate: Equatable, Sendable {
    public var doi: String
    /// True for DOIs from the embedded metadata (XMP / document info), which describe the document itself.
    public var trusted: Bool

    public init(doi: String, trusted: Bool) {
        self.doi = doi
        self.trusted = trusted
    }
}

/// Finds DOIs and arXiv identifiers in PDF text and metadata.
public enum IdentifierExtractor {
    private static let doiPattern = #"10\.\d{4,9}/[^\s"<>{}|\\^`\[\]]+"#

    private static let doiRegex = try! NSRegularExpression(pattern: doiPattern, options: [.caseInsensitive])

    /// DOIs explicitly marked as such ("doi:", "DOI ", "doi.org/").
    private static let prefixedDOIRegex = try! NSRegularExpression(
        pattern: #"(?:doi\s*[:.]?\s*|doi\.org/|dx\.doi\.org/)(10\.\d{4,9}/[^\s"<>{}|\\^`\[\]]+)"#,
        options: [.caseInsensitive]
    )

    /// Removes trailing punctuation that is usually not part of the DOI.
    public static func cleanDOI(_ raw: String) -> String? {
        var doi = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = doi.last, ".,;:'\")]}>".contains(last) {
            if last == ")" {
                let open = doi.filter { $0 == "(" }.count
                let close = doi.filter { $0 == ")" }.count
                if open >= close { break }
            }
            doi.removeLast()
        }
        guard doi.count >= 8, doi.contains("/"), !doi.hasSuffix("/") else { return nil }
        return doi
    }

    private static func matches(_ regex: NSRegularExpression, in text: String, group: Int = 0) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// All DOIs in a text, in order of appearance, without duplicates.
    public static func dois(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in matches(doiRegex, in: text) {
            guard let doi = cleanDOI(raw), seen.insert(doi.lowercased()).inserted else { continue }
            result.append(doi)
        }
        return result
    }

    /// DOIs that are explicitly labelled as DOI in the text.
    public static func prefixedDOIs(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in matches(prefixedDOIRegex, in: text, group: 1) {
            guard let doi = cleanDOI(raw), seen.insert(doi.lowercased()).inserted else { continue }
            result.append(doi)
        }
        return result
    }

    /// Ordered DOI candidates: embedded metadata first, then labelled DOIs, then any DOI in the text.
    public static func doiCandidates(for info: PDFInfo) -> [DOICandidate] {
        var seen = Set<String>()
        var result: [DOICandidate] = []
        func add(_ dois: [String], trusted: Bool) {
            for doi in dois where seen.insert(doi.lowercased()).inserted {
                result.append(DOICandidate(doi: doi, trusted: trusted))
            }
        }
        add(info.xmpDOIs.compactMap(cleanDOI), trusted: true)
        let metadataText = [info.metadataSubject, info.metadataTitle]
            .compactMap { $0 }
            .joined(separator: " ") + " " + info.metadataKeywords.joined(separator: " ")
        add(dois(in: metadataText), trusted: true)
        add(prefixedDOIs(in: info.text), trusted: false)
        add(dois(in: info.text), trusted: false)
        return result
    }

    /// DOIs inside the XMP metadata packet(s) of a raw PDF file.
    public static func xmpDOIs(in data: Data) -> [String] {
        let startMarker = Data("<x:xmpmeta".utf8)
        let endMarker = Data("</x:xmpmeta>".utf8)
        var result: [String] = []
        var searchStart = data.startIndex
        var packets = 0
        while packets < 10,
              let start = data.range(of: startMarker, in: searchStart..<data.endIndex) {
            let limit = min(data.endIndex, start.upperBound + 2_000_000)
            guard let end = data.range(of: endMarker, in: start.upperBound..<limit) else { break }
            let packet = data[start.lowerBound..<end.upperBound]
            if let xml = String(data: packet, encoding: .utf8) ?? String(data: packet, encoding: .isoLatin1) {
                for doi in dois(in: xml) where !result.contains(where: { $0.lowercased() == doi.lowercased() }) {
                    result.append(doi)
                }
            }
            searchStart = end.upperBound
            packets += 1
        }
        return result
    }

    // MARK: - arXiv

    private static let arxivStampRegex = try! NSRegularExpression(
        pattern: #"arXiv:\s?(\d{4}\.\d{4,5}|[a-z][a-z\-]*(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?\s*\["#,
        options: [.caseInsensitive]
    )
    private static let arxivRegex = try! NSRegularExpression(
        pattern: #"(?:arXiv:\s?|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}|[a-z][a-z\-]*(?:\.[A-Z]{2})?/\d{7})"#,
        options: [.caseInsensitive]
    )

    /// The arXiv identifier of the paper (without version), preferring the stamp in the page margin.
    public static func arxivID(in text: String) -> String? {
        if let stamp = matches(arxivStampRegex, in: text, group: 1).first { return stamp }
        return matches(arxivRegex, in: text, group: 1).first
    }

    /// arXiv identifier encoded in an arXiv DOI (10.48550/arXiv.1706.03762).
    public static func arxivID(fromDOI doi: String) -> String? {
        let prefix = "10.48550/arxiv."
        guard doi.lowercased().hasPrefix(prefix) else { return nil }
        let id = String(doi.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    /// Submission year encoded in an arXiv identifier ("1706.03762" -> 2017, "hep-th/9901001" -> 1999).
    public static func year(fromArxivID id: String) -> String? {
        let digits: Substring
        if let slash = id.lastIndex(of: "/") {
            digits = id[id.index(after: slash)...]
        } else {
            digits = Substring(id)
        }
        guard digits.count >= 4, let yy = Int(digits.prefix(2)) else { return nil }
        let year = yy >= 91 ? 1900 + yy : 2000 + yy
        return String(year)
    }
}
