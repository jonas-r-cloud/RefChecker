import Foundation

/// Evidence that the reference list was extracted completely: every piece of its text belongs
/// to a reference, the numbering has no gaps or duplicates, and no entry looks like two
/// references run together or like a fragment.
public struct ExtractionReport: Sendable {
    public struct Numbering: Sendable {
        public var first: Int
        public var last: Int
        public var missing: [Int]
        public var duplicates: [Int]
    }

    public struct Finding: Hashable, Sendable {
        public var label: String
        public var reason: String
    }

    public var count: Int
    public var numbering: Numbering?
    /// Text of the reference list that is not part of any reference.
    public var leftovers: [String]
    /// Entries that may be two references, or a fragment of one.
    public var suspicious: [Finding]

    public var isComplete: Bool {
        leftovers.isEmpty && (numbering.map { $0.missing.isEmpty && $0.duplicates.isEmpty } ?? true)
    }

    private static let apaYearRx = NSRegularExpression("\\((?:1[89]\\d{2}|20\\d{2})[a-z]?\\)\\.")
    private static let labelNumberRx = NSRegularExpression("^(\\d+)[a-z]?$")
    /// The next reference's number at the end of a gap ("… [12").
    private static let trailingMarkerRx = NSRegularExpression("(?:\\s*\\[?\\d+[a-z]?[\\].)]?)+$")

    public static func analyze(section: String, entries: [ReferenceSplitter.Entry]) -> ExtractionReport {
        // 1. Coverage: find every entry, in order, in the list text; whatever lies between is left over.
        let text = NormalizedText(ReferenceSplitter.clean(section))
        var covered: [Range<Int>] = []
        var cursor = 0
        for entry in entries {
            if !entry.marker.isEmpty, let r = text.find(entry.marker, from: cursor), r.lowerBound - cursor < 40 {
                covered.append(r)
                cursor = r.upperBound
            }
            // Long entries are located by their beginning and end, so line-break repairs do not matter.
            let probe = String(entry.text.prefix(60))
            guard let start = text.find(probe, from: cursor) else { continue }
            var end = start.upperBound
            if entry.text.count > 60, let tail = text.find(String(entry.text.suffix(40)), from: start.lowerBound) {
                end = tail.upperBound
            }
            covered.append(start.lowerBound..<end)
            cursor = end
        }
        var leftovers: [String] = []
        var position = 0
        for r in covered.sorted(by: { $0.lowerBound < $1.lowerBound }) + [text.characters.count..<text.characters.count] {
            if r.lowerBound > position {
                let edges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
                let gap = trailingMarkerRx.replacing(in: text.text(position..<r.lowerBound).trimmingCharacters(in: edges), with: "")
                    .trimmingCharacters(in: edges)
                if NormalizedText.key(gap).count >= 4 {
                    leftovers.append(gap.count > 160 ? String(gap.prefix(160)) + "…" : gap)
                }
            }
            position = max(position, r.upperBound)
        }

        // 2. Numbering (only for numbered lists): gaps and duplicates.
        let numbers = entries.compactMap { e -> Int? in
            guard let m = labelNumberRx.firstMatch(in: e.label), !e.marker.isEmpty else { return nil }
            return e.label.substring(with: m.range(at: 1)).flatMap { Int($0) }
        }
        var numbering: Numbering?
        if numbers.count >= 2, let first = numbers.min(), let last = numbers.max() {
            let counts = Dictionary(numbers.map { ($0, 1) }, uniquingKeysWith: +)
            numbering = Numbering(first: first, last: last,
                                  missing: (first...last).filter { counts[$0] == nil },
                                  duplicates: counts.filter { $0.value > 1 }.map(\.key).sorted())
        }

        // 3. Entries that look wrong.
        var suspicious: [Finding] = []
        for e in entries {
            if apaYearRx.allMatches(in: e.text).count >= 2 {
                suspicious.append(Finding(label: e.label, reason: "contains two “(Year).” – probably two references"))
            } else if e.text.count > 700 {
                suspicious.append(Finding(label: e.label, reason: "unusually long – may contain several references"))
            } else if e.text.count < 30 {
                suspicious.append(Finding(label: e.label, reason: "very short – probably a fragment of another reference"))
            } else if ReferenceParser.extractYear(e.text) == nil, !e.text.lowercased().contains("n.d") {
                suspicious.append(Finding(label: e.label, reason: "no year – may be a fragment of another reference"))
            }
        }
        return ExtractionReport(count: entries.count, numbering: numbering, leftovers: leftovers, suspicious: suspicious)
    }
}
