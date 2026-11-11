import XCTest
@testable import PaperRenamerCore

final class MetadataParserTests: XCTestCase {
    func testCrossrefWork() throws {
        let json = """
        {"status":"ok","message-type":"work","message":{
          "DOI":"10.1038/nature14539","type":"journal-article",
          "title":["Deep learning"],"subtitle":[],
          "author":[
            {"given":"Yann","family":"LeCun","sequence":"first"},
            {"given":"Yoshua","family":"Bengio","sequence":"additional"},
            {"given":"Geoffrey","family":"Hinton","sequence":"additional"}],
          "published-print":{"date-parts":[[2015,5,28]]},
          "issued":{"date-parts":[[2015,5,27]]}}}
        """
        let meta = try XCTUnwrap(MetadataParser.parseCrossrefWork(Data(json.utf8)))
        XCTAssertEqual(meta.title, "Deep learning")
        XCTAssertEqual(meta.authors.map(\.family), ["LeCun", "Bengio", "Hinton"])
        XCTAssertEqual(meta.year, "2015")
        XCTAssertEqual(meta.identifier, "10.1038/nature14539")
        XCTAssertEqual(meta.workType, "journal-article")
    }

    func testPrintYearIsPreferredOverOnlineYear() throws {
        let json = """
        {"message":{"title":["T"],"author":[{"family":"A"}],
          "issued":{"date-parts":[[2019,12,1]]},"published-online":{"date-parts":[[2019,12,1]]},
          "published-print":{"date-parts":[[2020,2]]}}}
        """
        XCTAssertEqual(MetadataParser.parseCrossrefWork(Data(json.utf8))?.year, "2020")
    }

    func testSubtitleMarkupAndOrganisations() throws {
        let json = """
        {"message":{"title":["<i>In vivo</i> imaging &amp; analysis"],"subtitle":["a review"],
          "author":[{"name":"WHO Consortium"},{"given":"A.","family":"Smith"}],
          "issued":{"date-parts":[["2018"]]}}}
        """
        let meta = try XCTUnwrap(MetadataParser.parseCrossrefWork(Data(json.utf8)))
        XCTAssertEqual(meta.title, "In vivo imaging & analysis: a review")
        XCTAssertEqual(meta.authors.map(\.family), ["WHO Consortium", "Smith"])
        XCTAssertEqual(meta.year, "2018")
    }

    func testCrossrefSearch() {
        let json = """
        {"status":"ok","message":{"items":[
          {"DOI":"10.1/a","title":["First"],"author":[{"family":"X"}],"issued":{"date-parts":[[2001]]},"type":"journal-article"},
          {"DOI":"10.1/b","author":[{"family":"Y"}]},
          {"DOI":"10.1/c","title":["Third"],"author":[{"family":"Z"}],"issued":{"date-parts":[[2003]]}}]}}
        """
        let results = MetadataParser.parseCrossrefSearch(Data(json.utf8))
        XCTAssertEqual(results.map(\.title), ["First", "Third"])
        XCTAssertEqual(results.first?.source, .crossrefSearch)
    }

    func testCSLJSON() throws {
        let json = """
        {"type":"article","title":"Attention Is All You Need","DOI":"10.48550/ARXIV.1706.03762",
         "author":[{"family":"Vaswani","given":"Ashish"},{"family":"Waals","given":"Johannes","non-dropping-particle":"van der"},
                   {"literal":"Google Brain Team"}],
         "issued":{"date-parts":[[2017]]}}
        """
        let meta = try XCTUnwrap(MetadataParser.parseCSL(Data(json.utf8)))
        XCTAssertEqual(meta.title, "Attention Is All You Need")
        XCTAssertEqual(meta.authors.map(\.family), ["Vaswani", "van der Waals", "Google Brain Team"])
        XCTAssertEqual(meta.year, "2017")
    }

    func testArxivAtom() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title type="html">ArXiv Query: id_list=1706.03762</title>
          <id>http://arxiv.org/api/abc</id>
          <entry>
            <id>http://arxiv.org/abs/1706.03762v7</id>
            <updated>2023-08-02T00:41:18Z</updated>
            <published>2017-06-12T17:57:34Z</published>
            <title>Attention Is All
              You Need</title>
            <summary>Placeholder.</summary>
            <author><name>Ashish Vaswani</name></author>
            <author><name>Noam Shazeer</name></author>
            <author><name>Ludwig van Beethoven</name></author>
          </entry>
        </feed>
        """
        let meta = try XCTUnwrap(MetadataParser.parseArxivAtom(Data(xml.utf8)))
        XCTAssertEqual(meta.title, "Attention Is All You Need")
        XCTAssertEqual(meta.authors.map(\.family), ["Vaswani", "Shazeer", "van Beethoven"])
        XCTAssertEqual(meta.year, "2017")
        XCTAssertEqual(meta.identifier, "1706.03762")
    }

    func testArxivErrorFeed() {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><id>http://arxiv.org/api/errors</id>
        <title>Error</title><summary>incorrect id format</summary></entry></feed>
        """
        XCTAssertNil(MetadataParser.parseArxivAtom(Data(xml.utf8)))
    }
}
