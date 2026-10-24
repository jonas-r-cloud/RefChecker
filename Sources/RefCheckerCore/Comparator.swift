import Foundation

/// Compares a parsed reference with retrieved metadata field by field.
///
/// A field matches only if the metadata value occurs in the reference text exactly,
/// ignoring case, accents, punctuation and line breaks. Whether a match is shown as
/// confirmed (green) is decided afterwards by `ReferenceChecker`, from the evidence.
public enum Comparator {
    public static func compare(_ ref: ParsedReference, with meta: RetrievedMetadata,
                               options: ComparisonOptions = ComparisonOptions()) -> (fields: [FieldComparison], highlights: [Highlight]) {
        let text = matchingText(ref.raw)
        var fields: [FieldComparison] = []
        var highlights: [Highlight] = []

        // Title
        if let r = text.find(meta.title) {
            highlights.append(Highlight(r, .match, field: "Title"))
            if let subtitle = meta.subtitle, !subtitle.isEmpty, text.find(subtitle) == nil,
               !NormalizedText.key(meta.title).contains(NormalizedText.key(subtitle)) {
                fields.append(FieldComparison(field: "Title", original: text.text(r), retrieved: meta.fullTitle,
                                              status: .mismatch, note: "Subtitle missing: “\(subtitle)”"))
            } else {
                fields.append(FieldComparison(field: "Title", original: text.text(r), retrieved: meta.fullTitle, status: .match,
                                              isLiteral: isLiteral(text.text(r), meta.title)))
            }
        } else {
            var original = ref.title
            if let w = text.bestWindow(for: meta.fullTitle) {
                original = text.text(w.range)
                highlights.append(Highlight(w.range, .mismatch, field: "Title"))
            }
            let note = original.map { "Similarity \(Int((Similarity.ratio($0, meta.fullTitle) * 100).rounded()))%" }
            fields.append(FieldComparison(field: "Title", original: original, retrieved: meta.fullTitle,
                                          status: original == nil ? .missing : .mismatch, note: note))
        }

        // Authors
        if meta.authors.isEmpty {
            fields.append(FieldComparison(field: "Authors", original: ref.authorsText, retrieved: nil, status: .unavailable))
        } else {
            var missing: [String] = []
            for author in meta.authors {
                let lastWord = author.family.split(separator: " ").last.map(String.init) ?? author.family
                if let r = text.findWords(author.family) ?? text.findWords(lastWord) {
                    highlights.append(Highlight(r, .match, field: "Authors"))
                } else {
                    missing.append(author.display)
                }
            }
            let found = meta.authors.count - missing.count
            var notes: [String] = []
            var status: MatchStatus = missing.isEmpty ? .match : .mismatch
            if !missing.isEmpty {
                // Organisations listed as authors by a provider are probably affiliations: not an error, but not confirmed.
                let orgLike = missing.filter(Affiliations.looksLikeOrganization)
                if orgLike.count == missing.count {
                    status = .unconfirmed
                    notes.append("\(meta.provider) lists “\(orgLike.joined(separator: "”, “"))” as author – probably an affiliation; check manually")
                } else {
                    notes.append(ref.hasEtAl && found > 0
                        ? "Shortened with “et al.” – not listed: \(missing.joined(separator: ", "))"
                        : "Not found in reference: \(missing.joined(separator: ", "))")
                }
            }
            if !meta.ignoredAuthors.isEmpty {
                notes.append("Ignored, not authors: " + meta.ignoredAuthors.map { "“\($0.name)” (\($0.reason))" }.joined(separator: "; "))
                // Only a removal the provider itself backs keeps the field green.
                if status == .match, meta.ignoredAuthors.contains(where: { !$0.isCertain }) { status = .unconfirmed }
            }
            // References generated from faulty metadata repeat the affiliations as authors.
            let written = Affiliations.inAuthorList(ref.authorsText, ignored: meta.ignoredAuthors)
            if !written.isEmpty {
                status = .mismatch
                notes.insert("The reference lists affiliations as authors: “\(written.joined(separator: "”, “"))” – remove them", at: 0)
                for affiliation in written {
                    if let r = text.find(affiliation) { highlights.append(Highlight(r, .mismatch, field: "Authors")) }
                }
            }
            fields.append(FieldComparison(
                field: "Authors",
                original: ref.authorsText,
                retrieved: meta.authors.map(\.display).joined(separator: "; "),
                status: status,
                note: notes.isEmpty ? nil : notes.joined(separator: ". ")))
        }

        // Year
        if let year = meta.year {
            let accepted = [year] + meta.alternativeYears
            let retrieved = ([year] + meta.alternativeYears.map { "\($0) (alt.)" }).joined(separator: ", ")
            if let refYear = ref.year {
                let ok = accepted.contains(refYear)
                if let r = text.findWords(refYear) ?? text.find(refYear) {
                    highlights.append(Highlight(r, ok ? .match : .mismatch, field: "Year"))
                }
                fields.append(FieldComparison(field: "Year", original: refYear, retrieved: retrieved, status: ok ? .match : .mismatch))
            } else {
                fields.append(FieldComparison(field: "Year", original: nil, retrieved: retrieved, status: .missing))
            }
        } else {
            fields.append(FieldComparison(field: "Year", original: ref.year, retrieved: nil, status: .unavailable))
        }

        // Venue (journal / proceedings / book series) or publisher for books
        let label = meta.isBook && meta.venue == nil ? "Publisher" : "Venue"
        let venues = ([label == "Publisher" ? meta.publisher : meta.venue] + meta.venueAliases)
            .compactMap { $0?.nilIfEmpty }
        // Short forms: official abbreviations (Crossref, ISSN register, NLM), then the ISO 4
        // abbreviation generated from the full name by the LTWA rules.
        var shortForms = label == "Venue" ? meta.venueAbbreviations : []
        if label == "Venue", let name = meta.venue {
            for iso in ISO4.variants(name) where !shortForms.contains(where: { NormalizedText.key($0.name) == NormalizedText.key(iso) }) {
                shortForms.append(VenueAbbreviation(iso, .iso4))
            }
        }
        if venues.isEmpty {
            fields.append(FieldComparison(field: label, original: ref.venue, retrieved: nil, status: .unavailable))
        } else if let hit = venues.lazy.compactMap({ v in
            // Short names such as "ICIS" must occur as a word, not inside another word.
            (NormalizedText.key(v).count <= 6 ? text.findWords(v) : text.find(v)).map { (venue: v, range: $0) }
        }).first {
            highlights.append(Highlight(hit.range, .match, field: label))
            fields.append(FieldComparison(field: label, original: text.text(hit.range), retrieved: hit.venue, status: .match,
                                          isLiteral: isLiteral(text.text(hit.range), hit.venue)))
        } else if let hit = shortForms.lazy.compactMap({ a in findAbbreviation(a.name, in: text).map { (form: a, range: $0) } }).first {
            // An official abbreviation is as good as the full name; the generated one is only a guess.
            let status: MatchStatus = hit.form.source.isOfficial ? .match : .unconfirmed
            highlights.append(Highlight(hit.range, status, field: label))
            var note = "Abbreviated journal name “\(hit.form.name)” (\(hit.form.source.rawValue))"
            if !hit.form.source.isOfficial { note += " – no official abbreviation list confirms it; check manually" }
            fields.append(FieldComparison(field: label, original: text.text(hit.range), retrieved: venues[0],
                                          status: status, note: note))
        } else {
            var original = ref.venue
            if let w = text.bestWindow(for: venues[0], minimumScore: 0.5) {
                original = text.text(w.range)
                highlights.append(Highlight(w.range, .mismatch, field: label))
            }
            var notes: [String] = []
            if venues.count > 1 { notes.append("Also known as: " + venues.dropFirst().joined(separator: "; ")) }
            if !shortForms.isEmpty {
                notes.append("Abbreviations tried: " + shortForms.map { "“\($0.name)” (\($0.source.rawValue))" }.joined(separator: "; "))
            }
            fields.append(FieldComparison(field: label, original: original, retrieved: venues[0],
                                          status: original == nil ? .missing : .mismatch,
                                          note: notes.isEmpty ? nil : notes.joined(separator: ". ")))
        }

        // Volume, issue, pages: the numbers must appear in a recognisable place
        // ("vol. 12", "12(3)", "45–67"); a number that merely occurs somewhere is only amber.
        if options.checkVolumeIssuePages {
            let volumeIdx = meta.volume.map(text.tokenIndices(of:)) ?? []
            let issueIdx = meta.issue.map(text.tokenIndices(of:)) ?? []
            let articleIdx = meta.articleNumber.map(text.tokenIndices(of:)) ?? []
            let firstPageIdx = meta.pages.flatMap { NormalizedText.words($0).first }.map(text.tokenIndices(of:)) ?? []
            func key(_ i: Int) -> String { text.tokens.indices.contains(i) ? text.tokens[i].key : "" }
            func range(_ i: Int, _ j: Int) -> Range<Int> { text.tokens[i].range.lowerBound..<text.tokens[j].range.upperBound }
            // What may follow the volume: "12(3)", "12, no. 3", "243, 122886", "12, 45–67".
            let afterVolume = Set(issueIdx + articleIdx + firstPageIdx)

            if let volume = meta.volume?.nilIfEmpty {
                let placed = volumeIdx.first { i in
                    volumeMarkers.contains(key(i - 1)) || afterVolume.contains(i + 1)
                        || (issueIdx.contains(i + 2) && issueMarkers.contains(key(i + 1)))
                }
                fields.append(numberField("Volume", volume, placed: placed.map { range($0, $0) },
                                          loose: volumeIdx.first.map { range($0, $0) }, what: "volume", &highlights))
            }
            if let issue = meta.issue?.nilIfEmpty {
                let placed = issueIdx.first { i in
                    issueMarkers.contains(key(i - 1)) || volumeIdx.contains(i - 1)
                        || (volumeIdx.contains(i - 2) && issueMarkers.contains(key(i - 1)))
                }
                fields.append(numberField("Issue", issue, placed: placed.map { range($0, $0) },
                                          loose: issueIdx.first.map { range($0, $0) }, what: "issue", &highlights))
            }
            // Like a missing DOI, a missing article number can be accepted via the settings.
            if let article = meta.articleNumber?.nilIfEmpty, options.requireArticleNumber || !articleIdx.isEmpty {
                // "Article 122886", "243, 122886", "35(3), 100582", "Art. No. 7".
                let placed = articleIdx.first { i in
                    articleMarkers.contains(key(i - 1)) || volumeIdx.contains(i - 1) || issueIdx.contains(i - 1)
                        || (articleMarkers.contains(key(i - 2)) && articleMarkers.contains(key(i - 1)))
                }
                fields.append(numberField("Article no.", article, placed: placed.map { range($0, $0) },
                                          loose: articleIdx.first.map { range($0, $0) }, what: "article number", &highlights))
            }
            if let pages = meta.pages?.nilIfEmpty {
                let parts = NormalizedText.words(pages)
                let firstIdx = parts.first.map(text.tokenIndices(of:)) ?? []
                let lastIdx = parts.last.map(text.tokenIndices(of:)) ?? []
                if parts.count >= 2 {
                    if let i = firstIdx.first(where: { lastIdx.contains($0 + 1) }) {
                        fields.append(numberField("Pages", pages, placed: range(i, i + 1), loose: nil, what: "page range", &highlights))
                    } else if !firstIdx.isEmpty && !lastIdx.isEmpty {
                        fields.append(numberField("Pages", pages, placed: nil, loose: range(firstIdx[0], firstIdx[0]),
                                                  what: "page range", &highlights))
                    } else if !firstIdx.isEmpty || !lastIdx.isEmpty {
                        let i = firstIdx.first ?? lastIdx[0]
                        highlights.append(Highlight(range(i, i), .mismatch, field: "Pages"))
                        fields.append(FieldComparison(field: "Pages", original: nil, retrieved: pages, status: .mismatch,
                                                      note: "Page range differs (only the \(firstIdx.isEmpty ? "last" : "first") page matches)"))
                    } else {
                        fields.append(FieldComparison(field: "Pages", original: nil, retrieved: pages, status: .missing))
                    }
                } else {
                    let placed = firstIdx.first { pageMarkers.contains(key($0 - 1)) || volumeIdx.contains($0 - 1) || issueIdx.contains($0 - 1) }
                    fields.append(numberField("Pages", pages, placed: placed.map { range($0, $0) },
                                              loose: firstIdx.first.map { range($0, $0) }, what: "page / article number", &highlights))
                }
            }
        }

        // DOI
        if let doi = meta.doi?.nilIfEmpty {
            if let refDOI = ref.doi {
                let ok = refDOI.lowercased() == doi.lowercased()
                if let r = ref.raw.range(of: refDOI) {
                    highlights.append(Highlight(ref.raw.characterOffsets(of: r), ok ? .match : .mismatch, field: "DOI"))
                }
                fields.append(FieldComparison(field: "DOI", original: refDOI, retrieved: doi, status: ok ? .match : .mismatch))
            } else if options.requireDOI {
                fields.append(FieldComparison(field: "DOI", original: nil, retrieved: doi, status: .missing,
                                              note: "The reference does not give the DOI"))
            }
        } else if let refDOI = ref.doi {
            fields.append(FieldComparison(field: "DOI", original: refDOI, retrieved: nil, status: .unavailable))
        }

        return (fields, removeOverlaps(highlights))
    }

    static let volumeMarkers: Set<String> = ["vol", "vols", "volume", "v", "bd", "band", "jg", "jahrgang"]
    static let issueMarkers: Set<String> = ["no", "nr", "n", "issue", "iss", "number", "num", "heft"]
    static let pageMarkers: Set<String> = ["p", "pp", "page", "pages", "s"]
    static let articleMarkers: Set<String> = ["art", "article", "artno", "no", "nr", "number", "paper", "e", "eid", "elocator"]

    /// Green if the number sits in a recognisable place, amber if it only occurs somewhere, red if absent.
    private static func numberField(_ field: String, _ value: String, placed: Range<Int>?, loose: Range<Int>?,
                                    what: String, _ highlights: inout [Highlight]) -> FieldComparison {
        if let placed {
            highlights.append(Highlight(placed, .match, field: field))
            return FieldComparison(field: field, original: value, retrieved: value, status: .match, isLiteral: true)
        }
        if let loose {
            highlights.append(Highlight(loose, .unconfirmed, field: field))
            return FieldComparison(field: field, original: value, retrieved: value, status: .unconfirmed,
                                   note: "The number occurs in the reference, but not recognisably as the \(what)")
        }
        return FieldComparison(field: field, original: nil, retrieved: value, status: .missing)
    }

    static func isLiteral(_ a: String, _ b: String) -> Bool {
        let collapse = { (s: String) in s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return collapse(a) == collapse(b)
    }

    private static let linkRx = NSRegularExpression(
        "(?:https?://|www\\.)\\S+|\\bdoi:\\s*\\S+|\\b10\\.\\d{4,9}/\\S+", options: [.caseInsensitive])
    /// A piece of a DOI/URL that a line break split off ("…/10.5465/ amr.2011.0396").
    private static let linkTailRx = NSRegularExpression("^\\s[A-Za-z0-9._\\-/()]*[./][A-Za-z0-9._\\-/()]*\\d[A-Za-z0-9._\\-/()]*")

    /// The reference text used for matching fields: DOIs and URLs are blanked out (same length, so
    /// highlights still line up), because "amr" in "10.5465/amr.2011.0396" or "icis2020" in an AISeL
    /// link is not the reference naming its venue. The DOI field is checked separately.
    public static func matchingText(_ raw: String) -> NormalizedText {
        var chars = Array(raw)
        for m in linkRx.allMatches(in: raw) {
            guard let r = Range(m.range, in: raw) else { continue }
            var span = raw.characterOffsets(of: r)
            let rest = String(raw[r.upperBound...])
            if let tail = linkTailRx.firstMatch(in: rest), let t = Range(tail.range, in: rest) {
                span = span.lowerBound..<(span.upperBound + rest.distance(from: rest.startIndex, to: t.upperBound))
            }
            for i in span where i < chars.count { chars[i] = " " }
        }
        return NormalizedText(String(chars))
    }

    /// Abbreviation parts used to recognise a longer abbreviation around a match.
    private static let abbreviationParts: Set<String> = Set(ISO4.ltwa.map { NormalizedText.key($0.abbreviation) })
    /// What may follow a journal name in a reference.
    private static let venueFollowers: Set<String> = [
        "vol", "volume", "vols", "v", "no", "nr", "n", "issue", "iss", "pp", "p", "s", "art", "article", "e",
        "doi", "https", "http", "www", "in", "bd", "jg", "heft", "online", "advance", "press", "forthcoming",
        "accepted", "retrieved", "available", "special", "suppl", "supplement"
    ]

    /// Finds a journal abbreviation as whole words that are not part of a longer abbreviation:
    /// "Inf. Syst." (Information Systems) must not match "Inf. Syst. Res." (Information Systems Research)
    /// nor "Eur. J. Inf. Syst." when looking for "J. Inf. Syst.".
    static func findAbbreviation(_ abbreviation: String, in text: NormalizedText) -> Range<Int>? {
        guard NormalizedText.key(abbreviation).count >= 3, let r = text.findWords(abbreviation) else { return nil }
        if let next = text.tokens.first(where: { $0.range.lowerBound >= r.upperBound }),
           !next.key.allSatisfy(\.isNumber), !venueFollowers.contains(next.key) {
            return nil
        }
        if let previous = text.tokens.last(where: { $0.range.upperBound <= r.lowerBound }),
           abbreviationParts.contains(previous.key),
           text.characters.indices.contains(previous.range.upperBound),
           text.characters[previous.range.upperBound] == "." {
            return nil
        }
        return r
    }

    static func removeOverlaps(_ highlights: [Highlight]) -> [Highlight] {
        var result: [Highlight] = []
        for h in highlights.sorted(by: { ($0.start, -$0.end) < ($1.start, -$1.end) }) {
            if let last = result.last, h.start < last.end { continue }
            result.append(h)
        }
        return result
    }

    /// How well a candidate record fits the reference text (used to pick the best hit).
    public struct Score: Comparable, Sendable {
        public var title: Double
        public var authors: Double
        public var year: Bool
        public var total: Double { title * 0.7 + authors * 0.2 + (year ? 0.1 : 0) }

        public var isAcceptable: Bool { title >= 0.6 && total >= 0.6 }
        public var isConvincing: Bool { title >= 0.99 && authors >= 0.5 }

        public static func < (a: Score, b: Score) -> Bool { a.total < b.total }
    }

    public static func score(_ meta: RetrievedMetadata, for ref: ParsedReference, text: NormalizedText) -> Score {
        let title = text.find(meta.title) != nil ? 1.0 : text.wordCoverage(of: meta.title)
        let considered = meta.authors.prefix(5)
        let authors = considered.isEmpty ? 0.5
            : Double(considered.filter { text.findWords($0.family) != nil || text.containsWord(String($0.family.split(separator: " ").last ?? "")) }.count) / Double(considered.count)
        let years = [meta.year].compactMap { $0 } + meta.alternativeYears
        let year = ref.year.map { years.contains($0) } ?? false
        return Score(title: title, authors: authors, year: year)
    }
}
