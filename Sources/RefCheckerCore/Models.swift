import Foundation

/// One entry of the paper's reference list, as parsed from the text.
public struct ParsedReference: Identifiable, Hashable, Sendable {
    public let id: Int
    /// Label as printed in the paper, e.g. "1" for "[1]" or "Smi20".
    public var label: String
    /// The full reference text (line breaks joined).
    public var raw: String
    public var authorsText: String?
    public var title: String?
    public var venue: String?
    public var year: String?
    public var doi: String?
    public var hasEtAl: Bool

    public init(id: Int, label: String, raw: String, authorsText: String? = nil, title: String? = nil,
                venue: String? = nil, year: String? = nil, doi: String? = nil, hasEtAl: Bool = false) {
        self.id = id
        self.label = label
        self.raw = raw
        self.authorsText = authorsText
        self.title = title
        self.venue = venue
        self.year = year
        self.doi = doi
        self.hasEtAl = hasEtAl
    }
}

public struct Author: Hashable, Sendable {
    public var given: String?
    public var family: String

    public init(given: String?, family: String) {
        self.given = given
        self.family = family
    }

    public var display: String {
        [given, family].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Bibliographic record returned by an online provider.
public struct RetrievedMetadata: Hashable, Sendable {
    public var provider: String
    public var title: String
    public var subtitle: String?
    public var authors: [Author]
    public var year: String?
    /// Other plausible publication years (online-first vs. print).
    public var alternativeYears: [String]
    public var venue: String?
    public var venueAliases: [String]
    public var volume: String?
    public var issue: String?
    public var pages: String?
    public var doi: String?
    public var publisher: String?
    public var type: String?
    public var url: String?
    /// Landing pages known for this record (used to find the AIS eLibrary page).
    public var links: [String]
    /// Entries the provider listed as authors that are affiliations; excluded from `authors`.
    public var ignoredAuthors: [IgnoredAuthor] = []

    public init(provider: String, title: String, subtitle: String? = nil, authors: [Author] = [],
                year: String? = nil, alternativeYears: [String] = [], venue: String? = nil,
                venueAliases: [String] = [], volume: String? = nil, issue: String? = nil,
                pages: String? = nil, doi: String? = nil, publisher: String? = nil,
                type: String? = nil, url: String? = nil, links: [String] = []) {
        self.provider = provider
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.year = year
        self.alternativeYears = alternativeYears
        self.venue = venue
        self.venueAliases = venueAliases
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.doi = doi
        self.publisher = publisher
        self.type = type
        self.url = url
        self.links = links
    }

    public var fullTitle: String {
        guard let subtitle, !subtitle.isEmpty,
              !NormalizedText.key(title).contains(NormalizedText.key(subtitle)) else { return title }
        return "\(title): \(subtitle)"
    }

    /// How trustworthy the source of this record is.
    public var authority: SourceAuthority { SourceAuthority(provider: provider) }

    public var isBook: Bool {
        ["book", "monograph", "edited-book", "reference-book", "Books and Theses"].contains(type ?? "")
    }

    /// A readable citation built from the retrieved fields.
    public var formattedCitation: String {
        var s = ""
        if !authors.isEmpty {
            s += authors.map(\.display).joined(separator: ", ")
            s += " "
        }
        s += "(\(year ?? "n.d.")). \(fullTitle)."
        var venuePart = venue ?? (isBook ? publisher : nil) ?? ""
        if let volume, !volume.isEmpty {
            venuePart += venuePart.isEmpty ? "Vol. \(volume)" : ", \(volume)"
            if let issue, !issue.isEmpty { venuePart += "(\(issue))" }
        }
        if let pages, !pages.isEmpty { venuePart += venuePart.isEmpty ? "pp. \(pages)" : ", \(pages)" }
        if !venuePart.isEmpty { s += " \(venuePart)." }
        if let doi, !doi.isEmpty { s += " https://doi.org/\(doi)" }
        return s
    }
}

/// An entry a provider listed as author that is really an affiliation (university, company …).
public struct IgnoredAuthor: Hashable, Sendable {
    public var name: String
    /// true when the provider itself labels the string as an affiliation; false when it was
    /// recognised only by its wording ("University", "GmbH" …).
    public var isCertain: Bool
    public var reason: String

    public init(name: String, isCertain: Bool, reason: String) {
        self.name = name
        self.isCertain = isCertain
        self.reason = reason
    }
}

/// How much a metadata source can be trusted.
public enum SourceAuthority: Int, Comparable, Sendable {
    /// Machine-aggregated from many sources (OpenAlex); known to misattribute venues.
    case aggregated
    /// Curated by an editorial team (DBLP).
    case curated
    /// Registered by the publisher itself: DOI metadata (doi.org, Crossref) or the publisher's
    /// own landing page (AIS eLibrary).
    case publisher

    public init(provider: String) {
        switch provider {
        case "doi.org", "Crossref", "AIS eLibrary": self = .publisher
        case "DBLP": self = .curated
        default: self = .aggregated
        }
    }

    public var label: String {
        switch self {
        case .publisher: return "publisher-registered"
        case .curated: return "curated database"
        case .aggregated: return "aggregated database"
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// How certain it is that the retrieved record is the work the reference means.
public struct Identification: Hashable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case probable, high, certain
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public var level: Level
    public var reason: String

    public init(_ level: Level, _ reason: String) {
        self.level = level
        self.reason = reason
    }

    public var title: String {
        switch level {
        case .certain: return "Identified with certainty"
        case .high: return "Identified with high confidence"
        case .probable: return "Identification uncertain"
        }
    }
}

/// What one source says about one field.
public struct Evidence: Hashable, Sendable {
    public var source: String
    public var authority: SourceAuthority
    public var value: String?
    /// true: agrees with the reference, false: differs, nil: source has no value.
    public var agrees: Bool?

    public init(source: String, authority: SourceAuthority, value: String?, agrees: Bool?) {
        self.source = source
        self.authority = authority
        self.value = value
        self.agrees = agrees
    }
}

public enum MatchStatus: String, Sendable {
    /// Confirmed (green): identical to a record that was identified with certainty or high
    /// confidence, and backed by a publisher-registered source or by two independent sources.
    case match
    /// Matches, but the evidence is weaker (amber): a single non-publisher source, an uncertain
    /// identification, disagreeing sources, or a number that is present but not clearly placed.
    case unconfirmed
    /// Reference contains a different value (red).
    case mismatch
    /// Metadata has a value the reference does not give (red – incomplete).
    case missing
    /// The provider has no value for this field, nothing to compare (grey).
    case unavailable

    public var isProblem: Bool { self == .mismatch || self == .missing }

    public var title: String {
        switch self {
        case .match: return "Confirmed"
        case .unconfirmed: return "Unconfirmed match"
        case .mismatch: return "Mismatch"
        case .missing: return "Missing in reference"
        case .unavailable: return "No data"
        }
    }
}

public struct FieldComparison: Identifiable, Hashable, Sendable {
    public var id: String { field }
    public var field: String
    public var original: String?
    public var retrieved: String?
    public var status: MatchStatus
    public var note: String?
    /// For text fields: the reference spells it character for character like the record
    /// (false: identical only when ignoring capitalisation, punctuation or accents).
    public var isLiteral: Bool?
    /// What each consulted source says about this field.
    public var evidence: [Evidence]
    /// Why the field got its colour, in words.
    public var explanation: String?

    public init(field: String, original: String?, retrieved: String?, status: MatchStatus, note: String? = nil,
                isLiteral: Bool? = nil, evidence: [Evidence] = [], explanation: String? = nil) {
        self.field = field
        self.original = original
        self.retrieved = retrieved
        self.status = status
        self.note = note
        self.isLiteral = isLiteral
        self.evidence = evidence
        self.explanation = explanation
    }
}

/// A coloured span in `ParsedReference.raw`, in Character offsets.
public struct Highlight: Hashable, Sendable {
    public var start: Int
    public var end: Int
    public var status: MatchStatus
    /// The field this span belongs to, so it can follow the field's final colour.
    public var field: String?

    public init(_ range: Range<Int>, _ status: MatchStatus, field: String? = nil) {
        self.start = range.lowerBound
        self.end = range.upperBound
        self.status = status
        self.field = field
    }
}

public enum Verdict: Hashable, Sendable {
    case verified
    case needsReview(Int)
    case issues(Int)
    case notFound
    case failed(String)

    public var title: String {
        switch self {
        case .verified: return "Verified"
        case .needsReview(let n): return n == 1 ? "1 field unconfirmed" : "\(n) fields unconfirmed"
        case .issues(let n): return n == 1 ? "1 issue" : "\(n) issues"
        case .notFound: return "Not found"
        case .failed: return "Lookup failed"
        }
    }
}

public struct ReferenceResult: Identifiable, Sendable {
    public var id: Int { reference.id }
    public var reference: ParsedReference
    public var metadata: RetrievedMetadata?
    public var identification: Identification?
    /// Every source consulted, with whether it found this work.
    public var sources: [(name: String, found: Bool)]
    public var fields: [FieldComparison]
    public var highlights: [Highlight]
    public var verdict: Verdict
    public var notes: [String]

    public init(reference: ParsedReference, metadata: RetrievedMetadata?, identification: Identification? = nil,
                sources: [(name: String, found: Bool)] = [], fields: [FieldComparison],
                highlights: [Highlight], verdict: Verdict, notes: [String]) {
        self.reference = reference
        self.metadata = metadata
        self.identification = identification
        self.sources = sources
        self.fields = fields
        self.highlights = highlights
        self.verdict = verdict
        self.notes = notes
    }
}

/// The user's decision that a reference is fine despite the automatic findings.
/// It changes only the verdict; the field colours and evidence stay as computed.
public struct Resolution: Codable, Hashable, Sendable {
    public var date: Date
    public var note: String?

    public init(date: Date = Date(), note: String? = nil) {
        self.date = date
        self.note = note
    }

    /// Resolutions are stored by the reference text (normalised), so they survive
    /// re-checking, re-splitting and reopening the paper.
    public static func key(for reference: ParsedReference) -> String {
        NormalizedText.key(reference.raw)
    }
}

public struct ComparisonOptions: Hashable, Sendable {
    /// Report a missing DOI as an issue.
    public var requireDOI: Bool
    /// Compare volume, issue and pages.
    public var checkVolumeIssuePages: Bool

    public init(requireDOI: Bool = true, checkVolumeIssuePages: Bool = true) {
        self.requireDOI = requireDOI
        self.checkVolumeIssuePages = checkVolumeIssuePages
    }
}
