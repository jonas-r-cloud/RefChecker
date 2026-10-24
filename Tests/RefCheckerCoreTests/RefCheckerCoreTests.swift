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

final class CrossrefAffiliationTests: XCTestCase {
    let correct = "Leidner, D. E., & Tona, O. (2021). A Thought-Gear Model of Theorizing from Literature. Journal of the Association for Information Systems, 22(4), 874–892. https://doi.org/10.17705/1jais.00683"
    let incorrect = "Dorothy E. Leidner, Baylor University, USA, Olgerta Tona, University of Gothenburg, Sweden (2021). A Thought-Gear Model of Theorizing from Literature. Journal of the Association for Information Systems, 22(4), 874-892. https://doi.org/10.17705/1jais.00683"

    /// Crossref record of 10.17705/1jais.00683 with affiliations deposited as authors.
    func record(_ authors: [[String: Any]]) -> RetrievedMetadata {
        CSLParser.metadata([
            "title": ["A Thought-Gear Model of Theorizing from Literature"],
            "author": authors,
            "issued": ["date-parts": [[2021]]],
            "container-title": ["Journal of the Association for Information Systems"],
            "volume": "22", "issue": "4", "page": "874-892", "DOI": "10.17705/1jais.00683"
        ], provider: "Crossref")!
    }

    let asNames: [[String: Any]] = [
        ["given": "Dorothy E.", "family": "Leidner"], ["name": "Baylor University, USA"],
        ["given": "Olgerta", "family": "Tona"], ["name": "University of Gothenburg, Sweden"]
    ]
    let splitIntoTwo: [[String: Any]] = [
        ["given": "Dorothy E.", "family": "Leidner"], ["family": "Baylor University"], ["family": "USA"],
        ["given": "Olgerta", "family": "Tona"], ["given": "University of Gothenburg", "family": "Sweden"]
    ]

    func testAffiliationsAreSeparatedFromCrossrefAuthors() {
        for authors in [asNames, splitIntoTwo] {
            let m = record(authors)
            XCTAssertEqual(m.authors.map(\.family), ["Leidner", "Tona"])
            XCTAssertTrue(m.ignoredAuthors.allSatisfy(\.isCertain), "\(m.ignoredAuthors)")
        }
    }

    func testCorrectReferenceIsGreen() {
        let ref = ReferenceParser.parse(correct, label: "1", id: 0)
        let fields = Dictionary(uniqueKeysWithValues: Comparator.compare(ref, with: record(asNames)).fields.map { ($0.field, $0.status) })
        XCTAssertEqual(fields["Authors"], .match)
        XCTAssertEqual(fields["Title"], .match)
        XCTAssertEqual(fields["DOI"], .match)
    }

    func testReferenceListingAffiliationsAsAuthorsIsRed() {
        let ref = ReferenceParser.parse(incorrect, label: "1", id: 0)
        let comparison = Comparator.compare(ref, with: record(asNames))
        let authors = comparison.fields.first { $0.field == "Authors" }!
        XCTAssertEqual(authors.status, .mismatch)
        XCTAssertTrue(authors.note?.contains("“Baylor University, USA”, “University of Gothenburg, Sweden”") == true, authors.note ?? "")
        XCTAssertTrue(comparison.highlights.contains { $0.status == .mismatch && $0.field == "Authors" })
    }

    func testSoleCorporateAuthorIsNotFlagged() {
        XCTAssertEqual(Affiliations.inAuthorList("American Psychological Association"), [])
        XCTAssertEqual(Affiliations.inAuthorList("Dorothy E. Leidner, Baylor University, USA, Olgerta Tona"),
                       ["Baylor University, USA"])
    }
}

final class ArticleNumberTests: XCTestCase {
    func testPageFieldHoldingAnArticleNumberIsReclassified() {
        XCTAssertEqual(ArticleNumbers.split(pages: "122886", articleNumber: nil).articleNumber, "122886")
        XCTAssertEqual(ArticleNumbers.split(pages: "e1234", articleNumber: nil).articleNumber, "e1234")
        XCTAssertEqual(ArticleNumbers.split(pages: "45-67", articleNumber: nil).pages, "45-67")
        XCTAssertEqual(ArticleNumbers.split(pages: "100582", articleNumber: "100582").pages, nil)
    }

    func fields(_ reference: String, _ item: [String: Any]) -> [String: MatchStatus] {
        let ref = ReferenceParser.parse(reference, label: "1", id: 0)
        let meta = CSLParser.metadata(item, provider: "Crossref")!
        return Dictionary(uniqueKeysWithValues: Comparator.compare(ref, with: meta).fields.map { ($0.field, $0.status) })
    }

    func testVolumeAndArticleNumber() {
        let f = fields("Sheng, L., Gu, Z., & Chang, F. (2024). A novel integration strategy for uncertain knowledge in group decision-making with artificial opinions: A DSFIT-SOA-DEMATEL approach. Expert Systems with Applications, 243, 122886. https://doi.org/10.1016/j.eswa.2023.122886", [
            "title": ["A novel integration strategy for uncertain knowledge in group decision-making with artificial opinions: A DSFIT-SOA-DEMATEL approach"],
            "author": [["given": "Lei", "family": "Sheng"], ["given": "Zhen", "family": "Gu"], ["given": "Fei", "family": "Chang"]],
            "issued": ["date-parts": [[2024]]], "container-title": ["Expert Systems with Applications"],
            "volume": "243", "page": "122886", "DOI": "10.1016/j.eswa.2023.122886"])
        XCTAssertEqual(f["Volume"], .match)
        XCTAssertEqual(f["Article no."], .match)
        XCTAssertNil(f["Pages"])
        XCTAssertNil(f["Issue"])
    }

    func testVolumeIssueAndArticleNumber() {
        let f = fields("Leonardi, P. M. (2025). Homo agenticus in the age of agentic AI: Agency loops, power displacement, and the circulation of responsibility. Information and Organization, 35(3), 100582. https://doi.org/10.1016/j.infoandorg.2025.100582", [
            "title": ["Homo agenticus in the age of agentic AI: Agency loops, power displacement, and the circulation of responsibility"],
            "author": [["given": "Paul M.", "family": "Leonardi"]],
            "issued": ["date-parts": [[2025]]], "container-title": ["Information and Organization"],
            "volume": "35", "issue": "3", "article-number": "100582", "DOI": "10.1016/j.infoandorg.2025.100582"])
        XCTAssertEqual(f["Volume"], .match)
        XCTAssertEqual(f["Issue"], .match)
        XCTAssertEqual(f["Article no."], .match)
    }
}

final class BlankLineSplitTests: XCTestCase {
    func testEmptyLineForcesSplitInNumberedList() {
        let entries = ReferenceSplitter.split("""
        [1] A. Smith, “First paper,” 2020.

        B. Jones, “Glued paper,” 2019.
        [2] C. Doe, “Second paper,” 2021.
        """)
        XCTAssertEqual(entries.map(\.label), ["1", "1b", "2"])
    }

    func testEmptyLineForcesSplitInAuthorYearList() {
        let entries = ReferenceSplitter.split("""
        Smith, J. (2020). Learning to rank. Journal of Testing, 12(3), 45–67. Zhang, L. (2019).
        Another paper. Conference on Things.

        Doe, A. (2018). Third paper. Some Journal, 1, 2–3.
        """)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[1].text.hasPrefix("Doe, A."))
    }

    func testFormattedListSplitsBackIdentically() {
        let original = ReferenceSplitter.split("""
        [1] A. Smith and B. Jones, “A study of infor-
        mation retrieval,” in Proc. SIGIR, 2020.
        [2] C. Doe, “Another title,” 2019.
        """)
        let formatted = ReferenceSplitter.format(original)
        XCTAssertEqual(formatted, "[1] A. Smith and B. Jones, “A study of information retrieval,” in Proc. SIGIR, 2020.\n\n[2] C. Doe, “Another title,” 2019.")
        XCTAssertEqual(ReferenceSplitter.split(formatted).map(\.text), original.map(\.text))
    }
}

final class ExtractionReportTests: XCTestCase {
    func testCompleteNumberedList() {
        let section = """
        [1] A. Smith, “First paper,” in Proc. X, 2020.
        [2] B. Jones, “Second paper,” Journal Y, 2021.
        [3] C. Doe, “Third paper,” Journal Z, 2019.
        """
        let entries = ReferenceSplitter.split(section)
        let report = ExtractionReport.analyze(section: section, entries: entries)
        XCTAssertEqual(report.count, 3)
        XCTAssertTrue(report.isComplete, "\(report.leftovers)")
        XCTAssertEqual(report.numbering?.missing, [])
        XCTAssertTrue(report.suspicious.isEmpty)
    }

    func testGapInNumberingIsReportedNotMerged() {
        let section = """
        [1] A. Smith, “First paper,” in Proc. X, 2020.
        [2] B. Jones, “Second paper,” Journal Y, 2021.
        [4] C. Doe, “Fourth paper,” Journal Z, 2019.
        """
        let entries = ReferenceSplitter.split(section)
        XCTAssertEqual(entries.map(\.label), ["1", "2", "4"])
        let report = ExtractionReport.analyze(section: section, entries: entries)
        XCTAssertEqual(report.numbering?.missing, [3])
        XCTAssertFalse(report.isComplete)
    }

    func testTextBeforeTheFirstReferenceIsALeftover() {
        let section = """
        Proceedings of Something, page header text
        [1] A. Smith, “First paper,” in Proc. X, 2020.
        [2] B. Jones, “Second paper,” Journal Y, 2021.
        """
        let report = ExtractionReport.analyze(section: section, entries: ReferenceSplitter.split(section))
        XCTAssertEqual(report.leftovers.count, 1)
    }

    func testTwoReferencesRunTogetherAreFlagged() {
        let entries = [ReferenceSplitter.Entry(label: "1", text: "Smith, J. (2020). Learning to rank. Journal of Testing, 12(3), 45–67. Doe, A. (2018). Third paper. Some Journal, 1, 2–3.")]
        let report = ExtractionReport.analyze(section: entries[0].text, entries: entries)
        XCTAssertEqual(report.suspicious.first?.label, "1")
    }
}

final class CitationIndexTests: XCTestCase {
    func testNumberedCitationsIncludingRangesAndPages() {
        let refs = (1...4).map { ReferenceParser.parse("A. Author, “Paper \($0),” Journal, 2020.", label: "\($0)", id: $0 - 1) }
        let body = "As shown in [1], and later [1, 3–4]. See also [2, p. 7]. A missing one [6]. Not a citation [sic]."
        let index = CitationIndex.build(body: body, references: refs)
        XCTAssertEqual(index.style, .numbered)
        XCTAssertEqual(index.count(for: 0), 2)
        XCTAssertEqual(index.count(for: 1), 1)
        XCTAssertEqual(index.count(for: 2), 1)
        XCTAssertEqual(index.count(for: 3), 1)
        XCTAssertEqual(index.unknownNumbers, [6])
    }

    func testAuthorYearCitations() {
        let refs = [
            ReferenceParser.parse("Smith, J., & Doe, A. (2020). Learning to rank. Journal of Testing, 12(3), 45–67.", label: "1", id: 0),
            ReferenceParser.parse("Jones, B. (2019). Another paper. Journal Y, 1, 1–2.", label: "2", id: 1),
            ReferenceParser.parse("Leidner, D. E., & Tona, O. (2021). A Thought-Gear Model. JAIS, 22(4), 874–892.", label: "3", id: 2)
        ]
        let body = """
        Smith and Doe (2020) argue … as others note (Jones, 2019; Smith & Doe, 2020).
        Later, Smith et al. (2019) – a different year – and Jones (2020) are not these references.
        """
        let index = CitationIndex.build(body: body, references: refs)
        XCTAssertEqual(index.style, .authorYear)
        XCTAssertEqual(index.count(for: 0), 2)
        XCTAssertEqual(index.count(for: 1), 1)
        XCTAssertEqual(index.count(for: 2), 0)
    }

    func testBodyAndSectionAreSeparated() {
        let paper = "Introduction\nAs [1] shows.\nReferences\n[1] A. Smith, “Paper,” 2020."
        let parts = ReferenceSectionExtractor.split(paper)
        XCTAssertEqual(parts?.body, "Introduction\nAs [1] shows.")
        XCTAssertEqual(parts?.section, "[1] A. Smith, “Paper,” 2020.")
    }
}

final class OptionsAndAISeLQueryTests: XCTestCase {
    func testMissingArticleNumberCanBeAccepted() {
        let ref = ReferenceParser.parse("Sheng, L. (2024). A novel integration strategy. Expert Systems with Applications, 243.", label: "1", id: 0)
        let meta = RetrievedMetadata(provider: "Crossref", title: "A novel integration strategy",
                                     authors: [Author(given: "Lei", family: "Sheng")], year: "2024",
                                     venue: "Expert Systems with Applications", volume: "243")
        var m = meta
        m.articleNumber = "122886"
        let strict = Comparator.compare(ref, with: m).fields.first { $0.field == "Article no." }
        XCTAssertEqual(strict?.status, .missing)
        let lenient = Comparator.compare(ref, with: m, options: ComparisonOptions(requireArticleNumber: false)).fields
        XCTAssertNil(lenient.first { $0.field == "Article no." })
    }

    func testConferenceReferenceWithoutLinkIsRecognisedAndSearchable() {
        let ref = ReferenceParser.parse("Smith, J. (2019). Digital nudging. In Proceedings of the 27th European Conference on Information Systems, Stockholm.",
                                        label: "1", id: 0)
        XCTAssertTrue(AISeLProvider.mentionsAIS(ref))
        XCTAssertEqual(AISeLProvider.query(for: ref), "Digital nudging")
        let journal = ReferenceParser.parse("Leidner, D. E., & Tona, O. (2021). A Thought-Gear Model of Theorizing from Literature. Journal of the Association for Information Systems, 22(4), 874–892.",
                                            label: "2", id: 1)
        XCTAssertFalse(AISeLProvider.mentionsAIS(journal), "journal references are not conference searches")
    }

    func testSearchEngineRedirectLinksAreUnwrapped() {
        let html = #"<a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Faisel.aisnet.org%2Fecis2019_rp%2F12%2F&rut=x">"#
        XCTAssertEqual(AISeLProvider.paperLinks(inSearchPage: AISeLProvider.decodeRedirects(html)),
                       ["https://aisel.aisnet.org/ecis2019_rp/12/"])
    }
}

final class UncitedIsIssueTests: XCTestCase {
    func testUncitedReferenceBecomesAnIssue() {
        let refs = (1...2).map { ReferenceParser.parse("A. Author, “Paper \($0),” Journal, 2020.", label: "\($0)", id: $0 - 1) }
        let index = CitationIndex.build(body: "Only [1] is cited.", references: refs)
        XCTAssertEqual(index.adjusted(.verified, for: 0), .verified)
        XCTAssertEqual(index.adjusted(.verified, for: 1), .issues(1))
        XCTAssertEqual(index.adjusted(.needsReview(2), for: 1), .issues(1))
        XCTAssertEqual(index.adjusted(.issues(2), for: 1), .issues(3))
        XCTAssertEqual(index.adjusted(.notFound, for: 1), .notFound)

        let results = Dictionary(uniqueKeysWithValues: refs.map {
            ($0.id, ReferenceResult(reference: $0, metadata: nil, fields: [], highlights: [], verdict: .verified, notes: []))
        })
        let html = HTMLReport.render(references: refs, results: results, source: nil, citations: index)
        XCTAssertTrue(html.contains("1 verified"))
        XCTAssertTrue(html.contains("1 with issues"))
        XCTAssertTrue(html.contains("Not cited in text (issue)"))
    }
}

final class JournalAbbreviationTests: XCTestCase {
    func testISO4Abbreviations() {
        XCTAssertEqual(ISO4.abbreviate("Expert Systems with Applications"), "Expert Syst. Appl.")
        XCTAssertEqual(ISO4.abbreviate("Journal of the Association for Information Systems"), "J. Assoc. Inf. Syst.")
        XCTAssertEqual(ISO4.abbreviate("MIS Quarterly"), "MIS Q.")
        XCTAssertEqual(ISO4.abbreviate("Information and Organization"), "Inf. Organ.")
        XCTAssertEqual(ISO4.abbreviate("Information Systems Research"), "Inf. Syst. Res.")
        XCTAssertEqual(ISO4.abbreviate("Decision Support Systems"), "Decis. Support Syst.")
        XCTAssertEqual(ISO4.abbreviate("International Journal of Human-Computer Studies"), "Int. J. Hum.-Comput. Stud.")
        XCTAssertNil(ISO4.abbreviate("Nature"), "single-word titles are not abbreviated")
    }

    func venueStatus(_ reference: String, venue: String, official: [VenueAbbreviation] = []) -> FieldComparison? {
        let ref = ReferenceParser.parse(reference, label: "1", id: 0)
        var meta = RetrievedMetadata(provider: "Crossref", title: "A novel integration strategy",
                                     authors: [Author(given: "Lei", family: "Sheng")], year: "2024", venue: venue)
        meta.venueAbbreviations = official
        return Comparator.compare(ref, with: meta).fields.first { $0.field == "Venue" }
    }

    func testOfficialAbbreviationIsGreen() {
        let f = venueStatus("Sheng, L. (2024). A novel integration strategy. Expert Syst. Appl., 243, 122886.",
                            venue: "Expert Systems with Applications",
                            official: [VenueAbbreviation("Expert Syst. Appl.", .crossref)])
        XCTAssertEqual(f?.status, .match)
        XCTAssertTrue(f?.note?.contains("Crossref short title") == true)
    }

    func testNLMStyleWithoutFullStopsMatches() {
        let f = venueStatus("Sheng L. A novel integration strategy. Expert Syst Appl. 2024;243:122886.",
                            venue: "Expert Systems with Applications",
                            official: [VenueAbbreviation("Expert Syst Appl", .nlm)])
        XCTAssertEqual(f?.status, .match)
    }

    func testGeneratedISO4AbbreviationIsAmber() {
        let f = venueStatus("Sheng, L. (2024). A novel integration strategy. Expert Syst. Appl., 243, 122886.",
                            venue: "Expert Systems with Applications")
        XCTAssertEqual(f?.status, .unconfirmed)
        XCTAssertTrue(f?.note?.contains("ISO 4") == true)
    }

    func testAbbreviationMustNotMatchInsideALongerOne() {
        // "Inf. Syst." (Information Systems) must not match "Inf. Syst. Res." (Information Systems Research).
        let f = venueStatus("Sheng, L. (2024). A novel integration strategy. Inf. Syst. Res., 35(3), 100–120.",
                            venue: "Information Systems",
                            official: [VenueAbbreviation("Inf. Syst.", .issn)])
        XCTAssertNotEqual(f?.status, .match)
        XCTAssertNotEqual(f?.status, .unconfirmed)
    }
}

final class LinksAreNotVenuesTests: XCTestCase {
    let amr = "Samantha A. Conroy and Anne M. O’Leary-Kelly. 2014. Letting Go and Moving On: Work-Related Identity Loss and Recovery. Acad. Manage. Rev. 39, 1 (January 2014), 67–87. https://doi.org/10.5465/amr.2011.0396"

    func meta(_ abbreviations: [VenueAbbreviation]) -> RetrievedMetadata {
        var m = RetrievedMetadata(provider: "doi.org", title: "Letting Go and Moving On: Work-Related Identity Loss and Recovery",
                                  authors: [Author(given: "Samantha A.", family: "Conroy"), Author(given: "Anne M.", family: "O'Leary-Kelly")],
                                  year: "2014", venue: "Academy of Management Review", volume: "39", issue: "1", pages: "67-87",
                                  doi: "10.5465/amr.2011.0396")
        m.venueAbbreviations = abbreviations
        return m
    }

    func testDOIIsNotTakenForTheVenue() {
        let ref = ReferenceParser.parse(amr, label: "16", id: 0)
        let venue = Comparator.compare(ref, with: meta([VenueAbbreviation("AMR", .crossref)])).fields.first { $0.field == "Venue" }
        // "amr" in the DOI must not count; the earlier-LTWA form "Acad. Manage. Rev." is found instead (generated → amber).
        XCTAssertEqual(venue?.original, "Acad. Manage. Rev")
        XCTAssertEqual(venue?.status, .unconfirmed)
        // The DOI itself is still compared.
        XCTAssertEqual(Comparator.compare(ref, with: meta([])).fields.first { $0.field == "DOI" }?.status, .match)
    }

    func testISSNRegisterAbbreviationMakesItGreen() {
        let ref = ReferenceParser.parse(amr, label: "16", id: 0)
        let venue = Comparator.compare(ref, with: meta([VenueAbbreviation("Acad. Manage. Rev.", .issn)])).fields.first { $0.field == "Venue" }
        XCTAssertEqual(venue?.status, .match)
    }

    func testISO4Variants() {
        XCTAssertEqual(ISO4.variants("Academy of Management Review"), ["Acad. Manag. Rev.", "Acad. Manage. Rev."])
    }

    func testAISeLLinkIsNotTakenForTheConference() {
        let ref = ReferenceParser.parse("Smith, J. (2020). Digital nudging. In Proceedings of the European Conference on Information Systems. https://aisel.aisnet.org/icis2020/track/3/",
                                        label: "1", id: 0)
        let m = RetrievedMetadata(provider: "AIS eLibrary", title: "Digital nudging", authors: [Author(given: "John", family: "Smith")],
                                  year: "2020", venue: "International Conference on Information Systems (ICIS 2020)",
                                  venueAliases: ["ICIS 2020 Proceedings", "ICIS 2020", "International Conference on Information Systems", "ICIS"])
        let venue = Comparator.compare(ref, with: m).fields.first { $0.field == "Venue" }
        XCTAssertEqual(venue?.status, .mismatch, "the reference names ECIS; icis2020 in the link must not count")
    }

    func testMaskingKeepsOffsets() {
        let raw = "Title. J. Test. https://doi.org/10.1/abc.123 end"
        let text = Comparator.matchingText(raw)
        XCTAssertEqual(text.characters.count, raw.count)
        XCTAssertNil(text.findWords("abc"))
        XCTAssertNotNil(text.findWords("end"))
    }
}
