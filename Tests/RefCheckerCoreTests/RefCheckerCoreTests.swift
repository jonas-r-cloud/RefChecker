import XCTest
@testable import RefCheckerCore

final class SectionAndSplitTests: XCTestCase {
    func testFindsLastReferencesHeadingAndStopsAtAppendix() {
        let text = """
        1 Introduction
        As shown in the references below …
        References
        [1] A. Smith, “First paper,” 2020.
        [2] B. Jones, “Second paper,” 2021.
        Appendix A
        Extra material
        """
        let section = ReferenceSectionExtractor.extract(from: text)
        XCTAssertEqual(section?.hasPrefix("[1]"), true)
        XCTAssertEqual(section?.contains("Extra material"), false)
    }

    func testBracketedNumbersWithWrappedLines() {
        let section = """
        [1] A. Smith and B. Jones, “A study of infor-
        mation retrieval,” in Proc. SIGIR, 2020, pp. 1–10.
        [2] C. Doe, “Another title,” IEEE Trans. Softw. Eng., vol. 5, no. 3, 2019.
        """
        let entries = ReferenceSplitter.split(section)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].label, "1")
        XCTAssertTrue(entries[0].text.contains("information retrieval"))
    }

    func testAuthorYearList() {
        let section = """
        Smith, J., & Doe, A. (2020). Learning to rank references. Journal of Testing, 12(3),
        45–67. https://doi.org/10.1234/jt.2020.
        5678
        Zhang, L. (2019). Another paper. In Proceedings of the
        Conference on Things (pp. 1–9).
        """
        let entries = ReferenceSplitter.split(section)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].text.contains("10.1234/jt.2020.5678"))
    }
}

final class ParserTests: XCTestCase {
    func testIEEE() {
        let r = ReferenceParser.parse("A. Smith and B. Jones, “A study of retrieval,” in Proc. SIGIR, 2020, pp. 1–10, doi: 10.1145/1234.5678.",
                                      label: "1", id: 0)
        XCTAssertEqual(r.title, "A study of retrieval")
        XCTAssertEqual(r.year, "2020")
        XCTAssertEqual(r.doi, "10.1145/1234.5678")
        XCTAssertEqual(r.venue, "Proc. SIGIR")
    }

    func testAPA() {
        let r = ReferenceParser.parse("Smith, J., & Doe, A. (2020). Learning to rank references. Journal of Testing, 12(3), 45–67.",
                                      label: "1", id: 0)
        XCTAssertEqual(r.authorsText, "Smith, J., & Doe, A")
        XCTAssertEqual(r.title, "Learning to rank references")
        XCTAssertEqual(r.year, "2020")
    }

    func testSpringer() {
        let r = ReferenceParser.parse("Smith, J., Doe, A.: Learning to rank references. In: Proc. ICTIR, pp. 1–9. Springer (2021)",
                                      label: "1", id: 0)
        XCTAssertEqual(r.title, "Learning to rank references")
        XCTAssertEqual(r.year, "2021")
    }

    func testACM() {
        let r = ReferenceParser.parse("Alice Smith and Bob Jones. 2020. Learning to Rank References. In Proceedings of SIGIR. ACM, 1–10.",
                                      label: "1", id: 0)
        XCTAssertEqual(r.authorsText, "Alice Smith and Bob Jones")
        XCTAssertEqual(r.title, "Learning to Rank References")
    }
}

final class ComparatorTests: XCTestCase {
    let meta = RetrievedMetadata(
        provider: "Test", title: "Learning to rank references",
        authors: [Author(given: "John", family: "Smith"), Author(given: "Anna", family: "Doe")],
        year: "2020", venue: "Journal of Testing", volume: "12", issue: "3", pages: "45-67", doi: "10.1234/jt.2020.5678")

    func testExactReferenceIsAllGreen() {
        let ref = ReferenceParser.parse("Smith, J., & Doe, A. (2020). Learning to Rank References. Journal of Testing, 12(3), 45–67. https://doi.org/10.1234/jt.2020.5678",
                                        label: "1", id: 0)
        let (fields, highlights) = Comparator.compare(ref, with: meta)
        XCTAssertTrue(fields.allSatisfy { $0.status == .match }, "\(fields)")
        XCTAssertFalse(highlights.isEmpty)
    }

    func testDifferencesAreRed() {
        let ref = ReferenceParser.parse("Smith, J. (2019). Learning to rank citations. Journal of Testing, 12(3), 45–67.",
                                        label: "1", id: 0)
        let fields = Dictionary(uniqueKeysWithValues: Comparator.compare(ref, with: meta).fields.map { ($0.field, $0.status) })
        XCTAssertEqual(fields["Title"], .mismatch)
        XCTAssertEqual(fields["Authors"], .mismatch)
        XCTAssertEqual(fields["Year"], .mismatch)
        XCTAssertEqual(fields["DOI"], .missing)
        XCTAssertEqual(fields["Venue"], .match)
    }

    func testNormalizationIgnoresAccentsAndLigatures() {
        let t = NormalizedText("Müller, K.: E\u{FB03}cient Indexing")
        XCTAssertNotNil(t.find("efficient indexing"))
        XCTAssertNotNil(t.findWords("Muller"))
    }
}

final class AISeLTests: XCTestCase {
    let page = """
    <html><head>
    <meta name="bepress_citation_series_title" content="ICIS 2020 Proceedings">
    <meta name="bepress_citation_author" content="Smith, John">
    <meta name="bepress_citation_author" content="M&#252;ller, Anna">
    <meta name="bepress_citation_title" content="Digital Nudging in Online Platforms">
    <meta name="bepress_citation_date" content="2020">
    </head></html>
    """

    func testConferenceFromURL() {
        let conf = AISeLProvider.conference(forURL: "https://aisel.aisnet.org/icis2020/digital_learning_env/digital_learning_env/3/")
        XCTAssertEqual(conf?.year, "2020")
        XCTAssertEqual(conf?.venue, "International Conference on Information Systems (ICIS 2020)")
        XCTAssertNotNil(AISeLProvider.conference(forURL: "https://aisel.aisnet.org/ecis2021_rp/12"))
        XCTAssertNotNil(AISeLProvider.conference(forURL: "https://aisel.aisnet.org/wi2021/HCI/Track10/5"))
        XCTAssertNil(AISeLProvider.conference(forURL: "https://aisel.aisnet.org/jais/vol21/iss1/3"))
    }

    func testParsesLandingPage() {
        let m = AISeLProvider.parseRecord(html: page, url: "https://aisel.aisnet.org/icis2020/digital_learning_env/digital_learning_env/3/")
        XCTAssertEqual(m?.title, "Digital Nudging in Online Platforms")
        XCTAssertEqual(m?.authors.map(\.family), ["Smith", "Müller"])
        XCTAssertEqual(m?.year, "2020")
        XCTAssertEqual(m?.venue, "International Conference on Information Systems (ICIS 2020)")
    }

    func testConferenceReferenceMatchesAISeLVenue() {
        let ref = ReferenceParser.parse("Smith, J., & Müller, A. (2020). Digital nudging in online platforms. In Proceedings of the 41st International Conference on Information Systems (ICIS), India.",
                                        label: "1", id: 0)
        XCTAssertTrue(AISeLProvider.mentionsAIS(ref))
        let m = AISeLProvider.parseRecord(html: page, url: "https://aisel.aisnet.org/icis2020/digital_learning_env/digital_learning_env/3/")!
        let fields = Dictionary(uniqueKeysWithValues: Comparator.compare(ref, with: m).fields.map { ($0.field, $0.status) })
        XCTAssertEqual(fields["Venue"], .match)
        XCTAssertEqual(fields["Title"], .match)
        XCTAssertEqual(fields["Authors"], .match)
    }
}

final class PageCleanerTests: XCTestCase {
    func page(_ n: Int, header: String, body: [String], footer: String) -> [PageLine] {
        var lines = [PageLine(text: header, top: 0.03, bottom: 0.05)]
        for (i, b) in body.enumerated() {
            let top = 0.1 + Double(i) * 0.03
            lines.append(PageLine(text: b, top: top, bottom: top + 0.02))
        }
        lines.append(PageLine(text: footer, top: 0.95, bottom: 0.97))
        return lines
    }

    func testRemovesRunningHeadersFootersAndPageNumbers() {
        let pages = [
            page(1, header: "Smith et al.: Digital Nudging", body: ["Body text"], footer: "Forty-First International Conference on Information Systems, India 2020 1"),
            page(2, header: "Digital Nudging", body: ["References", "[1] A. Smith, “A study of infor-"], footer: "Forty-First International Conference on Information Systems, India 2020 2"),
            page(3, header: "Smith et al.: Digital Nudging", body: ["mation retrieval,” in Proc. SIGIR, 2020.", "[2] B. Jones, “Another paper,” 2021."], footer: "Forty-First International Conference on Information Systems, India 2020 3")
        ]
        let result = PageCleaner.clean(pages: pages)
        XCTAssertFalse(result.text.contains("International Conference on Information Systems, India"))
        XCTAssertFalse(result.text.contains("Smith et al.: Digital Nudging"))
        XCTAssertTrue(result.text.contains("[1] A. Smith, “A study of infor-\nmation retrieval,”"))
        let refs = ReferenceParser.parse(section: ReferenceSectionExtractor.extract(from: result.text) ?? "")
        XCTAssertEqual(refs.count, 2)
        XCTAssertTrue(refs[0].raw.contains("information retrieval"))
    }

    func testKeepsReferenceLinesNearMarginWithoutGeometry() {
        let pages = [
            ["Running Title", "[1] A. Smith, “Paper,” in Proceedings of the ICIS, 2020.", "12"].map { PageLine(text: $0) },
            ["Running Title", "[2] B. Jones, “Other,” 2021.", "13"].map { PageLine(text: $0) }
        ]
        let result = PageCleaner.clean(pages: pages)
        XCTAssertEqual(result.text, "[1] A. Smith, “Paper,” in Proceedings of the ICIS, 2020.\n[2] B. Jones, “Other,” 2021.")
    }
}

final class NumberPlacementTests: XCTestCase {
    func testNumbersMustBeRecognisablyPlaced() {
        let meta = RetrievedMetadata(provider: "Crossref", title: "Learning to rank references",
                                     authors: [Author(given: "John", family: "Smith")],
                                     year: "2020", venue: "Journal of Testing", volume: "3", issue: "12", pages: "45-67")
        // "3" and "12" occur, but only inside other numbers' positions; pages are not a range.
        let ref = ReferenceParser.parse("Smith, J. (2020). Learning to rank references. Journal of Testing, 12 chapters, 3 figures, p. 45, see 67.",
                                        label: "1", id: 0)
        let fields = Dictionary(uniqueKeysWithValues: Comparator.compare(ref, with: meta).fields.map { ($0.field, $0.status) })
        XCTAssertEqual(fields["Volume"], .unconfirmed)
        XCTAssertEqual(fields["Pages"], .unconfirmed)
        XCTAssertEqual(fields["Title"], .match)
    }
}

final class ResolutionTests: XCTestCase {
    func testResolvedReferenceCountsAsVerifiedButKeepsFieldColours() {
        let ref = ReferenceParser.parse("Smith, J. (2019). Learning to rank citations. Journal of Testing.", label: "1", id: 0)
        let field = FieldComparison(field: "Year", original: "2019", retrieved: "2020", status: .mismatch)
        let result = ReferenceResult(reference: ref, metadata: nil, fields: [field], highlights: [],
                                     verdict: .issues(1), notes: [])
        let html = HTMLReport.render(references: [ref], results: [0: result], source: "paper.pdf",
                                     resolutions: [0: Resolution(note: "Online-first year")])
        XCTAssertTrue(html.contains("1 verified (1 resolved manually)"))
        XCTAssertTrue(html.contains("Resolved manually (was: 1 issue)"))
        XCTAssertTrue(html.contains("Online-first year"))
        XCTAssertTrue(html.contains("<td class=\"bad\">2019</td>"), "field colours must stay as computed")
    }

    func testResolutionKeyIgnoresLineBreaksAndPunctuation() {
        let a = ReferenceParser.parse("Smith, J. (2019). Learning to rank.", label: "1", id: 0)
        let b = ReferenceParser.parse("Smith, J. (2019).  Learning to\nrank", label: "4", id: 3)
        XCTAssertEqual(Resolution.key(for: a), Resolution.key(for: b))
    }
}

final class AffiliationTests: XCTestCase {
    let url = "https://aisel.aisnet.org/icis2020/digital_learning_env/digital_learning_env/3/"
    let ref = ReferenceParser.parse("Smith, J., & Müller, A. (2020). Digital nudging in online platforms. In Proceedings of the International Conference on Information Systems (ICIS 2020).",
                                    label: "1", id: 0)

    func page(_ authorTags: String) -> String {
        """
        <meta name="bepress_citation_series_title" content="ICIS 2020 Proceedings">
        \(authorTags)
        <meta name="bepress_citation_title" content="Digital Nudging in Online Platforms">
        <meta name="bepress_citation_date" content="2020">
        """
    }

    func testInstitutionListedAsAuthorIsDroppedWithCertainty() {
        let html = page("""
        <meta name="bepress_citation_author" content="Smith, John">
        <meta name="bepress_citation_author_institution" content="University of Bamberg">
        <meta name="bepress_citation_author" content="University of Bamberg">
        <meta name="bepress_citation_author" content="Müller, Anna">
        """)
        let m = AISeLProvider.parseRecord(html: html, url: url)!
        XCTAssertEqual(m.authors.map(\.family), ["Smith", "Müller"])
        XCTAssertEqual(m.ignoredAuthors.map(\.isCertain), [true])
        let authors = Comparator.compare(ref, with: m).fields.first { $0.field == "Authors" }!
        XCTAssertEqual(authors.status, .match, "AISeL itself labels it an institution")
        XCTAssertTrue(authors.note?.contains("University of Bamberg") == true)
    }

    func testAffiliationAppendedToNameIsSplitOff() {
        let html = page("""
        <meta name="bepress_citation_author" content="Smith, John, University of Bamberg">
        <meta name="bepress_citation_author" content="Müller, Anna">
        """)
        let m = AISeLProvider.parseRecord(html: html, url: url)!
        XCTAssertEqual(m.authors.map(\.display), ["John Smith", "Anna Müller"])
        XCTAssertEqual(m.ignoredAuthors.first?.name, "University of Bamberg")
    }

    func testOrganisationRecognisedOnlyByWordingIsAmber() {
        let html = page("""
        <meta name="bepress_citation_author" content="Smith, John">
        <meta name="bepress_citation_author" content="SAP SE">
        <meta name="bepress_citation_author" content="Müller, Anna">
        """)
        let m = AISeLProvider.parseRecord(html: html, url: url)!
        XCTAssertEqual(m.authors.count, 2)
        XCTAssertEqual(m.ignoredAuthors.map(\.isCertain), [false])
        XCTAssertEqual(Comparator.compare(ref, with: m).fields.first { $0.field == "Authors" }?.status, .unconfirmed)
    }

    func testPeopleWithKeywordSurnamesStayAuthors() {
        XCTAssertFalse(Affiliations.looksLikeOrganization("Bank, Michael"))
        XCTAssertFalse(Affiliations.looksLikeOrganization("Center, Mary J."))
        XCTAssertTrue(Affiliations.looksLikeOrganization("Bamberg, University of"))
        XCTAssertTrue(Affiliations.looksLikeOrganization("Technische Universität München"))
        XCTAssertFalse(Affiliations.looksLikeOrganization("van der Aalst, Wil M. P."))
    }
}
