import Foundation

/// Compares a parsed reference with retrieved metadata field by field.
///
/// A field matches only if the metadata value occurs in the reference text exactly,
/// ignoring case, accents, punctuation and line breaks. Whether a match is shown as
/// confirmed (green) is decided afterwards by `ReferenceChecker`, from the evidence.
public enum Comparator {
    public static func compare(_ ref: ParsedReference, with meta: RetrievedMetadata,
                               options: ComparisonOptions = ComparisonOptions()) -> (fields: [FieldComparison], highlights: [Highlight]) {
        let text = NormalizedText(ref.raw)
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
        if venues.isEmpty {
            fields.append(FieldComparison(field: label, original: ref.venue, retrieved: nil, status: .unavailable))
        } else if let hit = venues.lazy.compactMap({ v in
            // Short names such as "ICIS" must occur as a word, not inside another word.
            (NormalizedText.key(v).count <= 6 ? text.findWords(v) : text.find(v)).map { (venue: v, range: $0) }
        }).first {
            highlights.append(Highlight(hit.range, .match, field: label))
            fields.append(FieldComparison(field: label, original: text.text(hit.range), retrieved: hit.venue, status: .match,
                                          isLiteral: isLiteral(text.text(hit.range), hit.venue)))
        } else {
            var original = ref.venue
            if let w = text.bestWindow(for: venues[0], minimumScore: 0.5) {
                original = text.text(w.range)
                highlights.append(Highlight(w.range, .mismatch, field: label))
            }
            let aliases = venues.count > 1 ? "Also known as: " + venues.dropFirst().joined(separator: "; ") : nil
            fields.append(FieldComparison(field: label, original: original, retrieved: venues[0],
                                          status: original == nil ? .missing : .mismatch, note: aliases))
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
            if let article = meta.articleNumber?.nilIfEmpty {
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
