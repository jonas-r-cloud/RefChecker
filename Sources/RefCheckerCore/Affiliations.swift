import Foundation

/// Tells authors from affiliations. Repository metadata (notably the AIS eLibrary) sometimes
/// lists a university or company as a co-author, or appends it to an author's name.
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

    static func hasKeyword(_ s: String) -> Bool {
        wordRx.firstMatch(in: s) != nil || acronymRx.firstMatch(in: s) != nil
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

    static func matchesInstitution(_ name: String, _ institutions: [String]) -> Bool {
        let k = NormalizedText.key(name)
        guard k.count >= 4 else { return false }
        return institutions.map(NormalizedText.key).contains { inst in
            inst == k || (k.count >= 8 && inst.contains(k)) || (inst.count >= 8 && k.contains(inst))
        }
    }

    /// Splits raw author entries ("Family, Given") into real authors and ignored affiliations.
    /// `institutions` are strings the provider itself labels as affiliations; removals backed by
    /// them are certain, removals based on wording alone are not.
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
                    ignored.append(IgnoredAuthor(name: rest, isCertain: known,
                                                 reason: "appended to the name of \(parts[1]) \(parts[0])"))
                    continue
                }
            }
            if looksLikeOrganization(entry) {
                ignored.append(IgnoredAuthor(name: entry, isCertain: false, reason: "worded like an organisation"))
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
}
