import XCTest
@testable import PaperRenamerCore

final class FilenameFormatterTests: XCTestCase {
    let muller = Author(family: "Müller")
    let schmidt = Author(family: "Schmidt")
    let weber = Author(family: "Weber")

    func testAPAAuthorStyle() {
        let formatter = FilenameFormatter(authorStyle: .apa)
        XCTAssertEqual(formatter.authorText([muller]), "Müller")
        XCTAssertEqual(formatter.authorText([muller, schmidt]), "Müller & Schmidt")
        XCTAssertEqual(formatter.authorText([muller, schmidt, weber]), "Müller et al.")
        XCTAssertNil(formatter.authorText([]))
    }

    func testOtherAuthorStyles() {
        XCTAssertEqual(FilenameFormatter(authorStyle: .firstEtAl).authorText([muller, schmidt]), "Müller et al.")
        XCTAssertEqual(FilenameFormatter(authorStyle: .firstEtAl).authorText([muller]), "Müller")
        XCTAssertEqual(FilenameFormatter(authorStyle: .firstOnly).authorText([muller, schmidt, weber]), "Müller")
    }

    func testShoutingFamilyName() {
        XCTAssertEqual(FilenameFormatter().authorText([Author(family: "SMITH")]), "Smith")
        XCTAssertEqual(FilenameFormatter().authorText([Author(family: "LeCun")]), "LeCun")
    }

    func testBaseNameFromMetadata() {
        let meta = PaperMetadata(
            authors: [Author(family: "Vaswani"), Author(family: "Shazeer"), Author(family: "Parmar")],
            year: "2017",
            title: "Attention Is All You Need",
            source: .arxiv
        )
        XCTAssertEqual(FilenameFormatter().baseName(for: meta), "Vaswani et al. (2017) Attention Is All You Need")
    }

    func testIncompleteMetadataGivesNoName() {
        let meta = PaperMetadata(authors: [muller], year: nil, title: "Titel")
        XCTAssertNil(FilenameFormatter().baseName(for: meta))
        XCTAssertNil(FilenameFormatter().baseName(author: "Müller", year: "2020", title: "  "))
    }

    func testSeparators() {
        XCTAssertEqual(FilenameFormatter(separator: .space).baseName(author: "Müller", year: "2021", title: "Titel"),
                       "Müller (2021) Titel")
        XCTAssertEqual(FilenameFormatter(separator: .dash).baseName(author: "Müller", year: "2021", title: "Titel"),
                       "Müller (2021) - Titel")
        XCTAssertEqual(FilenameFormatter(separator: .period).baseName(author: "Müller", year: "2021", title: "Titel"),
                       "Müller (2021). Titel")
    }

    func testSanitize() {
        XCTAssertEqual(FilenameFormatter.sanitize("BERT: Pre-training of Deep/Bidirectional Transformers?"),
                       "BERT - Pre-training of Deep-Bidirectional Transformers")
        XCTAssertEqual(FilenameFormatter.sanitize("A \"quoted\" <title>\n with  spaces"),
                       "A 'quoted' title with spaces")
        XCTAssertEqual(FilenameFormatter.sanitize("\u{FB01}nite e\u{FB00}ects"), "finite effects")
        XCTAssertEqual(FilenameFormatter.sanitize("..hidden"), "hidden")
    }

    func testCleanTitle() {
        XCTAssertEqual(FilenameFormatter.cleanTitle("DEEP LEARNING FOR EVERYONE."), "Deep learning for everyone")
        XCTAssertEqual(FilenameFormatter.cleanTitle("<i>In vivo</i> imaging &amp; analysis"), "In vivo imaging & analysis")
        XCTAssertEqual(FilenameFormatter.cleanTitle("Attention Is All You Need"), "Attention Is All You Need")
        XCTAssertNil(FilenameFormatter.cleanTitle(" "))
    }

    func testLongTitlesAreShortenedAtWordBoundary() {
        let formatter = FilenameFormatter(maxLength: 60)
        let name = formatter.baseName(author: "Müller", year: "2020", title: String(repeating: "word ", count: 40))
        XCTAssertNotNil(name)
        XCTAssertLessThanOrEqual(name!.count, 60)
        XCTAssertTrue(name!.hasSuffix("word"))
    }

    func testNameStaysBelowFileSystemLimit() {
        let formatter = FilenameFormatter(maxLength: 1000)
        let name = formatter.baseName(author: "Müller", year: "2020", title: String(repeating: "Überprüfung ", count: 60))!
        XCTAssertLessThanOrEqual((name + ".pdf").utf8.count, 255)
    }

    func testUniqueFileName() {
        let taken: Set<String> = ["A.pdf", "A (2).pdf"]
        XCTAssertEqual(FilenameFormatter.uniqueFileName(base: "A", ext: "pdf") { taken.contains($0) }, "A (3).pdf")
        XCTAssertEqual(FilenameFormatter.uniqueFileName(base: "B", ext: "pdf") { taken.contains($0) }, "B.pdf")
    }
}
