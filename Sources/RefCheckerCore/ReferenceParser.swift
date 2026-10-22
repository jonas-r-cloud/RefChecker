import Foundation

/// Locates the reference list in the full text of a paper.
public enum ReferenceSectionExtractor {
    static let headings: Set<String> = [
        "references", "reference", "bibliography", "literature", "literature cited", "works cited",
        "cited literature", "references and notes", "list of references", "sources",
        "literaturverzeichnis", "literatur", "quellenverzeichnis", "quellen"
    ]
    private static let numberingRx = NSRegularExpression("^(?:(?:\\d+|[IVXLC]+|[A-Z])[.)]?\\s+)")
    private static let endRx = NSRegularExpression(
        "^(?:(?:\\d+|[A-Z])[.)]?\\s+)?(appendix|appendices|supplementary (material|information)|anhang|author biographies|biographies)\\b",
        options: [.caseInsensitive])

    static func isHeading(_ line: String) -> Bool {
        var t = line.trimmed
        guard !t.isEmpty, t.count <= 40 else { return false }
        t = numberingRx.replacing(in: t, with: "")
        t = t.trimmingCharacters(":.").lowercased()
        return headings.contains(t)
    }

    /// Returns the text following the last "References"-type heading, or nil.
    public static func extract(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.lastIndex(where: isHeading) else { return nil }
        var body = Array(lines[(start + 1)...])
        if let end = body.firstIndex(where: { $0.trimmed.count < 60 && endRx.firstMatch(in: $0.trimmed) != nil }) {
            body = Array(body[..<end])
        }
        let section = body.joined(separator: "\n").trimmed
        return section.isEmpty ? nil : section
    }
}

/// Splits a reference section into individual entries.
public enum ReferenceSplitter {
    public struct Entry: Hashable, Sendable {
        public var label: String
        public var text: String
    }

    public static func split(_ section: String) -> [Entry] {
        let text = clean(section)
        guard !text.isEmpty else { return [] }
        if let e = splitNumbered(text, bracketed: true) { return e }
        if let e = splitNumbered(text, bracketed: false) { return e }
        if let e = splitAlphaLabels(text) { return e }
        if let e = splitBlankLines(text) { return e }
        return splitAuthorYear(text)
    }

    private static let pageNumberRx = NSRegularExpression("^\\s*\\d{1,4}\\s*$")

    static func clean(_ s: String) -> String {
        let t = s.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        // Drop bare page numbers, but keep digits that continue a DOI/URL broken across lines.
        var lines: [String] = []
        for line in t.components(separatedBy: "\n") {
            if pageNumberRx.firstMatch(in: line) != nil,
               !(lines.last.map { endsWithURL($0.trimmed) && "/.-_".contains($0.trimmed.last ?? " ") } ?? false) {
                continue
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmed
    }

    /// "[1] … [2] …" (markers may appear anywhere, they must be consecutive) or
    /// "1. …" / "1) …" at the start of a line.
    static func splitNumbered(_ text: String, bracketed: Bool) -> [Entry]? {
        var markers: [(label: String, range: Range<String.Index>)] = []
        var searchFrom = text.startIndex
        var n = 1
        while searchFrom < text.endIndex {
            let pattern = bracketed ? "\\[\(n)\\]" : "(?m)^[ \\t]*\(n)[.)]?[ \\t]+(?=\\S)"
            let rx = NSRegularExpression(pattern)
            guard let m = rx.firstMatch(in: text, options: [], range: NSRange(searchFrom..<text.endIndex, in: text)),
                  let r = Range(m.range, in: text) else { break }
            if n == 1 && text.distance(from: text.startIndex, to: r.lowerBound) > 300 { return nil }
            markers.append((String(n), r))
            searchFrom = r.upperBound
            n += 1
        }
        guard markers.count >= 2 else { return nil }
        return entries(from: markers, in: text)
    }

    private static let alphaLabelRx = NSRegularExpression("(?m)^[ \\t]*\\[([A-Za-z][^\\]\\s]{0,20})\\][ \\t]*")

    /// "[Smi20] …" alphanumeric labels at line starts.
    static func splitAlphaLabels(_ text: String) -> [Entry]? {
        let matches = alphaLabelRx.allMatches(in: text)
        guard matches.count >= 2,
              let first = matches.first, first.range.location < 300 else { return nil }
        let markers = matches.compactMap { m -> (String, Range<String.Index>)? in
            guard let r = Range(m.range, in: text), let label = text.substring(with: m.range(at: 1)) else { return nil }
            return (label, r)
        }
        return entries(from: markers, in: text)
    }

    private static func entries(from markers: [(label: String, range: Range<String.Index>)], in text: String) -> [Entry] {
        markers.indices.compactMap { i in
            let end = i + 1 < markers.count ? markers[i + 1].range.lowerBound : text.endIndex
            let body = joinLines(text[markers[i].range.upperBound..<end].components(separatedBy: "\n"))
            return body.isEmpty ? nil : Entry(label: markers[i].label, text: body)
        }
    }

    private static let yearRx = NSRegularExpression("\\b(1[89]\\d{2}|20\\d{2})")

    /// Entries separated by empty lines (typical for pasted reference lists).
    static func splitBlankLines(_ text: String) -> [Entry]? {
        let chunks = text.components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmed.isEmpty })
            .map { joinLines(Array($0)) }
            .filter { $0.count > 15 }
        guard chunks.count >= 2 else { return nil }
        let withYear = chunks.filter { yearRx.firstMatch(in: $0) != nil }.count
        let averageLength = chunks.map(\.count).reduce(0, +) / chunks.count
        guard Double(withYear) >= 0.8 * Double(chunks.count), averageLength < 700 else { return nil }
        return chunks.enumerated().map { Entry(label: "\($0.offset + 1)", text: $0.element) }
    }

    private static let authorStartRx = NSRegularExpression(
        "^(?:(?:van|von|de|der|den|del|della|da|di|du|le|la|ten|ter|dos)\\s+)*" +
        "(?:\\p{Lu}[\\p{L}'’`\\-]+(?:\\s+\\p{Lu}[\\p{L}'’\\-]+)?,\\s*(?:\\p{Lu}\\.|\\p{Lu}\\p{Ll}+(?:\\s\\p{Lu}\\.)*(?:,|\\s+(?:and|&)\\s))" +
        "|\\p{Lu}\\.(?:\\s?-?\\p{Lu}\\.)*\\s+\\p{Lu}[\\p{L}'’\\-]+[,\\s]" +
        "|\\p{Lu}[\\p{L}'’\\-]+\\s+\\p{Lu}{1,3}[,.])")

    /// Unnumbered author–year lists: a new entry starts on a line that looks like
    /// the beginning of an author list, after a line that ends an entry.
    static func splitAuthorYear(_ text: String) -> [Entry] {
        var entries: [String] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmed
            guard !t.isEmpty else { continue }
            if let previous = current.last, endsEntry(previous),
               authorStartRx.firstMatch(in: t) != nil,
               yearRx.firstMatch(in: current.joined(separator: " ")) != nil {
                entries.append(joinLines(current))
                current = [t]
            } else {
                current.append(t)
            }
        }
        if !current.isEmpty { entries.append(joinLines(current)) }
        return entries.enumerated().map { Entry(label: "\($0.offset + 1)", text: $0.element) }
    }

    private static func endsEntry(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        if ".)]".contains(last) || last.isNumber { return true }
        let lower = line.lowercased()
        return lower.contains("doi") || lower.contains("http")
    }

    /// Joins wrapped lines, undoing end-of-line hyphenation and broken URLs/DOIs.
    static func joinLines(_ lines: [String]) -> String {
        var out = ""
        for raw in lines {
            let line = raw.trimmed
            guard !line.isEmpty else { continue }
            if out.isEmpty {
                out = line
                continue
            }
            if out.hasSuffix("-"), out.dropLast().last?.isLowercase == true, line.first?.isLowercase == true,
               !endsWithURL(out) {
                out.removeLast()
                out += line
            } else if endsWithURL(out), let last = out.last, "/.-_".contains(last) {
                out += line
            } else {
                out += " " + line
            }
        }
        return out
    }

    private static func endsWithURL(_ s: String) -> Bool {
        guard let last = s.split(separator: " ").last?.lowercased() else { return false }
        return last.hasPrefix("http") || last.hasPrefix("doi:") || last.hasPrefix("10.") || last.contains("doi.org")
    }
}

/// Extracts fields (authors, title, venue, year, DOI) from a single entry.
public enum ReferenceParser {
    public static func parse(section: String) -> [ParsedReference] {
        ReferenceSplitter.split(section).enumerated().map { index, entry in
            parse(entry.text, label: entry.label, id: index)
        }
    }

    static let doiRx = NSRegularExpression("10\\.\\d{4,9}/[^\\s\"<>]+", options: [.caseInsensitive])
    private static let urlRx = NSRegularExpression("(?:https?://|www\\.)\\S+", options: [.caseInsensitive])
    private static let doiLabelRx = NSRegularExpression(
        "\\b(?:doi|DOI)\\s*:?\\s*|\\[online\\]|available(?: online)?(?: at| from)?:?|retrieved from|accessed:?[^.]*\\.?|last accessed[^.]*\\.?|\\bURL\\b:?",
        options: [.caseInsensitive])
    private static let parenYearRx = NSRegularExpression("\\((1[89]\\d{2}|20\\d{2})[a-z]?(?:,[^)]*)?\\)")
    private static let bareYearRx = NSRegularExpression("(?<![\\d/.])(1[89]\\d{2}|20\\d{2})[a-z]?(?![\\d/])")
    private static let quotedRx = NSRegularExpression("[“\"„«]([^”\"“»]{8,})[”\"“»]")
    private static let apaRx = NSRegularExpression("\\s*\\((?:1[89]\\d{2}|20\\d{2}|n\\.\\s?d\\.|in press)[a-z]?(?:,[^)]*)?\\)\\.?\\s*",
                                                   options: [.caseInsensitive])
    private static let authorsBeforeColonRx = NSRegularExpression("(?:\\p{Lu}\\.|et al\\.?|,\\s*\\p{Lu}\\.?)\\s*$")
    private static let venuePrefixRx = NSRegularExpression("^(?:in\\s*:|in\\s+)\\s*", options: [.caseInsensitive])
    private static let pureYearRx = NSRegularExpression("^\\(?(1[89]\\d{2}|20\\d{2})[a-z]?\\)?$")

    public static func parse(_ text: String, label: String, id: Int) -> ParsedReference {
        let raw = text.trimmed
        let doi = extractDOI(raw)

        var stripped = urlRx.replacing(in: raw, with: " ")
        stripped = doiRx.replacing(in: stripped, with: " ")
        stripped = doiLabelRx.replacing(in: stripped, with: " ")
        stripped = NSRegularExpression("\\s+").replacing(in: stripped, with: " ").trimmed

        let year = extractYear(stripped)
        let hasEtAl = raw.range(of: "et al", options: .caseInsensitive) != nil

        var authors: String?
        var title: String?
        var venue: String?

        if let m = quotedRx.firstMatch(in: stripped), let q = stripped.substring(with: m.range(at: 1)),
           let whole = Range(m.range, in: stripped) {
            // IEEE / Chicago: Authors, “Title,” Venue, …
            title = q
            authors = String(stripped[..<whole.lowerBound])
            venue = String(stripped[whole.upperBound...]).trimmingCharacters(",.;: ")
                .components(separatedBy: ", ").first
        } else if let m = apaRx.firstMatch(in: stripped), let r = Range(m.range, in: stripped),
                  m.range.location > 0, Double(m.range.location) < Double(stripped.utf16.count) * 0.6 {
            // APA / Harvard: Authors (2020). Title. Venue, …
            authors = String(stripped[..<r.lowerBound])
            let rest = segments(String(stripped[r.upperBound...]))
            title = rest.first
            venue = rest.dropFirst().first
        } else {
            var segs = segments(stripped).filter { pureYearRx.firstMatch(in: $0) == nil }
            if let first = segs.first, let colon = first.range(of: ": "),
               authorsBeforeColonRx.firstMatch(in: String(first[..<colon.lowerBound])) != nil {
                // Springer LNCS: Smith, J., Doe, A.: Title. In: Venue …
                segs[0] = String(first[colon.upperBound...])
                segs.insert(String(first[..<colon.lowerBound]), at: 0)
            }
            authors = segs.first
            title = segs.dropFirst().first
            venue = segs.dropFirst(2).first
        }

        return ParsedReference(
            id: id, label: label, raw: raw,
            authorsText: authors?.trimmingCharacters(",.;: ").nilIfEmpty,
            title: title?.trimmingCharacters(",.;: “”\"").nilIfEmpty,
            venue: venue.map { venuePrefixRx.replacing(in: $0.trimmed, with: "") }?.trimmingCharacters(",.;: ").nilIfEmpty,
            year: year, doi: doi, hasEtAl: hasEtAl)
    }

    static func extractDOI(_ text: String) -> String? {
        guard let m = doiRx.firstMatch(in: text), var doi = text.substring(with: m.range) else { return nil }
        while let last = doi.last, ".,;:]}".contains(last) || (last == ")" && doi.filter({ $0 == "(" }).count < doi.filter({ $0 == ")" }).count) {
            doi.removeLast()
        }
        return doi
    }

    static func extractYear(_ text: String) -> String? {
        if let m = parenYearRx.firstMatch(in: text) { return text.substring(with: m.range(at: 1)) }
        if let m = bareYearRx.allMatches(in: text).last { return text.substring(with: m.range(at: 1)) }
        return nil
    }

    private static let abbreviations: Set<String> = [
        "al", "pp", "p", "vol", "vols", "no", "nos", "nr", "eds", "ed", "proc", "conf", "int", "intl", "j",
        "trans", "univ", "dept", "vs", "etc", "jr", "sr", "st", "inc", "ltd", "co", "comp", "comput", "sci",
        "eng", "inf", "syst", "res", "rev", "assoc", "mach", "natl", "acad", "lett", "phys", "chem", "math",
        "appl", "symp", "annu", "manag", "mgmt", "technol", "tech", "fig", "ch", "sec", "ser", "pt", "rep",
        "suppl", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec", "hrsg",
        "aufl", "bd", "s", "dr", "prof", "mr", "mrs", "ms", "e.g", "i.e", "cf"
    ]

    /// Splits at sentence-ending punctuation, but not after initials or common abbreviations.
    static func segments(_ s: String) -> [String] {
        let chars = Array(s)
        var segs: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if ".?!".contains(c), i + 2 < chars.count, chars[i + 1] == " " {
                var isBreak = !chars[i + 2].isLowercase
                if c == ".", isBreak {
                    let word = current.dropLast().reversed().prefix(while: { $0.isLetter || $0 == "." }).reversed()
                    let w = String(word)
                    let lastPart = w.split(separator: ".").last.map(String.init) ?? ""
                    if lastPart.count == 1 && lastPart.first!.isUppercase { isBreak = false }
                    if abbreviations.contains(w.lowercased()) || abbreviations.contains(lastPart.lowercased()) {
                        isBreak = false
                    }
                }
                if isBreak {
                    let seg = (c == "." ? String(current.dropLast()) : current).trimmed
                    if !seg.isEmpty { segs.append(seg) }
                    current = ""
                    i += 2
                    continue
                }
            }
            i += 1
        }
        let rest = current.trimmed.trimmingCharacters(".")
        if !rest.isEmpty { segs.append(rest) }
        return segs
    }
}
