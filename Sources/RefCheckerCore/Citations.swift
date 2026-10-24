import Foundation

/// How often each reference is cited in the body of the paper.
public struct CitationIndex: Sendable {
    public enum Style: String, Sendable {
        case numbered, authorYear
    }

    public var style: Style
    /// Text snippets around each citation, by reference id.
    public var occurrences: [Int: [String]]
    /// Numbers cited in the text for which the list has no reference (numbered style only).
    public var unknownNumbers: [Int]

    public func count(for id: Int) -> Int { occurrences[id]?.count ?? 0 }

    /// A reference that is never cited in the text is an issue in itself.
    public func adjusted(_ verdict: Verdict, for id: Int) -> Verdict {
        guard count(for: id) == 0 else { return verdict }
        switch verdict {
        case .verified, .needsReview: return .issues(1)
        case .issues(let n): return .issues(n + 1)
        case .notFound, .failed: return verdict
        }
    }

    private static let bracketRx = NSRegularExpression("\\[([^\\[\\]]{1,80})\\]")
    private static let pageRx = NSRegularExpression("(?:,\\s*)?(?:pp?|S)\\.\\s*\\d+(?:\\s*[–—-]\\s*\\d+)?", options: [.caseInsensitive])
    private static let numericContentRx = NSRegularExpression("^[\\d\\s,;–—-]+$")
    private static let rangeRx = NSRegularExpression("^(\\d+)\\s*[–—-]\\s*(\\d+)$")
    private static let yearRx = NSRegularExpression("(?<![\\d/.])(1[89]\\d{2}|20\\d{2})([a-z])?(?![\\d/])")
    private static let leadingNumberRx = NSRegularExpression("^(\\d+)[a-z]?$")

    /// Counts citations in `body`. Numbered lists are matched by "[3]", "[3, 5–7]"; author–year
    /// lists by the first author's family name followed (within the same citation) by the year.
    public static func build(body: String, references: [ParsedReference]) -> CitationIndex {
        let numbered = references.filter { leadingNumberRx.firstMatch(in: $0.label) != nil && !$0.label.contains(where: \.isLetter) }
        if references.count > 0, Double(numbered.count) >= 0.8 * Double(references.count),
           countBracketCitations(body) > 0 {
            return numberedIndex(body: body, references: references)
        }
        return authorYearIndex(body: body, references: references)
    }

    static func snippet(_ text: String, _ range: Range<String.Index>) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        let s = String(text[lower..<upper]).components(separatedBy: .newlines).joined(separator: " ")
        return "…" + s.trimmed + "…"
    }

    private static func countBracketCitations(_ body: String) -> Int {
        bracketRx.allMatches(in: body).filter { m in
            body.substring(with: m.range(at: 1)).map { numericContentRx.firstMatch(in: pageRx.replacing(in: $0, with: "")) != nil } ?? false
        }.count
    }

    static func numberedIndex(body: String, references: [ParsedReference]) -> CitationIndex {
        var idsByNumber: [Int: Int] = [:]
        for ref in references { if let n = Int(ref.label) { idsByNumber[n] = ref.id } }
        var occurrences: [Int: [String]] = [:]
        var unknown = Set<Int>()
        for m in bracketRx.allMatches(in: body) {
            guard let content = body.substring(with: m.range(at: 1)), let whole = Range(m.range, in: body) else { continue }
            let cleaned = pageRx.replacing(in: content, with: "")
            guard numericContentRx.firstMatch(in: cleaned) != nil else { continue }
            var cited = Set<Int>()
            for part in cleaned.components(separatedBy: CharacterSet(charactersIn: ",;")) {
                let p = part.trimmed
                if let r = rangeRx.firstMatch(in: p), let a = p.substring(with: r.range(at: 1)).flatMap({ Int($0) }),
                   let b = p.substring(with: r.range(at: 2)).flatMap({ Int($0) }), a <= b, b - a < 50 {
                    cited.formUnion(a...b)
                } else if let n = Int(p) {
                    cited.insert(n)
                }
            }
            let context = snippet(body, whole)
            for n in cited {
                if let id = idsByNumber[n] { occurrences[id, default: []].append(context) } else { unknown.insert(n) }
            }
        }
        return CitationIndex(style: .numbered, occurrences: occurrences, unknownNumbers: unknown.sorted())
    }

    /// The first author's family name: "Smith, J., & Doe, A." → Smith; "Alice Smith and Bob Jones" → Smith.
    static func firstAuthorFamily(_ ref: ParsedReference) -> String? {
        guard let authors = ref.authorsText?.trimmed, !authors.isEmpty else { return nil }
        let pieces = authors.components(separatedBy: ",").map { $0.trimmed }
        guard var first = pieces.first, !first.isEmpty else { return nil }
        for separator in [" and ", " & ", " und "] {
            if let r = first.range(of: separator) { first = String(first[..<r.lowerBound]) }
        }
        let initialsFollow = pieces.count > 1 && pieces[1].first?.isUppercase == true && pieces[1].count <= 12
            && pieces[1].contains(".")
        if initialsFollow || !first.contains(" ") { return first }
        // Given name first ("Alice Smith"), unless it is an organisation.
        if Affiliations.looksLikeOrganization(first) { return first }
        let words = first.split(separator: " ").map(String.init)
        // Vancouver: "Smith JA" – initials after the family name.
        if let last = words.last, last.count <= 3, last.allSatisfy({ $0.isUppercase }) {
            return words.dropLast().joined(separator: " ")
        }
        return words.last
    }

    static func authorYearIndex(body: String, references: [ParsedReference]) -> CitationIndex {
        let years = yearRx.allMatches(in: body).compactMap { m -> (year: String, suffix: String, range: Range<String.Index>)? in
            guard let r = Range(m.range, in: body), let y = body.substring(with: m.range(at: 1)) else { return nil }
            return (y, body.substring(with: m.range(at: 2)) ?? "", r)
        }
        var occurrences: [Int: [String]] = [:]
        for ref in references {
            guard let family = firstAuthorFamily(ref), let year = ref.year else { continue }
            // "2020a" in the list must be cited as "2020a".
            let suffix = yearRx.allMatches(in: ref.raw).first { ref.raw.substring(with: $0.range(at: 1)) == year }
                .flatMap { ref.raw.substring(with: $0.range(at: 2)) } ?? ""
            let familyRx = NSRegularExpression("\\b" + NSRegularExpression.escapedPattern(for: family) + "\\b",
                                               options: [.caseInsensitive])
            for (i, occurrence) in years.enumerated() where occurrence.year == year && occurrence.suffix == suffix {
                // The name must precede the year within the same citation: at most 80 characters back,
                // with no other year and no ";" in between ("(Smith, 2019; Jones, 2020)").
                let previousYearEnd = i > 0 ? years[i - 1].range.upperBound : body.startIndex
                let windowStart = max(previousYearEnd,
                                      body.index(occurrence.range.lowerBound, offsetBy: -80, limitedBy: body.startIndex) ?? body.startIndex)
                var window = String(body[windowStart..<occurrence.range.lowerBound])
                if let semicolon = window.range(of: ";", options: .backwards) { window = String(window[semicolon.upperBound...]) }
                if familyRx.firstMatch(in: window) != nil {
                    occurrences[ref.id, default: []].append(snippet(body, occurrence.range))
                }
            }
        }
        return CitationIndex(style: .authorYear, occurrences: occurrences, unknownNumbers: [])
    }
}
