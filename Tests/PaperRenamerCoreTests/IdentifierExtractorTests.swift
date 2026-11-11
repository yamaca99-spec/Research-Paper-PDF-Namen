import XCTest
@testable import PaperRenamerCore

final class IdentifierExtractorTests: XCTestCase {
    func testDOIInText() {
        let text = "Nature 521, 436–444 (2015). https://doi.org/10.1038/nature14539. Received 25 February 2015"
        XCTAssertEqual(IdentifierExtractor.dois(in: text), ["10.1038/nature14539"])
    }

    func testDOICleanup() {
        XCTAssertEqual(IdentifierExtractor.cleanDOI("10.1016/S0140-6736(20)30183-5)."), "10.1016/S0140-6736(20)30183-5")
        XCTAssertEqual(IdentifierExtractor.dois(in: "(see doi:10.1000/xyz123)"), ["10.1000/xyz123"])
        XCTAssertEqual(IdentifierExtractor.dois(in: "DOI 10.1002/anie.201915678;"), ["10.1002/anie.201915678"])
        XCTAssertNil(IdentifierExtractor.cleanDOI("10.1000/"))
    }

    func testLabelledDOIsComeFirst() {
        let info = PDFInfo(
            fileName: "x.pdf",
            text: "As shown before (10.1000/cited.1) ... Article DOI: 10.1234/own.5\nmore 10.1000/cited.1"
        )
        XCTAssertEqual(IdentifierExtractor.doiCandidates(for: info).map(\.doi), ["10.1234/own.5", "10.1000/cited.1"])
        XCTAssertFalse(IdentifierExtractor.doiCandidates(for: info)[0].trusted)
    }

    func testMetadataDOIsAreTrusted() {
        let info = PDFInfo(
            fileName: "x.pdf",
            metadataSubject: "Journal of Hydrology, 580 (2020) 124015. doi:10.1016/j.jhydrol.2019.124015",
            text: "references 10.1000/cited.1",
            xmpDOIs: ["10.1016/J.JHYDROL.2019.124015"]
        )
        let candidates = IdentifierExtractor.doiCandidates(for: info)
        XCTAssertEqual(candidates.map(\.doi), ["10.1016/J.JHYDROL.2019.124015", "10.1000/cited.1"])
        XCTAssertTrue(candidates[0].trusted)
    }

    func testXMPExtraction() {
        let raw = "%PDF-1.5 garbage <x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF><rdf:Description "
            + "prism:doi=\"10.1016/j.cell.2020.01.001\"/></rdf:RDF></x:xmpmeta> trailer 10.9999/notxmp"
        XCTAssertEqual(IdentifierExtractor.xmpDOIs(in: Data(raw.utf8)), ["10.1016/j.cell.2020.01.001"])
        XCTAssertEqual(IdentifierExtractor.xmpDOIs(in: Data("no metadata".utf8)), [])
    }

    func testArxivIdentifiers() {
        let text = "We use Adam (arXiv:1412.6980).\narXiv:1706.03762v7  [cs.CL]  2 Aug 2023"
        XCTAssertEqual(IdentifierExtractor.arxivID(in: text), "1706.03762")
        XCTAssertEqual(IdentifierExtractor.arxivID(in: "arXiv:hep-th/9901001v2 [hep-th]"), "hep-th/9901001")
        XCTAssertEqual(IdentifierExtractor.arxivID(in: "see https://arxiv.org/abs/2005.14165"), "2005.14165")
        XCTAssertNil(IdentifierExtractor.arxivID(in: "no identifier here"))
        XCTAssertEqual(IdentifierExtractor.arxivID(fromDOI: "10.48550/arXiv.2101.00001"), "2101.00001")
        XCTAssertNil(IdentifierExtractor.arxivID(fromDOI: "10.1038/nature14539"))
    }

    func testYearFromArxivID() {
        XCTAssertEqual(IdentifierExtractor.year(fromArxivID: "1706.03762"), "2017")
        XCTAssertEqual(IdentifierExtractor.year(fromArxivID: "hep-th/9901001"), "1999")
        XCTAssertEqual(IdentifierExtractor.year(fromArxivID: "2401.00001"), "2024")
    }
}
