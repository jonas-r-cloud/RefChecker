import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProviderError: LocalizedError {
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let host): return "\(host) answered with HTTP \(code)."
        }
    }
}

struct HTTPClient: Sendable {
    let userAgent: String

    /// GETs JSON. Returns nil for 404; retries on rate limiting and server errors.
    func json(_ url: URL, accept: String = "application/json") async throws -> Any? {
        guard let data = try await data(url, accept: accept) else { return nil }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// GETs an HTML/text page.
    func text(_ url: URL) async throws -> String? {
        guard let data = try await data(url, accept: "text/html,application/xhtml+xml") else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    func data(_ url: URL, accept: String) async throws -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        var lastCode = 0
        for attempt in 0..<3 {
            let (data, response) = try await URLSession.shared.data(for: request)
            lastCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch lastCode {
            case 200..<300:
                return data
            case 404, 400:
                return nil
            case 429, 500...:
                try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (1 << attempt)))
            default:
                throw ProviderError.http(lastCode, url.host ?? "server")
            }
        }
        throw ProviderError.http(lastCode, url.host ?? "server")
    }

    static func url(_ base: String, _ query: [(String, String?)]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        // "+" would be read as a space by the servers.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }
}

public protocol MetadataProvider: Sendable {
    var name: String { get }
    func search(_ reference: ParsedReference) async throws -> [RetrievedMetadata]
}

/// Parses CSL-JSON (doi.org content negotiation) and Crossref REST items, which share most keys.
enum CSLParser {
    static func strings(_ v: Any?) -> [String] {
        if let s = v as? String { return s.nilIfEmpty.map { [Markup.clean($0)] } ?? [] }
        if let a = v as? [Any] { return a.compactMap { ($0 as? String)?.nilIfEmpty }.map(Markup.clean) }
        if let n = v as? NSNumber { return [n.stringValue] }
        return []
    }

    static func string(_ v: Any?) -> String? { strings(v).first }

    static func year(_ v: Any?) -> String? {
        guard let d = v as? [String: Any], let parts = d["date-parts"] as? [[Any]],
              let first = parts.first?.first else { return nil }
        if let n = first as? NSNumber { return n.stringValue }
        return (first as? String)?.nilIfEmpty
    }

    static func metadata(_ item: [String: Any], provider: String) -> RetrievedMetadata? {
        guard let title = string(item["title"]) else { return nil }
        let people = (item["author"] as? [[String: Any]]) ?? (item["editor"] as? [[String: Any]]) ?? []
        let authors = people.compactMap { a -> Author? in
            if let family = (a["family"] as? String)?.nilIfEmpty { return Author(given: a["given"] as? String, family: family) }
            if let name = (a["name"] as? String ?? a["literal"] as? String)?.nilIfEmpty { return Author(given: nil, family: name) }
            return nil
        }
        let issued = year(item["issued"])
        var alternatives = [year(item["published-print"]), year(item["published-online"]), year(item["published"])]
            .compactMap { $0 }
        alternatives = Array(Set(alternatives)).filter { $0 != issued }.sorted()
        let containers = strings(item["container-title"])
        let short = strings(item["short-container-title"]) + strings(item["container-title-short"])
        var doi = string(item["DOI"])
        if doi == nil, let u = string(item["URL"]), let r = u.range(of: "doi.org/") { doi = String(u[r.upperBound...]) }
        return RetrievedMetadata(
            provider: provider,
            title: title,
            subtitle: string(item["subtitle"]),
            authors: authors,
            year: issued ?? alternatives.first,
            alternativeYears: alternatives,
            venue: containers.first,
            venueAliases: Array(containers.dropFirst()) + short + strings(item["event"].flatMap { ($0 as? [String: Any])?["name"] }),
            volume: string(item["volume"]),
            issue: string(item["issue"]),
            pages: string(item["page"]) ?? string(item["article-number"]),
            doi: doi,
            publisher: string(item["publisher"]),
            type: item["type"] as? String,
            url: string(item["URL"]),
            links: strings(item["URL"]) + ((item["link"] as? [[String: Any]]) ?? []).compactMap { $0["URL"] as? String })
    }
}

/// Resolves a DOI at doi.org (works for Crossref, DataCite, mEDRA … DOIs).
public struct DOIResolver: Sendable {
    let http: HTTPClient

    public func lookup(doi: String) async throws -> RetrievedMetadata? {
        let path = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        guard let url = URL(string: "https://doi.org/\(path)"),
              let json = try await http.json(url, accept: "application/vnd.citationstyles.csl+json") as? [String: Any]
        else { return nil }
        var m = CSLParser.metadata(json, provider: "doi.org")
        if m?.doi == nil { m?.doi = doi }
        return m
    }
}

/// Crossref REST API, bibliographic search with the full reference string.
public struct CrossrefProvider: MetadataProvider {
    public let name = "Crossref"
    let http: HTTPClient
    let mailto: String?

    public func search(_ reference: ParsedReference) async throws -> [RetrievedMetadata] {
        let url = HTTPClient.url("https://api.crossref.org/works", [
            ("query.bibliographic", String(reference.raw.prefix(1000))),
            ("rows", "5"),
            ("mailto", mailto)
        ])
        guard let json = try await http.json(url) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { CSLParser.metadata($0, provider: name) }
    }
}

/// DBLP (computer science).
public struct DBLPProvider: MetadataProvider {
    public let name = "DBLP"
    let http: HTTPClient
    private static let disambiguationRx = NSRegularExpression("\\s+\\d{4}$")

    public func search(_ reference: ParsedReference) async throws -> [RetrievedMetadata] {
        let query = reference.title ?? reference.raw
        let url = HTTPClient.url("https://dblp.org/search/publ/api", [
            ("q", String(query.prefix(300))), ("format", "json"), ("h", "5")
        ])
        guard let json = try await http.json(url) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let hits = (result["hits"] as? [String: Any])?["hit"] as? [[String: Any]] else { return [] }
        return hits.compactMap { hit in
            guard let info = hit["info"] as? [String: Any], var title = CSLParser.string(info["title"]) else { return nil }
            if title.hasSuffix(".") { title.removeLast() }
            let authorField = (info["authors"] as? [String: Any])?["author"]
            let authorList: [Any] = (authorField as? [Any]) ?? (authorField.map { [$0] } ?? [])
            let authors = authorList.compactMap { a -> Author? in
                guard let text = (a as? [String: Any])?["text"] as? String ?? a as? String else { return nil }
                return Self.author(from: Self.disambiguationRx.replacing(in: text, with: ""))
            }
            let venues = CSLParser.strings(info["venue"])
            return RetrievedMetadata(
                provider: name, title: title, authors: authors,
                year: CSLParser.string(info["year"]),
                venue: venues.first, venueAliases: Array(venues.dropFirst()),
                volume: CSLParser.string(info["volume"]), issue: CSLParser.string(info["number"]),
                pages: CSLParser.string(info["pages"]), doi: CSLParser.string(info["doi"]),
                publisher: CSLParser.string(info["publisher"]), type: info["type"] as? String,
                url: CSLParser.string(info["ee"]),
                links: CSLParser.strings(info["ee"]) + CSLParser.strings(info["url"]))
        }
    }

    static func author(from fullName: String) -> Author {
        let parts = fullName.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return Author(given: nil, family: fullName) }
        // Keep lowercase particles with the family name ("van der Aalst").
        var split = parts.count - 1
        while split > 1, parts[split - 1].first?.isLowercase == true { split -= 1 }
        return Author(given: parts[..<split].joined(separator: " "), family: parts[split...].joined(separator: " "))
    }
}

/// OpenAlex (all disciplines).
public struct OpenAlexProvider: MetadataProvider {
    public let name = "OpenAlex"
    let http: HTTPClient
    let mailto: String?

    public func search(_ reference: ParsedReference) async throws -> [RetrievedMetadata] {
        let query = reference.title ?? reference.raw
        let url = HTTPClient.url("https://api.openalex.org/works", [
            ("search", String(query.prefix(300))), ("per-page", "5"), ("mailto", mailto)
        ])
        guard let json = try await http.json(url) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { w in
            guard let title = CSLParser.string(w["title"]) ?? CSLParser.string(w["display_name"]) else { return nil }
            let authors = ((w["authorships"] as? [[String: Any]]) ?? []).compactMap { a -> Author? in
                guard let n = (a["author"] as? [String: Any])?["display_name"] as? String ?? a["raw_author_name"] as? String
                else { return nil }
                return DBLPProvider.author(from: n)
            }
            let source = ((w["primary_location"] as? [String: Any])?["source"] as? [String: Any])
            let biblio = w["biblio"] as? [String: Any] ?? [:]
            var pages = CSLParser.string(biblio["first_page"])
            if let p = pages, let last = CSLParser.string(biblio["last_page"]), last != p { pages = "\(p)-\(last)" }
            var doi = CSLParser.string(w["doi"])
            if let d = doi, let r = d.range(of: "doi.org/") { doi = String(d[r.upperBound...]) }
            return RetrievedMetadata(
                provider: name, title: title, authors: authors,
                year: CSLParser.string(w["publication_year"]),
                venue: CSLParser.string(source?["display_name"]),
                venueAliases: CSLParser.strings(source?["abbreviated_title"]),
                volume: CSLParser.string(biblio["volume"]), issue: CSLParser.string(biblio["issue"]),
                pages: pages, doi: doi,
                publisher: CSLParser.string(source?["host_organization_name"]),
                type: w["type"] as? String, url: CSLParser.string(w["id"]),
                links: (((w["locations"] as? [[String: Any]]) ?? []) + [w["primary_location"] as? [String: Any] ?? [:]])
                    .compactMap { $0["landing_page_url"] as? String })
        }
    }
}
