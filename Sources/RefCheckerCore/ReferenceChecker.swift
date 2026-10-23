import Foundation

public struct CheckerConfiguration: Hashable, Sendable {
    /// E-mail sent to Crossref/OpenAlex for their "polite pool" (faster, more reliable).
    public var contactEmail: String?
    public var useCrossref: Bool
    public var useDBLP: Bool
    public var useOpenAlex: Bool
    /// Resolve AIS conference papers (ICIS, ECIS, AMCIS, PACIS, WI, …) at aisel.aisnet.org.
    public var useAISeL: Bool
    public var options: ComparisonOptions

    public init(contactEmail: String? = nil, useCrossref: Bool = true, useDBLP: Bool = true,
                useOpenAlex: Bool = true, useAISeL: Bool = true, options: ComparisonOptions = ComparisonOptions()) {
        self.contactEmail = contactEmail?.nilIfEmpty
        self.useCrossref = useCrossref
        self.useDBLP = useDBLP
        self.useOpenAlex = useOpenAlex
        self.useAISeL = useAISeL
        self.options = options
    }
}

/// Looks up one reference at the configured providers and compares it.
///
/// Order: DOI given in the reference → Crossref search → DBLP → OpenAlex; stops
/// as soon as a candidate convincingly matches, otherwise takes the best one.
/// AIS conference papers are then resolved at the AIS eLibrary, whose record
/// replaces the generic one (which often lacks them or files them under the
/// Journal of the AIS).
public final class ReferenceChecker: Sendable {
    private let configuration: CheckerConfiguration
    private let doiResolver: DOIResolver
    private let providers: [any MetadataProvider]
    private let aisel: AISeLProvider?

    public init(configuration: CheckerConfiguration) {
        self.configuration = configuration
        let mail = configuration.contactEmail
        let http = HTTPClient(userAgent: "RefChecker/1.0 (macOS reference checker\(mail.map { "; mailto:\($0)" } ?? ""))")
        doiResolver = DOIResolver(http: http)
        var providers: [any MetadataProvider] = []
        if configuration.useCrossref { providers.append(CrossrefProvider(http: http, mailto: mail)) }
        if configuration.useDBLP { providers.append(DBLPProvider(http: http)) }
        if configuration.useOpenAlex { providers.append(OpenAlexProvider(http: http, mailto: mail)) }
        self.providers = providers
        self.aisel = configuration.useAISeL ? AISeLProvider(http: http) : nil
    }

    private struct Search {
        let ref: ParsedReference
        let text: NormalizedText
        var best: (meta: RetrievedMetadata, score: Comparator.Score)?
        var seen: [RetrievedMetadata] = []
        var queried: Set<String> = []
        var notes: [String] = []
        var errors: [String] = []

        init(_ ref: ParsedReference) {
            self.ref = ref
            self.text = NormalizedText(ref.raw)
        }

        func score(_ m: RetrievedMetadata) -> Comparator.Score {
            Comparator.score(m, for: ref, text: text)
        }

        mutating func consider(_ candidates: [RetrievedMetadata]) {
            seen += candidates
            for c in candidates {
                let s = score(c)
                if best == nil || s > best!.score { best = (c, s) }
            }
        }
    }

    public func check(_ ref: ParsedReference) async -> ReferenceResult {
        var search = Search(ref)

        if let doi = ref.doi {
            do {
                if let m = try await doiResolver.lookup(doi: doi) {
                    search.consider([m])
                } else {
                    search.notes.append("The DOI \(doi) given in the reference does not resolve.")
                }
            } catch {
                search.errors.append("doi.org: \(error.localizedDescription)")
            }
        }

        for provider in providers {
            if search.best?.score.isConvincing == true || Task.isCancelled { break }
            await query(provider, &search)
        }

        if let aisel, !Task.isCancelled, needsAISeL(search) {
            await resolveAtAISeL(aisel, &search)
        }

        guard let match = search.best, match.score.isAcceptable else {
            if !search.errors.isEmpty && search.best == nil {
                return ReferenceResult(reference: ref, metadata: nil, fields: [], highlights: [],
                                       verdict: .failed(search.errors.joined(separator: "\n")),
                                       notes: search.notes + search.errors)
            }
            var note = "No matching record found" + (providers.isEmpty && aisel == nil ? " (all providers are disabled)." : ".")
            if AISeLProvider.mentionsAIS(ref) {
                note += " AIS conference papers without DOI are often only listed in the AIS eLibrary; adding the aisel.aisnet.org link to the reference lets the app read it directly."
            }
            search.notes.append(note)
            return ReferenceResult(reference: ref, metadata: nil, fields: [], highlights: [],
                                   verdict: .notFound, notes: search.notes)
        }

        // Corroborate: unless a publisher-registered record was identified with certainty,
        // also ask the providers that were skipped, so fields can be confirmed independently.
        var identification = identify(match, search)
        if match.meta.authority < .publisher || identification.level < .certain {
            for provider in providers where !Task.isCancelled {
                await query(provider, &search)
            }
            identification = identify(match, search)
        }

        var notes = search.notes
        let comparison = Comparator.compare(ref, with: match.meta, options: configuration.options)
        let others = corroborating(search, excluding: match.meta)
        let fields = comparison.fields.map { confirm($0, match.meta, others, identification, ref) }
        let highlights = comparison.highlights.map { h -> Highlight in
            // Text highlights follow the field decision: nothing unconfirmed is shown green.
            let fieldStatus = fields.first { $0.field == h.field }?.status
            guard h.status == .match, identification.level == .probable || fieldStatus == .unconfirmed else { return h }
            return Highlight(h.start..<h.end, .unconfirmed, field: h.field)
        }
        if let given = ref.doi, let found = match.meta.doi, given.lowercased() != found.lowercased(),
           !notes.contains(where: { $0.contains(given) }) {
            notes.append("The DOI in the reference points to a different record than the best match.")
        }
        let problems = fields.filter { $0.status.isProblem }.count
        let unconfirmed = fields.filter { $0.status == .unconfirmed }.count
        let verdict: Verdict = problems > 0 ? .issues(problems) : (unconfirmed > 0 ? .needsReview(unconfirmed) : .verified)
        let consulted = (ref.doi != nil ? ["doi.org"] : []) + search.queried.sorted()
            + (search.seen.contains { $0.provider == AISeLProvider.name } ? [AISeLProvider.name] : [])
        let sources = consulted.map { name in
            (name: name, found: name == match.meta.provider || others.contains { $0.provider == name })
        }
        return ReferenceResult(reference: ref, metadata: match.meta, identification: identification, sources: sources,
                               fields: fields, highlights: Comparator.removeOverlaps(highlights),
                               verdict: verdict, notes: notes)
    }

    /// How certain it is that `match` is the work the reference means.
    private func identify(_ match: (meta: RetrievedMetadata, score: Comparator.Score), _ search: Search) -> Identification {
        let meta = match.meta, ref = search.ref
        if let doi = ref.doi, meta.doi?.lowercased() == doi.lowercased(), match.score.title >= 0.6 {
            return Identification(.certain, "The DOI printed in the reference resolves to this record.")
        }
        let linked = AISeLProvider.urls(in: ref).map { $0.lowercased() }
        if !linked.isEmpty, (meta.links + [meta.url].compactMap { $0 }).contains(where: { l in linked.contains { $0.hasPrefix(l.lowercased()) || l.lowercased().hasPrefix($0) } }) {
            return Identification(.certain, "The link printed in the reference leads to this record.")
        }
        if match.score.title >= 0.99 && match.score.authors >= 0.99 && match.score.year {
            return Identification(.high, "Found by search; title, all authors and the year agree with the reference.")
        }
        var differs: [String] = []
        if match.score.title < 0.99 { differs.append("title") }
        if match.score.authors < 0.99 { differs.append("authors") }
        if !match.score.year { differs.append("year") }
        return Identification(.probable, "Found by search, but the \(differs.joined(separator: ", ")) only partly agree – it may be a different work (e.g. a later journal version).")
    }

    /// Records from other providers that describe the same work (one per provider).
    private func corroborating(_ search: Search, excluding best: RetrievedMetadata) -> [RetrievedMetadata] {
        var byProvider: [String: (RetrievedMetadata, Comparator.Score)] = [:]
        for c in search.seen where c.provider != best.provider {
            let s = search.score(c)
            let sameWork = Similarity.ratio(c.title, best.title) >= 0.95 && s.authors >= 0.5
            guard sameWork else { continue }
            if let existing = byProvider[c.provider], existing.1 >= s { continue }
            byProvider[c.provider] = (c, s)
        }
        return byProvider.values.map(\.0).sorted { $0.authority > $1.authority }
    }

    /// Decides whether a matching field is shown as confirmed (green) or unconfirmed (amber),
    /// and records the evidence from every source.
    private func confirm(_ field: FieldComparison, _ best: RetrievedMetadata, _ others: [RetrievedMetadata],
                         _ identification: Identification, _ ref: ParsedReference) -> FieldComparison {
        var f = field
        var evidence = [Evidence(source: best.provider, authority: best.authority, value: field.retrieved,
                                 agrees: field.status == .unavailable ? nil : field.status == .match || field.status == .unconfirmed)]
        var strictlyAgreeing: [Evidence] = []
        for other in others {
            let theirs = Comparator.compare(ref, with: other, options: configuration.options).fields
                .first { $0.field == field.field || (field.field == "Publisher" && $0.field == "Venue") }
            let agrees: Bool? = theirs.flatMap { $0.status == .unavailable ? nil : ($0.status == .match || $0.status == .unconfirmed) }
            let e = Evidence(source: other.provider, authority: other.authority, value: theirs?.retrieved, agrees: agrees)
            evidence.append(e)
            if theirs?.status == .match { strictlyAgreeing.append(e) }
        }
        f.evidence = evidence

        let agreeing = evidence.filter { $0.agrees == true }
        let disagreeingPublishers = evidence.filter { $0.agrees == false && $0.authority == .publisher }
        let describe = { (e: [Evidence]) in e.map { "\($0.source) (\($0.authority.label))" }.joined(separator: ", ") }

        switch field.status {
        case .match:
            if identification.level == .probable {
                f.status = .unconfirmed
                f.explanation = "Matches \(best.provider), but it is uncertain whether that record is the cited work."
            } else if !disagreeingPublishers.isEmpty {
                f.status = .unconfirmed
                f.explanation = "Sources disagree: \(describe(disagreeingPublishers)) has a different value."
            } else if best.authority == .publisher || agreeing.count >= 2 {
                f.explanation = "Confirmed by " + describe(agreeing) + "."
            } else {
                f.status = .unconfirmed
                f.explanation = "Only \(describe(agreeing)) supports this; no second source could confirm it."
            }
            if f.status == .match, field.isLiteral == false {
                f.explanation! += " Identical apart from capitalisation, punctuation or accents."
            }
        case .unconfirmed:
            f.explanation = field.note
            // Affiliations were set aside on wording alone; an independent source whose author list
            // matches the reference exactly confirms that decision.
            if field.field == "Authors", identification.level != .probable,
               best.ignoredAuthors.contains(where: { !$0.isCertain }),
               !(field.note ?? "").contains("probably an affiliation"),
               !strictlyAgreeing.isEmpty {
                f.status = .match
                f.explanation = "Confirmed by \(describe(strictlyAgreeing)); \(best.provider)'s extra entries are affiliations."
            }
        case .mismatch, .missing:
            let backing = evidence.dropFirst().filter { $0.agrees == true }
            f.explanation = backing.isEmpty
                ? "\(best.provider) (\(best.authority.label)) has a different value."
                : "\(best.provider) has a different value, but \(describe(Array(backing))) agrees with the reference – check manually."
            // An equally trustworthy source backing the reference makes it a conflict, not an error.
            if f.status == .mismatch, backing.contains(where: { $0.authority >= best.authority }) { f.status = .unconfirmed }
        case .unavailable:
            f.explanation = "No source has this field."
        }
        return f
    }

    private func query(_ provider: any MetadataProvider, _ search: inout Search) async {
        guard search.queried.insert(provider.name).inserted else { return }
        do {
            search.consider(try await provider.search(search.ref))
        } catch {
            search.errors.append("\(provider.name): \(error.localizedDescription)")
        }
    }

    /// AISeL is consulted when the reference cites an AIS outlet, when the best record
    /// is attributed to an AIS outlet the reference does not name, or when nothing was found.
    private func needsAISeL(_ search: Search) -> Bool {
        guard let best = search.best, best.score.isAcceptable else { return true }
        if best.meta.provider == AISeLProvider.name { return false }
        if AISeLProvider.mentionsAIS(search.ref) { return true }
        guard AISeLProvider.hasAISVenue(best.meta) else { return false }
        return best.meta.venue.map { search.text.find($0) == nil } ?? true
    }

    private func resolveAtAISeL(_ aisel: AISeLProvider, _ search: inout Search) async {
        let previous = search.best

        // 1. AISeL links in the reference, then in records already retrieved.
        var tried = Set<String>()
        func links(_ s: Search) -> [String] {
            (AISeLProvider.urls(in: s.ref) + s.seen.flatMap(\.links)).filter(AISeLProvider.isAISeLURL)
        }
        var record = await firstAcceptableRecord(aisel, links(search), &tried, search)

        // 2. DBLP and OpenAlex usually link conference papers to their AISeL page.
        if record == nil {
            for provider in providers where provider.name != "Crossref" && !search.queried.contains(provider.name) {
                await query(provider, &search)
                record = await firstAcceptableRecord(aisel, links(search), &tried, search)
                if record != nil { break }
            }
        }

        // 3. The AISeL site search.
        if record == nil {
            do {
                let hits = try await aisel.search(search.ref)
                record = hits.map { ($0, search.score($0)) }.filter { $0.1.isAcceptable }.max { $0.1 < $1.1 }?.0
            } catch {
                search.errors.append("\(AISeLProvider.name): \(error.localizedDescription)")
            }
        }

        guard let record else {
            if let prev = previous?.meta, AISeLProvider.mentionsAIS(search.ref), AISeLProvider.hasAISVenue(prev),
               let venue = prev.venue, search.text.find(venue) == nil {
                search.notes.append("\(prev.provider) attributes this paper to “\(venue)”. AIS conference papers are sometimes filed under an AIS journal there – the AIS eLibrary page could not be found to verify the venue.")
            }
            return
        }
        let score = search.score(record)
        // Prefer the AISeL record unless the generic hit fits the title clearly better.
        if let prev = previous, prev.score.title > score.title + 0.1 { return }
        if let prev = previous?.meta, let oldVenue = prev.venue,
           NormalizedText.key(oldVenue) != NormalizedText.key(record.venue ?? "") {
            search.notes.append("\(prev.provider) attributes this paper to “\(oldVenue)”; the AIS eLibrary record was used instead.")
        }
        search.best = (record, score)
    }

    private func firstAcceptableRecord(_ aisel: AISeLProvider, _ urls: [String], _ tried: inout Set<String>,
                                       _ search: Search) async -> RetrievedMetadata? {
        for url in urls where tried.insert(url).inserted {
            guard let record = try? await aisel.record(at: url) else { continue }
            if search.score(record).isAcceptable { return record }
        }
        return nil
    }
}
