import Foundation

/// A text line of a PDF page with its vertical position as fractions of the page
/// height measured from the top (0 = top edge, 1 = bottom edge). Positions are
/// nil when the PDF gives no usable geometry.
public struct PageLine: Hashable, Sendable {
    public var text: String
    public var top: Double?
    public var bottom: Double?

    public init(text: String, top: Double? = nil, bottom: Double? = nil) {
        self.text = text
        self.top = top
        self.bottom = bottom
    }
}

/// Removes running headers, footers, page numbers and publisher stamps from
/// extracted PDF text, so they do not end up inside references that continue
/// on the next page.
///
/// A line counts as header/footer if it lies in the top or bottom margin band
/// (or, without geometry, among the first/last lines of a page) and
/// - recurs on several pages (digits ignored, so "Page 3" ≈ "Page 4"), or
/// - is a page number, or
/// - is typical publisher boilerplate (copyright, "Downloaded from", arXiv stamp …).
public enum PageCleaner {
    public struct Result: Sendable {
        public var text: String
        public var removed: [String]
    }

    /// Fraction of the page height treated as header / footer band.
    static let band = 0.075
    /// Lines per page treated as margin candidates when there is no geometry.
    static let fallbackLines = 3

    private static let pageNumberRx = NSRegularExpression(
        "^(?:(?:page|seite|p\\.)\\s*)?[-–—(\\[]?\\s*(?:#+|[ivxlc]{1,6})\\s*[-–—)\\]]?(?:\\s*(?:of|/|von)\\s*#+)?$",
        options: [.caseInsensitive])
    private static let boilerplateRx = NSRegularExpression(
        "downloaded (from|on)|authorized licensed use|restrictions apply|all rights reserved|©|" +
        "licensed under|creative commons|arxiv:\\s*\\d|manuscript submitted to|accepted manuscript|" +
        "this article is protected|terms of use|for personal use only",
        options: [.caseInsensitive])
    /// Stamps that never belong to the text, wherever they are on the page.
    private static let stampRx = NSRegularExpression(
        "^arXiv:\\d{4}\\.\\d{4,5}(v\\d+)?\\s*\\[|authorized licensed use limited to|downloaded on .* from ieee xplore",
        options: [.caseInsensitive])
    private static let digitsRx = NSRegularExpression("\\d+")
    private static let spaceRx = NSRegularExpression("\\s+")

    static func signature(_ line: String) -> String {
        let s = digitsRx.replacing(in: line.lowercased(), with: "#")
        return spaceRx.replacing(in: s, with: " ").trimmed
    }

    public static func clean(pages: [[PageLine]]) -> Result {
        let pages = pages.map { $0.filter { !$0.text.trimmed.isEmpty } }

        // Which lines of each page sit in the margin bands.
        let marginFlags: [[Bool]] = pages.map { lines in
            lines.indices.map { i in
                let line = lines[i]
                if let top = line.top, let bottom = line.bottom {
                    return bottom <= band || top >= 1 - band
                }
                return i < fallbackLines || i >= lines.count - fallbackLines
            }
        }

        // How many pages have a given margin line (digits ignored).
        var counts: [String: Int] = [:]
        for (p, lines) in pages.enumerated() {
            let signatures = Set(lines.indices.filter { marginFlags[p][$0] && lines[$0].text.count <= 160 }
                .map { signature(lines[$0].text) })
            for s in signatures { counts[s, default: 0] += 1 }
        }
        let repeatThreshold = max(2, Int((Double(pages.count) * 0.3).rounded(.up)))

        var kept: [String] = []
        var removed: [String] = []
        for (p, lines) in pages.enumerated() {
            for (i, line) in lines.enumerated() {
                let text = line.text.trimmed
                let sig = signature(text)
                var drop = stampRx.firstMatch(in: text) != nil
                if !drop && marginFlags[p][i] {
                    drop = (pages.count > 1 && (counts[sig] ?? 0) >= repeatThreshold)
                        || pageNumberRx.firstMatch(in: sig) != nil
                        || (text.count <= 160 && boilerplateRx.firstMatch(in: text) != nil && isOutermost(i, of: lines, flags: marginFlags[p]))
                }
                if drop { removed.append(text) } else { kept.append(line.text) }
            }
        }
        return Result(text: kept.joined(separator: "\n"), removed: removed)
    }

    /// Boilerplate patterns are only trusted for the outermost lines of the page,
    /// so that a reference that happens to mention e.g. a licence is kept.
    private static func isOutermost(_ i: Int, of lines: [PageLine], flags: [Bool]) -> Bool {
        let leading = flags.prefix(while: { $0 }).count
        let trailing = flags.reversed().prefix(while: { $0 }).count
        let isLeading = i < min(leading, 2)
        let isTrailing = i >= lines.count - min(trailing, 2)
        // Geometry decides the band; never treat the whole page as margin.
        return (isLeading || isTrailing) && leading + trailing < lines.count
    }
}
