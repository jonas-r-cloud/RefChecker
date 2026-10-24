import Foundation

/// Journal title abbreviations from the NLM Catalog (NCBI E-utilities): the MEDLINE abbreviation
/// (MedlineTA) and the ISO abbreviation NLM records. Looked up by ISSN, else by exact title.
public struct NLMCatalog: Sendable {
    let http: HTTPClient
    private let cache = Cache()

    private actor Cache {
        var entries: [String: [String]] = [:]
        func get(_ key: String) -> [String]? { entries[key] }
        func set(_ key: String, _ value: [String]) { entries[key] = value }
    }

    private static let base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
    private static let abbreviationRx = NSRegularExpression("<(MedlineTA|ISOAbbreviation)>([^<]+)</\\1>")
    private static let titleRx = NSRegularExpression("<TitleMain>\\s*<Title[^>]*>([^<]+)</Title>")

    public func abbreviations(journal: String, issn: [String]) async -> [String] {
        let key = NormalizedText.key(journal)
        if let cached = await cache.get(key) { return cached }
        var found: [String] = []
        // ISSN first: unambiguous. The title search is checked against the record's main title.
        let terms = issn.map { ("\($0)[issn]", false) } + [("\"\(journal)\"[Title]", true)]
        for (term, checkTitle) in terms {
            guard let ids = await search(term), !ids.isEmpty,
                  let xml = try? await http.text(HTTPClient.url(Self.base + "efetch.fcgi",
                                                                [("db", "nlmcatalog"), ("id", ids.prefix(3).joined(separator: ",")), ("retmode", "xml")]))
            else { continue }
            if checkTitle {
                let titles = Self.titleRx.allMatches(in: xml).compactMap { xml.substring(with: $0.range(at: 1)) }
                guard titles.contains(where: { NormalizedText.key($0) == key }) else { continue }
            }
            found = Self.abbreviationRx.allMatches(in: xml).compactMap { xml.substring(with: $0.range(at: 2)).map(Markup.clean) }
            if !found.isEmpty { break }
        }
        let unique = found.reduce(into: [String]()) { list, a in
            if !list.contains(where: { NormalizedText.key($0) == NormalizedText.key(a) }) { list.append(a) }
        }
        await cache.set(key, unique)
        return unique
    }

    private func search(_ term: String) async -> [String]? {
        let url = HTTPClient.url(Self.base + "esearch.fcgi", [("db", "nlmcatalog"), ("term", term), ("retmode", "json"), ("retmax", "3")])
        guard let json = (try? await http.json(url)) as? [String: Any],
              let result = json["esearchresult"] as? [String: Any] else { return nil }
        return result["idlist"] as? [String]
    }
}
