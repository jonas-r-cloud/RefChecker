import Foundation

/// Tells authors from affiliations. Publisher and repository metadata sometimes lists a university
/// or company as a co-author or appends it to an author's name: the AIS eLibrary, and Crossref
/// records of the Journal of the AIS ("Dorothy E. Leidner", "Baylor University, USA", …).
/// References generated from such data repeat the error.
public enum Affiliations {
    private static let wordRx = NSRegularExpression(
        "\\b(universit\\w*|univ\\.|institut\\w*|college|school|department|dept\\.|faculty|fakult\\w*|" +
        "hochschule|fachhochschule|polytechnic|politecnico|laborator\\w*|labs?|center|centre|zentrum|" +
        "research|academy|akademie|ministry|agency|hospital|klinikum|association|society|council|consortium|" +
        "foundation|stiftung|company|corporation|corp\\.|inc\\.?|ltd\\.?|llc|fraunhofer|max planck|helmholtz|leibniz)\\b",
        options: [.caseInsensitive])
    /// Acronyms only count in capitals ("MIT", not the German "mit").
    private static let acronymRx = NSRegularExpression("\\b(ETH|EPFL|KIT|MIT|TU|LMU|RWTH|WU|HEC|INSEAD|IBM|SAP|AG|GmbH|SE)\\b")
    private static let givenNameRx = NSRegularExpression("^(\\p{Lu}[\\p{L}'’\\-]*\\.?)(\\s+\\p{Lu}[\\p{L}'’\\-]*\\.?){0,3}$")
    private static let separatorRx = NSRegularExpression("\\s*(?:,|;|&|\\band\\b)\\s*")

    /// Country names as they follow affiliations ("Baylor University, USA"), as comparison keys.
    static let countries: Set<String> = Set([
        "USA", "U.S.A.", "US", "U.S.", "United States", "United States of America", "UK", "U.K.", "United Kingdom",
        "England", "Scotland", "Wales", "Ireland", "Germany", "Deutschland", "Austria", "Switzerland", "Sweden",
        "Norway", "Denmark", "Finland", "Iceland", "Netherlands", "The Netherlands", "Belgium", "Luxembourg",
        "France", "Spain", "Portugal", "Italy", "Greece", "Poland", "Czech Republic", "Czechia", "Slovakia",
        "Hungary", "Slovenia", "Croatia", "Estonia", "Latvia", "Lithuania", "Romania", "Bulgaria", "Serbia",
        "Turkey", "Türkiye", "Israel", "Canada", "Mexico", "Brazil", "Argentina", "Chile", "Colombia", "Peru",
        "Australia", "New Zealand", "China", "P.R. China", "PR China", "Hong Kong", "Taiwan", "Japan", "Korea",
        "South Korea", "Republic of Korea", "Singapore", "Malaysia", "Indonesia", "Thailand", "Vietnam",
        "Philippines", "India", "Pakistan", "Bangladesh", "Sri Lanka", "Iran", "Saudi Arabia", "UAE",
        "United Arab Emirates", "Qatar", "Egypt", "South Africa", "Nigeria", "Kenya", "Ghana", "Russia", "Ukraine"
    ].map(NormalizedText.key))

    static func hasKeyword(_ s: String) -> Bool {
        wordRx.firstMatch(in: s) != nil || acronymRx.firstMatch(in: s) != nil
    }

    public static func isCountry(_ s: String) -> Bool {
        countries.contains(NormalizedText.key(s))
    }

    /// The last one to three words (or the part after the last comma) name a country.
    static func endsWithCountry(_ s: String) -> Bool {
        if let last = s.components(separatedBy: ",").last, s.contains(","), isCountry(last) { return true }
        let words = s.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return false }
        return (1...min(3, words.count)).contains { isCountry(words.suffix($0).joined(separator: " ")) }
    }

    /// Whether an author entry is worded like an organisation.
    public static func looksLikeOrganization(_ name: String) -> Bool {
        let t = name.trimmed
        if t.contains("@") || t.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        let parts = t.components(separatedBy: ",").map { $0.trimmed }
        // "Bank, Michael" / "Center, Mary": a person whose family name happens to be a keyword.
        if parts.count == 2, parts[0].split(separator: " ").count == 1,
           givenNameRx.firstMatch(in: parts[1]) != nil, !hasKeyword(parts[1]) {
            return false
        }
        if hasKeyword(t) { return true }
        return !t.contains(",") && t.split(separator: " ").count > 5
    }

    /// "Baylor University, USA": an organisation word together with a country is an affiliation for certain.
    static func isCertainOrganization(_ name: String) -> Bool {
        hasKeyword(name) && endsWithCountry(name)
    }

    static func matchesInstitution(_ name: String, _ institutions: [String]) -> Bool {
        let k = NormalizedText.key(name)
        guard k.count >= 4 else { return false }
        return institutions.map(NormalizedText.key).contains { inst in
            inst == k || (k.count >= 8 && inst.contains(k)) || (inst.count >= 8 && k.contains(inst))
        }
    }

    /// Splits raw author entries ("Family, Given") into real authors and ignored affiliations.
    /// `institutions` are strings the provider itself labels as affiliations; removals backed by
    /// them (or by an organisation word plus a country) are certain, others are not.
    public static func separate(_ entries: [String], institutions: [String], provider: String)
        -> (authors: [String], ignored: [IgnoredAuthor]) {
        var authors: [String] = []
        var ignored: [IgnoredAuthor] = []
        for entry in entries.map({ $0.trimmed }) where !entry.isEmpty {
            if matchesInstitution(entry, institutions) {
                ignored.append(IgnoredAuthor(name: entry, isCertain: true,
                                             reason: "\(provider) lists it as an affiliation"))
                continue
            }
            let parts = entry.components(separatedBy: ",").map { $0.trimmed }
            if parts.count >= 3 {
                // "Smith, John, University of Bamberg": affiliation appended to the name.
                let rest = parts[2...].joined(separator: ", ")
                let known = matchesInstitution(rest, institutions)
                if known || looksLikeOrganization(rest) {
                    authors.append("\(parts[0]), \(parts[1])")
                    ignored.append(IgnoredAuthor(name: rest, isCertain: known || isCertainOrganization(rest),
                                                 reason: "appended to the name of \(parts[1]) \(parts[0])"))
                    continue
                }
            }
            if looksLikeOrganization(entry) {
                ignored.append(IgnoredAuthor(name: entry, isCertain: isCertainOrganization(entry),
                                             reason: "worded like an organisation"))
                continue
            }
            authors.append(entry)
        }
        // Never discard everything on wording alone.
        if authors.isEmpty && !ignored.contains(where: \.isCertain) {
            return (entries, [])
        }
        return (authors, ignored)
    }

    /// The same for structured author records (Crossref, doi.org, OpenAlex). Handles affiliations
    /// as separate "authors" (also split into an organisation and a country entry) and affiliations
    /// appended to a family name.
    public static func separate(authors: [Author], institutions: [String], provider: String)
        -> (authors: [Author], ignored: [IgnoredAuthor]) {
        var people: [Author] = []
        var ignored: [IgnoredAuthor] = []
        // (entry, is organisation, certain)
        var classified: [(author: Author, name: String, org: Bool, certain: Bool)] = []

        for var author in authors {
            // family "Leidner, Baylor University, USA"
            let familyParts = author.family.components(separatedBy: ",").map { $0.trimmed }
            if familyParts.count >= 2, let given = author.given?.nilIfEmpty {
                let rest = familyParts.dropFirst().joined(separator: ", ")
                let known = matchesInstitution(rest, institutions)
                if known || looksLikeOrganization(rest) || isCountry(rest) {
                    ignored.append(IgnoredAuthor(name: rest, isCertain: known || isCertainOrganization(rest) || isCountry(rest),
                                                 reason: "appended to the name of \(given) \(familyParts[0])"))
                    author.family = familyParts[0]
                }
            }
            let name = author.given.map { "\($0) \(author.family)" } ?? author.family
            let asEntry = author.given.map { "\(author.family), \($0)" } ?? author.family
            if matchesInstitution(name, institutions) {
                classified.append((author, name, true, true))
            } else if looksLikeOrganization(asEntry) || isCountry(name) {
                classified.append((author, name, true, isCertainOrganization(name)))
            } else {
                classified.append((author, name, false, false))
            }
        }
        // "Baylor University" followed by a separate "USA" entry: both are certainly an affiliation.
        for i in classified.indices where isCountry(classified[i].name) {
            if i > 0, classified[i - 1].org, hasKeyword(classified[i - 1].name) {
                classified[i - 1].certain = true
                classified[i].certain = true
            }
        }
        for c in classified {
            if c.org {
                ignored.append(IgnoredAuthor(name: c.name, isCertain: c.certain,
                                             reason: c.certain ? "an affiliation listed as author by \(provider)"
                                                               : "worded like an organisation"))
            } else {
                people.append(c.author)
            }
        }
        if people.isEmpty && !ignored.contains(where: \.isCertain) {
            return (authors, [])
        }
        return (people, ignored)
    }

    /// Affiliations written into a reference's author list, e.g. "Dorothy E. Leidner, Baylor University, USA,
    /// Olgerta Tona, …" → ["Baylor University, USA"]. Only multi-word organisation names count, so a
    /// person called "Center" is not mistaken for one. A corporate author standing alone (e.g. "American
    /// Psychological Association") is not reported unless `ignored` (affiliations the record itself set
    /// aside) names it or it carries a country.
    public static func inAuthorList(_ authorsText: String?, ignored: [IgnoredAuthor] = []) -> [String] {
        guard let text = authorsText?.nilIfEmpty else { return [] }
        var parts: [String] = []
        var last = text.startIndex
        for m in separatorRx.allMatches(in: text) {
            guard let r = Range(m.range, in: text) else { continue }
            parts.append(String(text[last..<r.lowerBound]).trimmed)
            last = r.upperBound
        }
        parts.append(String(text[last...]).trimmed)

        var found: [(text: String, withCountry: Bool)] = []
        var personLike = 0
        var i = 0
        while i < parts.count {
            let part = parts[i]
            if hasKeyword(part), part.split(separator: " ").count >= 2 {
                var affiliation = part
                var withCountry = endsWithCountry(part)
                if i + 1 < parts.count, isCountry(parts[i + 1]) {
                    affiliation += ", " + parts[i + 1]
                    withCountry = true
                    i += 1
                }
                found.append((affiliation, withCountry))
            } else if !part.isEmpty, !isCountry(part), part.lowercased() != "et al." {
                personLike += 1
            }
            i += 1
        }
        return found.filter { f in
            f.withCountry || personLike > 0 || ignored.contains { matchesInstitution(f.text, [$0.name]) }
        }.map(\.text)
    }
}
