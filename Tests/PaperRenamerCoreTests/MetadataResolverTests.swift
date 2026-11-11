import XCTest
@testable import PaperRenamerCore

final class MetadataResolverTests: XCTestCase {
    private let pageText = """
    Mastering the game of Go with deep neural
    networks and tree search
    David Silver1*, Aja Huang1*, Chris J. Maddison1, Arthur Guez1
    Abstract The game of Go has long been viewed as the most challenging of classic games.
    """

    func testBestMatchPicksResultThatAppearsInThePDF() {
        let resolver = MetadataResolver()
        let evidence = PageEvidence(text: pageText)
        let results = [
            PaperMetadata(authors: [Author(family: "Goodfellow")], year: "2016", title: "Deep learning",
                          source: .crossrefSearch, workType: "book"),
            PaperMetadata(authors: [Author(family: "Silver")], year: "2016",
                          title: "Mastering the game of Go with deep neural networks and tree search",
                          source: .crossrefSearch, workType: "journal-article"),
            PaperMetadata(authors: [Author(family: "Silver")], year: "2017",
                          title: "Mastering the game of Go without human knowledge",
                          source: .crossrefSearch, workType: "journal-article"),
        ]
        let best = resolver.bestMatch(
            results, evidence: evidence,
            detectedTitle: "Mastering the game of Go with deep neural networks and tree search"
        )
        XCTAssertEqual(best?.year, "2016")
        XCTAssertEqual(best?.title, "Mastering the game of Go with deep neural networks and tree search")
    }

    func testBestMatchRejectsUnrelatedResults() {
        let resolver = MetadataResolver()
        let evidence = PageEvidence(text: pageText)
        let results = [
            PaperMetadata(authors: [Author(family: "Goodfellow")], year: "2016", title: "Deep learning",
                          source: .crossrefSearch),
        ]
        XCTAssertNil(resolver.bestMatch(results, evidence: evidence, detectedTitle: nil))
    }

    func testOfflineResolution() async {
        let lines = [
            TextLine(text: "Journal of Imaginary Results 12 (2023) 1-10", fontSize: 8, top: 0.05),
            TextLine(text: "A completely fictional study on automatically", fontSize: 18, top: 0.12),
            TextLine(text: "renaming scientific PDF files", fontSize: 18, top: 0.15),
            TextLine(text: "Erika Mustermann1, Max Beispiel2", fontSize: 11, top: 0.2),
        ] + (0..<15).map {
            TextLine(text: "Placeholder body text that is long enough to be the dominant size \($0).",
                     fontSize: 9.5, top: 0.3 + Double($0) * 0.02)
        }
        let info = PDFInfo(
            fileName: "draft.pdf",
            metadataTitle: "Microsoft Word - draft_v3.docx",
            lines: lines,
            text: lines.map(\.text).joined(separator: "\n") + "\n© 2023 The Authors."
        )
        let meta = await MetadataResolver().resolve(info, online: false)
        XCTAssertEqual(meta.source, .offline)
        XCTAssertEqual(
            FilenameFormatter().baseName(for: meta),
            "Mustermann & Beispiel (2023) A completely fictional study on automatically renaming scientific PDF files"
        )
    }
}

/// Real requests against Crossref, doi.org and arXiv. Only run when RUN_NETWORK_TESTS=1.
final class NetworkTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1",
                          "Set RUN_NETWORK_TESTS=1 to run network tests")
    }

    func testCrossrefDOILookup() async throws {
        let meta = try await MetadataResolver().lookupDOI("10.1038/nature14539")
        XCTAssertEqual(meta?.title, "Deep learning")
        XCTAssertEqual(meta?.authors.first?.family, "LeCun")
        XCTAssertEqual(meta?.year, "2015")
    }

    func testDataCiteDOILookup() async throws {
        let meta = try await MetadataResolver().lookupDOI("10.48550/arXiv.1706.03762")
        XCTAssertEqual(meta?.title, "Attention Is All You Need")
        XCTAssertEqual(meta?.authors.first?.family, "Vaswani")
    }

    func testArxivLookup() async throws {
        let meta = try await MetadataResolver().lookupArxiv("1706.03762")
        XCTAssertEqual(meta?.title, "Attention Is All You Need")
        XCTAssertEqual(meta?.authors.first?.family, "Vaswani")
        XCTAssertEqual(meta?.year, "2017")
    }

    func testCrossrefSearch() async throws {
        let results = try await MetadataResolver().searchCrossref(
            "Mastering the game of Go with deep neural networks and tree search"
        )
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { ($0.identifier ?? "").lowercased() == "10.1038/nature16961" },
                      "Results: \(results.map { $0.identifier ?? "?" })")
    }
}
