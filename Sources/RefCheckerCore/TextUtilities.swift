import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }

    func substring(with range: NSRange) -> String? {
        guard range.location != NSNotFound, let r = Range(range, in: self) else { return nil }
        return String(self[r])
    }

    var fullNSRange: NSRange { NSRange(startIndex..., in: self) }

    /// Character-offset range of a String range.
    func characterOffsets(of range: Range<String.Index>) -> Range<Int> {
        let lower = distance(from: startIndex, to: range.lowerBound)
        return lower..<(lower + distance(from: range.lowerBound, to: range.upperBound))
    }

    func trimmingCharacters(_ chars: String) -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: chars).union(.whitespacesAndNewlines))
    }
}

extension NSRegularExpression {
    convenience init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // Patterns are compile-time constants; a failure is a programming error.
        try! self.init(pattern: pattern, options: options)
    }

    func firstMatch(in s: String) -> NSTextCheckingResult? {
        firstMatch(in: s, options: [], range: s.fullNSRange)
    }

    func allMatches(in s: String) -> [NSTextCheckingResult] {
        matches(in: s, options: [], range: s.fullNSRange)
    }

    /// The pieces of `s` between matches.
    func split(_ s: String) -> [String] {
        var pieces: [String] = []
        var last = s.startIndex
        for m in allMatches(in: s) {
            guard let r = Range(m.range, in: s) else { continue }
            pieces.append(String(s[last..<r.lowerBound]))
            last = r.upperBound
        }
        pieces.append(String(s[last...]))
        return pieces
    }

    func replacing(in s: String, with template: String) -> String {
        stringByReplacingMatches(in: s, options: [], range: s.fullNSRange, withTemplate: template)
    }
}

public enum Markup {
    private static let tagRx = NSRegularExpression("<[^>]+>")
    private static let spaceRx = NSRegularExpression("\\s+")
    private static let numericEntityRx = NSRegularExpression("&#([xX]?)([0-9a-fA-F]+);")

    /// Removes JATS/HTML tags and common entities from provider titles.
    public static func clean(_ s: String) -> String {
        var t = tagRx.replacing(in: s, with: "")
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                               ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        for m in numericEntityRx.allMatches(in: t).reversed() {
            guard let r = Range(m.range, in: t), let digits = t.substring(with: m.range(at: 2)) else { continue }
            let hex = !(t.substring(with: m.range(at: 1)) ?? "").isEmpty
            if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                t.replaceSubrange(r, with: String(Character(scalar)))
            }
        }
        return spaceRx.replacing(in: t, with: " ").trimmed
    }
}

/// Text folded for comparison (case, diacritics, ligatures, punctuation and
/// whitespace are ignored), with a map back to the original characters so
/// matches can be highlighted in the original reference.
public struct NormalizedText: Sendable {
    public struct Token: Sendable {
        public let key: String
        public let range: Range<Int>
    }

    public let characters: [Character]
    public let tokens: [Token]
    private let folded: [Character]
    private let map: [Int]
    private let tokenKeys: Set<String>

    public init(_ text: String) {
        let chars = Array(text)
        var folded: [Character] = []
        var map: [Int] = []
        var tokens: [Token] = []
        var currentKey = ""
        var currentStart: Int?
        for (i, c) in chars.enumerated() {
            let f = NormalizedText.fold(c)
            if f.isEmpty {
                if let s = currentStart {
                    tokens.append(Token(key: currentKey, range: s..<i))
                    currentStart = nil
                    currentKey = ""
                }
                continue
            }
            if currentStart == nil { currentStart = i }
            currentKey += f
            for fc in f {
                folded.append(fc)
                map.append(i)
            }
        }
        if let s = currentStart { tokens.append(Token(key: currentKey, range: s..<chars.count)) }
        self.characters = chars
        self.folded = folded
        self.map = map
        self.tokens = tokens
        self.tokenKeys = Set(tokens.map(\.key))
    }

    static func fold(_ c: Character) -> String {
        let s = String(c).precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars where CharacterSet.alphanumerics.contains(u) {
            out.append(u)
        }
        return String(out)
    }

    /// Comparison key: folded letters and digits only.
    public static func key(_ s: String) -> String {
        s.map(fold).joined()
    }

    public static func words(_ s: String) -> [String] {
        NormalizedText(s).tokens.map(\.key)
    }

    public func text(_ range: Range<Int>) -> String {
        String(characters[range.clamped(to: 0..<characters.count)])
    }

    /// Finds `needle` ignoring case, accents, punctuation and spacing, starting at character `from`.
    public func find(_ needle: String, from: Int = 0) -> Range<Int>? {
        let k = Array(NormalizedText.key(needle))
        guard !k.isEmpty, k.count <= folded.count else { return nil }
        var i = from == 0 ? 0 : (map.firstIndex { $0 >= from } ?? folded.count)
        while i + k.count <= folded.count {
            if folded[i] == k[0] {
                var j = 1
                while j < k.count && folded[i + j] == k[j] { j += 1 }
                if j == k.count { return map[i]..<(map[i + k.count - 1] + 1) }
            }
            i += 1
        }
        return nil
    }

    /// Finds `needle` as whole word(s), e.g. a family name like "van der Aalst".
    public func findWords(_ needle: String) -> Range<Int>? {
        let k = NormalizedText.key(needle)
        guard !k.isEmpty else { return nil }
        for i in tokens.indices {
            var acc = ""
            for j in i..<min(i + 12, tokens.count) {
                acc += tokens[j].key
                if acc == k { return tokens[i].range.lowerBound..<tokens[j].range.upperBound }
                if acc.count >= k.count || !k.hasPrefix(acc) { break }
            }
        }
        return nil
    }

    /// Indices of tokens equal to `word` (a single word or number).
    public func tokenIndices(of word: String) -> [Int] {
        let k = NormalizedText.key(word)
        guard !k.isEmpty else { return [] }
        return tokens.indices.filter { tokens[$0].key == k }
    }

    public func containsWord(_ word: String) -> Bool {
        tokenKeys.contains(NormalizedText.key(word)) || findWords(word) != nil
    }

    /// Fraction of the words of `other` that occur in this text.
    public func wordCoverage(of other: String) -> Double {
        let words = NormalizedText.words(other)
        guard !words.isEmpty else { return 0 }
        return Double(words.filter { tokenKeys.contains($0) }.count) / Double(words.count)
    }

    /// The span of this text that best resembles `target` (word overlap), used to
    /// show what the reference says where it differs from the metadata.
    public func bestWindow(for target: String, minimumScore: Double = 0.35) -> (range: Range<Int>, score: Double)? {
        let targetWords = NormalizedText.words(target)
        guard !targetWords.isEmpty, !tokens.isEmpty else { return nil }
        let targetSet = Set(targetWords)
        var best: (Range<Int>, Double)?
        let n = targetWords.count
        for length in max(1, n - 3)...(n + 3) {
            guard length <= tokens.count else { break }
            for start in 0...(tokens.count - length) {
                let window = tokens[start..<(start + length)].map(\.key)
                let common = Set(window).intersection(targetSet).count
                let score = Double(2 * common) / Double(window.count + targetWords.count)
                if score > (best?.1 ?? 0) {
                    best = (tokens[start].range.lowerBound..<tokens[start + length - 1].range.upperBound, score)
                }
            }
        }
        guard let b = best, b.1 >= minimumScore else { return nil }
        return b
    }
}

public enum Similarity {
    /// Levenshtein similarity (0…1) of the comparison keys of two strings.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let x = Array(NormalizedText.key(a)), y = Array(NormalizedText.key(b))
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}
