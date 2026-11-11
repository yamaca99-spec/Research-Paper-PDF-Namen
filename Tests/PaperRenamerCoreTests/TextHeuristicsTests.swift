import XCTest
@testable import PaperRenamerCore

final class TextHeuristicsTests: XCTestCase {
    private func bodyLines(from top: Double) -> [TextLine] {
        (0..<20).map { i in
            TextLine(
                text: "This is ordinary body text of the article which is long enough to dominate the page \(i).",
                fontSize: 9.5,
                top: top + Double(i) * 0.02
            )
        }
    }

    private var elsevierLikePage: [TextLine] {
        [
            TextLine(text: "Journal of Hydrology 580 (2020) 124015", fontSize: 8, top: 0.05),
            TextLine(text: "Contents lists available at ScienceDirect", fontSize: 8, top: 0.07),
            TextLine(text: "Journal of Hydrology", fontSize: 14, top: 0.09),
            TextLine(text: "Research papers", fontSize: 9, top: 0.14),
            TextLine(text: "A physically based model for ground-", fontSize: 16, top: 0.17),
            TextLine(text: "water recharge in semi-arid regions", fontSize: 16, top: 0.19),
            TextLine(text: "Anna Müller a,∗, Peter Schmidt b", fontSize: 10, top: 0.23),
            TextLine(text: "a Department of Geosciences, University of Tübingen, Germany", fontSize: 7, top: 0.25),
            TextLine(text: "A B S T R A C T", fontSize: 8, top: 0.30),
        ] + bodyLines(from: 0.32)
    }

    func testTitleDetection() throws {
        let detected = try XCTUnwrap(TextHeuristics.detectTitle(lines: elsevierLikePage))
        XCTAssertEqual(detected.title, "A physically based model for groundwater recharge in semi-arid regions")
        XCTAssertEqual(detected.lastLineIndex, 5)
    }

    func testAuthorsBelowTitle() {
        let lines = elsevierLikePage
        let authors = TextHeuristics.authorsFromLines(lines, after: TextHeuristics.detectTitle(lines: lines))
        XCTAssertEqual(authors.map(\.family), ["Müller", "Schmidt"])
    }

    func testAuthorsWithFootnoteMarkers() {
        let lines = [
            TextLine(text: "Attention Is All You Need", fontSize: 17, top: 0.1),
            TextLine(text: "Ashish Vaswani∗ Noam Shazeer∗ Niki Parmar∗ Jakob Uszkoreit∗", fontSize: 10, top: 0.2),
            TextLine(text: "Google Brain Google Brain Google Research Google Research", fontSize: 10, top: 0.22),
        ] + bodyLines(from: 0.3)
        let title = TextHeuristics.detectTitle(lines: lines)
        XCTAssertEqual(title?.title, "Attention Is All You Need")
        let authors = TextHeuristics.authorsFromLines(lines, after: title)
        XCTAssertEqual(authors.map(\.family), ["Vaswani", "Shazeer", "Parmar", "Uszkoreit"])
    }

    func testNoTitleWhenAllTextHasTheSameSize() {
        XCTAssertNil(TextHeuristics.detectTitle(lines: bodyLines(from: 0.1)))
    }

    func testMetadataAuthors() {
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Doe, Jane; Smith, John").map(\.family), ["Doe", "Smith"])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Jane Doe and John Smith").map(\.family), ["Doe", "Smith"])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Doe, Jane").map(\.family), ["Doe"])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Jane Doe, John Smith").map(\.family), ["Doe", "Smith"])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Vincent van Gogh").map(\.family), ["van Gogh"])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Administrator"), [])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("Elsevier"), [])
        XCTAssertEqual(TextHeuristics.authorsFromMetadata("jdoe@example.org"), [])
    }

    func testAuthorNameParsing() {
        XCTAssertEqual(Author.parse(fullName: "Ludwig van Beethoven")?.family, "van Beethoven")
        XCTAssertEqual(Author.parse(fullName: "Martin Luther King Jr.")?.family, "King")
        XCTAssertEqual(Author.parse(fullName: "Vaswani, Ashish")?.family, "Vaswani")
        XCTAssertEqual(Author.parse(fullName: "Vaswani, Ashish")?.given, "Ashish")
        XCTAssertNil(Author.parse(fullName: "123 *"))
    }

    func testPlausibleMetadataTitles() {
        XCTAssertFalse(TextHeuristics.isPlausibleMetadataTitle("Microsoft Word - paper_final.docx"))
        XCTAssertFalse(TextHeuristics.isPlausibleMetadataTitle("untitled"))
        XCTAssertFalse(TextHeuristics.isPlausibleMetadataTitle("PII: S0022-1694(19)31234-5"))
        XCTAssertFalse(TextHeuristics.isPlausibleMetadataTitle(nil))
        XCTAssertTrue(TextHeuristics.isPlausibleMetadataTitle("Deep learning for plant disease detection"))
    }

    func testYearDetection() {
        let text = "Received 3 May 2019; Accepted 12 Dec 2019\n© 2020 Elsevier B.V. All rights reserved."
        XCTAssertEqual(TextHeuristics.detectYear(text: text, arxivID: nil, creationYear: "2023"), "2020")
        XCTAssertEqual(TextHeuristics.detectYear(text: "© The Author(s), under exclusive licence 2021", arxivID: nil, creationYear: nil), "2021")
        XCTAssertEqual(TextHeuristics.detectYear(text: "Published online: 4 March 2018", arxivID: nil, creationYear: nil), "2018")
        XCTAssertEqual(TextHeuristics.detectYear(text: "nothing", arxivID: "1706.03762", creationYear: "2023"), "2017")
        XCTAssertEqual(TextHeuristics.detectYear(text: "nothing", arxivID: nil, creationYear: "2023"), "2023")
        XCTAssertNil(TextHeuristics.detectYear(text: "nothing", arxivID: nil, creationYear: nil))
    }

    func testPageEvidence() {
        let evidence = PageEvidence(text: "A physically based model for ground-\nwater recharge\nAnna Müller, Peter Schmidt")
        XCTAssertEqual(evidence.coverage(of: "A Physically-Based Model for Groundwater Recharge"), 1, accuracy: 0.001)
        XCTAssertTrue(evidence.contains(name: "Müller"))
        XCTAssertTrue(evidence.contains(name: "Muller"))
        XCTAssertFalse(evidence.contains(name: "Weber"))
        XCTAssertLessThan(evidence.coverage(of: "Deep learning in hydrology"), 0.5)
    }
}
