import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses responses of Crossref, doi.org (CSL-JSON) and the arXiv API.
public enum MetadataParser {
    // MARK: - Crossref / CSL-JSON

    /// Parses a Crossref work or a CSL-JSON item (both use very similar keys).
    public static func parseWork(_ object: [String: Any], source: MetadataSource) -> PaperMetadata {
        var meta = PaperMetadata(source: source)
        meta.title = title(from: object)
        meta.authors = authors(from: object["author"])
        if meta.authors.isEmpty {
            meta.authors = authors(from: object["editor"])
        }
        meta.year = year(from: object)
        meta.identifier = (object["DOI"] as? String) ?? (object["doi"] as? String)
        meta.workType = object["type"] as? String
        return meta
    }

    /// `{"status": "ok", "message": {...}}` from api.crossref.org/works/{doi}
    public static func parseCrossrefWork(_ data: Data) -> PaperMetadata? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any] else { return nil }
        let meta = parseWork(message, source: .doi)
        return meta.title == nil ? nil : meta
    }

    /// `{"message": {"items": [...]}}` from api.crossref.org/works?query...
    public static func parseCrossrefSearch(_ data: Data) -> [PaperMetadata] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]] else { return [] }
        return items.map { parseWork($0, source: .crossrefSearch) }.filter { $0.title != nil }
    }

    /// CSL-JSON from https://doi.org/{doi} (works for Crossref, DataCite, mEDRA, ... DOIs).
    public static func parseCSL(_ data: Data) -> PaperMetadata? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let meta = parseWork(object, source: .doi)
        return meta.title == nil ? nil : meta
    }

    static func string(from value: Any?) -> String? {
        if let s = value as? String { return s }
        if let array = value as? [Any] { return array.compactMap { $0 as? String }.first }
        return nil
    }

    static func title(from object: [String: Any]) -> String? {
        guard var title = string(from: object["title"]).map(TextTools.stripMarkup), !title.isEmpty else {
            return nil
        }
        if let subtitle = string(from: object["subtitle"]).map(TextTools.stripMarkup), !subtitle.isEmpty,
           !title.lowercased().contains(subtitle.lowercased()) {
            let separator = title.hasSuffix("?") || title.hasSuffix("!") || title.hasSuffix(":") ? " " : ": "
            title += separator + subtitle
        }
        return title
    }

    static func authors(from value: Any?) -> [Author] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.compactMap { entry -> Author? in
            let given = (entry["given"] as? String).map(TextTools.collapseWhitespace)
            if var family = (entry["family"] as? String).map(TextTools.collapseWhitespace), !family.isEmpty {
                if let particle = entry["non-dropping-particle"] as? String, !particle.isEmpty,
                   !family.lowercased().hasPrefix(particle.lowercased()) {
                    family = particle + " " + family
                }
                return Author(family: family, given: (given?.isEmpty ?? true) ? nil : given)
            }
            if let literal = (entry["literal"] as? String) ?? (entry["name"] as? String) {
                let name = TextTools.collapseWhitespace(literal)
                return name.isEmpty ? nil : Author(family: name)
            }
            return nil
        }
    }

    static func year(fromDateObject value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let parts = object["date-parts"] as? [[Any]], let first = parts.first?.first {
            if let n = first as? NSNumber, n.intValue > 0 { return String(n.intValue) }
            if let s = first as? String, let n = Int(s), n > 0 { return String(n) }
        }
        if let raw = object["raw"] as? String,
           let range = raw.range(of: #"(19|20)\d{2}"#, options: .regularExpression) {
            return String(raw[range])
        }
        return nil
    }

    static func year(from object: [String: Any]) -> String? {
        for key in ["published-print", "issued", "published", "published-online", "created"] {
            if let year = year(fromDateObject: object[key]) { return year }
        }
        return nil
    }

    // MARK: - arXiv Atom feed

    /// Parses the first entry of an arXiv API response.
    public static func parseArxivAtom(_ data: Data) -> PaperMetadata? {
        let delegate = ArxivAtomDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() || delegate.title != nil else { return nil }
        guard let rawTitle = delegate.title else { return nil }
        let title = TextTools.collapseWhitespace(rawTitle)
        guard !title.isEmpty, title.lowercased() != "error" else { return nil }

        var meta = PaperMetadata(source: .arxiv)
        meta.title = title
        meta.authors = delegate.authorNames.compactMap(Author.parse(fullName:))
        if let published = delegate.published, published.count >= 4 {
            meta.year = String(published.prefix(4))
        }
        if let id = delegate.id {
            meta.identifier = id
                .replacingOccurrences(of: #"^https?://arxiv\.org/abs/"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        }
        meta.workType = "posted-content"
        return meta
    }
}

private final class ArxivAtomDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var published: String?
    var id: String?
    var authorNames: [String] = []

    private var inEntry = false
    private var entryCount = 0
    private var inAuthor = false
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "entry" {
            entryCount += 1
            inEntry = entryCount == 1
        } else if elementName == "author" {
            inAuthor = true
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        defer { buffer = "" }
        guard inEntry else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "entry":
            inEntry = false
        case "author":
            inAuthor = false
        case "name" where inAuthor:
            if !value.isEmpty { authorNames.append(value) }
        case "title":
            if title == nil { title = value }
        case "published":
            if published == nil { published = value }
        case "id":
            if id == nil { id = value }
        default:
            break
        }
    }
}
