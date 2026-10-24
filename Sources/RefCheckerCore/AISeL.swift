import Foundation

/// AIS eLibrary (aisel.aisnet.org, a bepress Digital Commons repository).
///
/// Most AIS conference papers (ICIS, ECIS, AMCIS, PACIS, WI, …) have no DOI, so
/// Crossref does not know them, and Crossref/OpenAlex sometimes attribute them to
/// the Journal of the AIS. The AISeL landing pages carry the authoritative
/// citation metadata, and the URL path names the conference and year
/// (e.g. aisel.aisnet.org/icis2020/…).
public struct AISeLProvider: Sendable {
    public static let name = "AIS eLibrary"
    static let host = "aisel.aisnet.org"
    let http: HTTPClient

    struct Conference: Sendable {
        let name: String
        let abbreviation: String
        var aliases: [String] = []
    }

    /// Keyed by the letters of the AISeL collection slug ("icis" in "icis2020").
    static let conferences: [String: Conference] = [
        "icis": Conference(name: "International Conference on Information Systems", abbreviation: "ICIS"),
        "ecis": Conference(name: "European Conference on Information Systems", abbreviation: "ECIS"),
        "amcis": Conference(name: "Americas Conference on Information Systems", abbreviation: "AMCIS"),
        "pacis": Conference(name: "Pacific Asia Conference on Information Systems", abbreviation: "PACIS"),
        "wi": Conference(name: "International Conference on Wirtschaftsinformatik", abbreviation: "WI",
                         aliases: ["Internationale Tagung Wirtschaftsinformatik", "Wirtschaftsinformatik"]),
        "acis": Conference(name: "Australasian Conference on Information Systems", abbreviation: "ACIS"),
        "mcis": Conference(name: "Mediterranean Conference on Information Systems", abbreviation: "MCIS"),
        "ukais": Conference(name: "UK Academy for Information Systems Conference", abbreviation: "UKAIS"),
        "bled": Conference(name: "Bled eConference", abbreviation: "Bled"),
        "confirm": Conference(name: "International Conference on Information Resources Management", abbreviation: "CONF-IRM"),
        "sais": Conference(name: "Southern Association for Information Systems Conference", abbreviation: "SAIS"),
        "mwais": Conference(name: "Midwest Association for Information Systems Conference", abbreviation: "MWAIS"),
        "whiceb": Conference(name: "Wuhan International Conference on e-Business", abbreviation: "WHICEB"),
        "iceb": Conference(name: "International Conference on Electronic Business", abbreviation: "ICEB"),
        "sigdsa": Conference(name: "SIGDSA Symposium", abbreviation: "SIGDSA"),
        "treos_amcis": Conference(name: "Americas Conference on Information Systems (TREOs)", abbreviation: "AMCIS")
    ]

    private static let slugRx = NSRegularExpression("^([a-z_]+?)[-_]?(\\d{4})")
    private static let aiselURLRx = NSRegularExpression("https?://aisel\\.aisnet\\.org/[^\\s\"'<>]+", options: [.caseInsensitive])
    private static let mentionRx = NSRegularExpression(
        "\\b(ICIS|ECIS|AMCIS|PACIS|ACIS|MCIS|UKAIS|WHICEB|ICEB|CONF-IRM|AISeL|Wirtschaftsinformatik|Bled eConference)\\b|" +
        "AIS Electronic Library|aisel\\.aisnet\\.org|Conferences? on Information Systems|Information Systems Conference",
        options: [.caseInsensitive])
    private static let aisVenueRx = NSRegularExpression(
        "association for information systems|ais electronic library|aisel|communications of the ais|journal of the ais",
        options: [.caseInsensitive])
    private static let yearRx = NSRegularExpression("(1[89]|20)\\d{2}")

    // MARK: Classification

    public static func isAISeLURL(_ s: String) -> Bool {
        URL(string: s)?.host?.lowercased().hasSuffix(host) == true
    }

    /// Conference venue, aliases and year derived from an AISeL URL, or nil for journals/unknown collections.
    public static func conference(forURL s: String) -> (venue: String, aliases: [String], year: String)? {
        guard isAISeLURL(s), let url = URL(string: s),
              let slug = url.pathComponents.dropFirst().first?.lowercased(),
              let m = slugRx.firstMatch(in: slug),
              let key = slug.substring(with: m.range(at: 1)), let year = slug.substring(with: m.range(at: 2)),
              let conf = conferences[key] ?? conferences[key.trimmingCharacters("_")] else { return nil }
        let venue = "\(conf.name) (\(conf.abbreviation) \(year))"
        let aliases = ["\(conf.abbreviation) \(year) Proceedings", "\(conf.abbreviation) \(year)", conf.name]
            + conf.aliases + [conf.abbreviation]
        return (venue, aliases, year)
    }

    /// The reference cites an AIS conference or the AIS eLibrary.
    public static func mentionsAIS(_ ref: ParsedReference) -> Bool {
        mentionRx.firstMatch(in: ref.raw) != nil
    }

    /// The record names an AIS outlet (often wrongly the Journal of the AIS for conference papers).
    public static func hasAISVenue(_ meta: RetrievedMetadata) -> Bool {
        [meta.venue, meta.publisher].compactMap { $0 }.contains { aisVenueRx.firstMatch(in: $0) != nil }
            || meta.links.contains(where: isAISeLURL)
    }

    public static func urls(in ref: ParsedReference) -> [String] {
        aiselURLRx.allMatches(in: ref.raw).compactMap { ref.raw.substring(with: $0.range)?.trimmingCharacters(".,;)") }
    }

    // MARK: Lookup

    /// Reads the citation meta tags of an AISeL landing page.
    public func record(at urlString: String) async throws -> RetrievedMetadata? {
        guard let url = URL(string: urlString), !url.path.contains("viewcontent.cgi"),
              let html = try await http.text(url) else { return nil }
        return Self.parseRecord(html: html, url: urlString)
    }

    /// The words to search for: the parsed title, else the longest sentence of the reference.
    static func query(for ref: ParsedReference) -> String? {
        if let title = ref.title, title.count >= 10 { return title }
        return ReferenceParser.segments(ref.raw)
            .filter { $0.split(separator: " ").count >= 4 && !mentionsAISVenueText($0) }
            .max { $0.count < $1.count }
    }

    private static func mentionsAISVenueText(_ s: String) -> Bool { mentionRx.firstMatch(in: s) != nil }

    /// Searches for the paper's AISeL page: the AISeL site search (title phrase, then plain words),
    /// then a web search restricted to aisel.aisnet.org. Reads the top hits' landing pages.
    /// Returns the records and a description of every route tried, for the card's notes.
    public func search(_ ref: ParsedReference) async throws -> (records: [RetrievedMetadata], routes: [String]) {
        guard let q = Self.query(for: ref) else { return ([], ["no title to search for"]) }
        var routes: [String] = []
        var links: [String] = []
        let attempts: [(String, URL)] = [
            ("AISeL site search (title)", HTTPClient.url("https://\(Self.host)/do/search/", [("q", "title:\"\(q)\""), ("start", "0")])),
            ("AISeL site search (words)", HTTPClient.url("https://\(Self.host)/do/search/", [("q", q), ("start", "0")])),
            ("web search on aisel.aisnet.org", HTTPClient.url("https://html.duckduckgo.com/html/", [("q", "site:\(Self.host) \"\(q)\"")]))
        ]
        for (name, url) in attempts {
            let html = (try? await http.text(url)) ?? nil
            let found = html.map { Self.paperLinks(inSearchPage: Self.decodeRedirects($0)) } ?? []
            routes.append("\(name): " + (html == nil ? "not reachable" : "\(found.count) hit(s)"))
            links += found.filter { !links.contains($0) }
            if !found.isEmpty { break }
        }
        var records: [RetrievedMetadata] = []
        for link in links.prefix(3) {
            if let m = try await record(at: link) { records.append(m) }
        }
        return (records, routes)
    }

    private static let redirectRx = NSRegularExpression("uddg=([^&\"'>]+)")

    /// Search engines wrap result links ("/l/?uddg=https%3A%2F%2Faisel…"); unwrap them.
    static func decodeRedirects(_ html: String) -> String {
        let decoded = redirectRx.allMatches(in: html).compactMap { html.substring(with: $0.range(at: 1))?.removingPercentEncoding }
        return html + "\n" + decoded.joined(separator: "\n")
    }

    static func paperLinks(inSearchPage html: String) -> [String] {
        var seen = Set<String>()
        return aiselURLRx.allMatches(in: html).compactMap { m -> String? in
            guard let link = html.substring(with: m.range), let url = URL(string: link) else { return nil }
            let parts = url.pathComponents.dropFirst()
            // Papers live at /<collection>/…/<number>; skip search, assets and PDF links.
            guard parts.count >= 2, let first = parts.first, !["do", "cgi", "assets", "ir-style.css"].contains(first),
                  let last = parts.last, Int(last) != nil, seen.insert(link).inserted else { return nil }
            return link
        }
    }

    private static let metaRx = NSRegularExpression("<meta\\s[^>]*>", options: [.caseInsensitive])
    private static let nameAttrRx = NSRegularExpression("\\b(?:name|property)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive])
    private static let contentAttrRx = NSRegularExpression("\\bcontent\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive])

    static func metaTags(_ html: String) -> [(name: String, content: String)] {
        metaRx.allMatches(in: html).compactMap { m in
            guard let tag = html.substring(with: m.range),
                  let n = nameAttrRx.firstMatch(in: tag), let c = contentAttrRx.firstMatch(in: tag) else { return nil }
            let name = tag.substring(with: n.range(at: 1)) ?? tag.substring(with: n.range(at: 2)) ?? ""
            let content = tag.substring(with: c.range(at: 1)) ?? tag.substring(with: c.range(at: 2)) ?? ""
            return (name.lowercased(), Markup.clean(content))
        }
    }

    static func parseRecord(html: String, url: String) -> RetrievedMetadata? {
        let tags = metaTags(html)
        func values(_ keys: [String]) -> [String] {
            for key in keys {
                let v = tags.filter { $0.name == key }.map(\.content).filter { !$0.isEmpty }
                if !v.isEmpty { return v }
            }
            return []
        }
        func value(_ keys: String...) -> String? { values(keys).first }

        guard let title = value("bepress_citation_title", "citation_title", "dc.title") else { return nil }
        // AISeL sometimes lists affiliations as co-authors; its own institution tags tell them apart.
        let institutions = tags.filter { ["bepress_citation_author_institution", "citation_author_institution"].contains($0.name) }
            .map(\.content)
        let separated = Affiliations.separate(values(["bepress_citation_author", "citation_author", "dc.creator"]),
                                              institutions: institutions, provider: name)
        let authors = separated.authors.map { entry -> Author in
            let parts = entry.components(separatedBy: ",").map { $0.trimmed }
            if parts.count >= 2, !parts[0].isEmpty { return Author(given: parts[1].nilIfEmpty, family: parts[0]) }
            return DBLPProvider.author(from: entry)
        }
        let dates = [value("bepress_citation_date", "citation_publication_date", "citation_date", "dc.date"),
                     value("bepress_citation_online_date", "citation_online_date")]
            .compactMap { date -> String? in
                guard let date, let m = yearRx.firstMatch(in: date) else { return nil }
                return date.substring(with: m.range)
            }

        let journal = value("bepress_citation_journal_title", "citation_journal_title")
        let series = value("bepress_citation_series_title", "citation_conference_title", "citation_conference",
                           "bepress_citation_conference")
        var venue = journal ?? series
        var aliases = [series].compactMap { $0 }.filter { $0 != venue }
        var year = dates.first
        var type = journal != nil ? "journal-article" : "proceedings-article"
        if let conf = conference(forURL: url) {
            // The collection in the URL is authoritative for conference papers.
            venue = conf.venue
            aliases = [series].compactMap { $0 } + conf.aliases
            year = year ?? conf.year
            type = "proceedings-article"
        }
        let first = value("bepress_citation_firstpage", "citation_firstpage")
        let last = value("bepress_citation_lastpage", "citation_lastpage")
        let pages = first.map { f in last.map { $0 != f ? "\(f)-\($0)" : f } ?? f }

        var record = RetrievedMetadata(
            provider: name, title: title, authors: authors,
            year: year, alternativeYears: Array(Set(dates)).filter { $0 != year }.sorted(),
            venue: venue, venueAliases: aliases,
            volume: value("bepress_citation_volume", "citation_volume"),
            issue: value("bepress_citation_issue", "citation_issue"),
            pages: pages,
            doi: value("bepress_citation_doi", "citation_doi").map { d in
                d.range(of: "doi.org/").map { String(d[$0.upperBound...]) } ?? d
            },
            publisher: "Association for Information Systems",
            type: type, url: url, links: [url])
        record.ignoredAuthors = separated.ignored
        (record.pages, record.articleNumber) = ArticleNumbers.split(pages: pages, articleNumber: nil)
        return record
    }
}
