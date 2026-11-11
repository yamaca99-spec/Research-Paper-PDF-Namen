import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Finds author, year and title of a PDF: first via DOI / arXiv id, then via a Crossref search,
/// and finally (offline) from the PDF itself. Online results are only accepted when their title
/// actually appears in the PDF text.
public final class MetadataResolver {
    private let session: URLSession
    private let userAgent = "PaperRenamer/1.0 (macOS; PDF renaming tool)"

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    public func resolve(_ info: PDFInfo, online: Bool) async -> PaperMetadata {
        let evidence = PageEvidence(text: info.text)
        let detectedTitle = TextHeuristics.detectTitle(lines: info.lines)
        let offline = offlineMetadata(info, evidence: evidence, detectedTitle: detectedTitle)
        guard online else { return offline }
        if let found = await onlineMetadata(info, evidence: evidence, offline: offline) {
            return found.filling(from: offline)
        }
        return offline
    }

    /// Metadata estimated from the PDF only.
    public func offlineMetadata(_ info: PDFInfo) -> PaperMetadata {
        let evidence = PageEvidence(text: info.text)
        return offlineMetadata(info, evidence: evidence, detectedTitle: TextHeuristics.detectTitle(lines: info.lines))
    }

    // MARK: - Offline

    func offlineMetadata(_ info: PDFInfo, evidence: PageEvidence,
                         detectedTitle: TextHeuristics.DetectedTitle?) -> PaperMetadata {
        var meta = PaperMetadata(source: .offline)

        if let metaTitle = info.metadataTitle, TextHeuristics.isPlausibleMetadataTitle(metaTitle),
           evidence.isSparse || evidence.coverage(of: metaTitle) >= 0.7 {
            meta.title = TextTools.collapseWhitespace(metaTitle)
        } else {
            meta.title = detectedTitle?.title
        }

        meta.authors = TextHeuristics.authorsFromMetadata(info.metadataAuthor)
        if meta.authors.isEmpty {
            meta.authors = TextHeuristics.authorsFromLines(info.lines, after: detectedTitle)
        }

        let arxiv = IdentifierExtractor.arxivID(in: info.text)
        meta.year = TextHeuristics.detectYear(text: info.text, arxivID: arxiv, creationYear: info.creationYear)
        if let arxiv = arxiv { meta.identifier = "arXiv:\(arxiv)" }
        return meta
    }

    // MARK: - Online

    private struct NetworkUnavailable: Error {}

    private func onlineMetadata(_ info: PDFInfo, evidence: PageEvidence,
                                offline: PaperMetadata) async -> PaperMetadata? {
        do {
            var arxiv = IdentifierExtractor.arxivID(in: info.text)

            // 1. DOIs (embedded metadata first, then text).
            for candidate in IdentifierExtractor.doiCandidates(for: info).prefix(5) {
                if let id = IdentifierExtractor.arxivID(fromDOI: candidate.doi) {
                    if arxiv == nil { arxiv = id }
                    continue
                }
                guard let meta = try await lookupDOI(candidate.doi) else { continue }
                let coverage = evidence.coverage(of: meta.title)
                let threshold = candidate.trusted ? 0.5 : 0.7
                if coverage >= threshold || (candidate.trusted && evidence.isSparse) {
                    var result = meta
                    result.identifier = candidate.doi
                    return result
                }
            }

            // 2. arXiv identifier.
            if let id = arxiv, let meta = try await lookupArxiv(id) {
                if evidence.coverage(of: meta.title) >= 0.6 || evidence.isSparse {
                    return meta
                }
            }

            // 3. Crossref search with the detected title / the top of the first page.
            guard !evidence.isSparse else { return nil }
            var queries: [String] = []
            if let title = offline.title { queries.append(title) }
            if let metaTitle = info.metadataTitle, TextHeuristics.isPlausibleMetadataTitle(metaTitle) {
                queries.append(metaTitle)
            }
            let topText = info.lines.prefix(25).map(\.text).joined(separator: " ")
            if !topText.isEmpty { queries.append(String(topText.prefix(400))) }

            var tried = Set<String>()
            for query in queries where tried.insert(query.lowercased()).inserted {
                let results = try await searchCrossref(query)
                if let best = bestMatch(results, evidence: evidence, detectedTitle: offline.title) {
                    return best
                }
                if tried.count >= 3 { break }
            }
        } catch {
            // No connection: fall back to the offline result.
        }
        return nil
    }

    /// Picks the search result whose title (and first author) appear in the PDF.
    func bestMatch(_ results: [PaperMetadata], evidence: PageEvidence, detectedTitle: String?) -> PaperMetadata? {
        let badTypes: Set<String> = ["peer-review", "component", "dataset", "grant", "journal-issue", "journal"]
        var best: (meta: PaperMetadata, score: Double)?
        for result in results {
            guard let title = result.title else { continue }
            let words = TextTools.tokens(title)
            guard words.count >= 2 else { continue }
            let coverage = evidence.coverage(of: title)
            guard coverage >= 0.85 else { continue }
            let authorFound = result.authors.first.map { evidence.contains(name: $0.family) } ?? false
            guard authorFound || (coverage >= 0.95 && words.count >= 4) else { continue }
            var score = coverage + (authorFound ? 0.5 : 0)
            if let detected = detectedTitle { score += TextTools.similarity(title, detected) }
            if let type = result.workType, badTypes.contains(type) { score -= 1 }
            if best == nil || score > best!.score { best = (result, score) }
        }
        return best?.meta
    }

    // MARK: - HTTP

    private func get(_ url: URL, accept: String? = nil) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let accept = accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .timedOut,
                 .networkConnectionLost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw NetworkUnavailable()
            default:
                return nil
            }
        }
        guard let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return result.0
    }

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: ";?#%")
        return set
    }()

    /// Crossref first (fast, includes subtitles), then doi.org content negotiation (DataCite & co.).
    func lookupDOI(_ doi: String) async throws -> PaperMetadata? {
        guard let encoded = doi.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed) else { return nil }
        if let url = URL(string: "https://api.crossref.org/works/\(encoded)"),
           let data = try await get(url),
           let meta = MetadataParser.parseCrossrefWork(data) {
            return meta
        }
        if let url = URL(string: "https://doi.org/\(encoded)"),
           let data = try await get(url, accept: "application/vnd.citationstyles.csl+json"),
           let meta = MetadataParser.parseCSL(data) {
            return meta
        }
        return nil
    }

    func lookupArxiv(_ id: String) async throws -> PaperMetadata? {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [URLQueryItem(name: "id_list", value: id)]
        if let url = components.url, let data = try await get(url),
           var meta = MetadataParser.parseArxivAtom(data) {
            // The identifier encodes the month of the first version; it is the citation year.
            if let year = IdentifierExtractor.year(fromArxivID: id) { meta.year = year }
            meta.identifier = "arXiv:\(id)"
            return meta
        }
        // Fallback: DataCite record of the arXiv DOI.
        if var meta = try await lookupDOI("10.48550/arXiv.\(id)") {
            meta.source = .arxiv
            if let year = IdentifierExtractor.year(fromArxivID: id) { meta.year = year }
            meta.identifier = "arXiv:\(id)"
            return meta
        }
        return nil
    }

    func searchCrossref(_ query: String) async throws -> [PaperMetadata] {
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: query),
            URLQueryItem(name: "rows", value: "5"),
            URLQueryItem(name: "select", value: "DOI,title,subtitle,author,editor,issued,published-print,published-online,created,type"),
        ]
        guard let url = components.url, let data = try await get(url) else { return [] }
        return MetadataParser.parseCrossrefSearch(data)
    }
}
