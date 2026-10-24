import Foundation

/// Printable side-by-side report.
public enum HTMLReport {
    public static func render(references: [ParsedReference], results: [Int: ReferenceResult],
                              source: String?, resolutions: [Int: Resolution] = [:],
                              citations: CitationIndex? = nil,
                              date: Date = Date()) -> String {
        let checked = references.compactMap { results[$0.id] }
        // A reference resolved by the user counts as verified.
        // Uncited references count as an issue; a reference resolved by the user counts as verified.
        func automatic(_ r: ReferenceResult) -> Verdict { citations?.adjusted(r.verdict, for: r.id) ?? r.verdict }
        func effective(_ r: ReferenceResult) -> Verdict { resolutions[r.id] != nil ? .verified : automatic(r) }
        func count(_ test: (Verdict) -> Bool) -> Int { checked.filter { test(effective($0)) }.count }
        let resolvedCount = checked.filter { resolutions[$0.id] != nil && automatic($0) != .verified }.count
        let verified = count { $0 == .verified }
        let review = count { if case .needsReview = $0 { return true }; return false }
        let withIssues = count { if case .issues = $0 { return true }; return false }
        let notFound = count { if case .notFound = $0 { return true }; if case .failed = $0 { return true }; return false }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <title>Reference check – \(escape(source ?? "paper"))</title>
        <style>
        * { -webkit-print-color-adjust: exact; print-color-adjust: exact; box-sizing: border-box; }
        body { font: 11px/1.4 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #1d1d1f; margin: 24px; }
        h1 { font-size: 18px; margin: 0 0 4px; }
        .meta { color: #6e6e73; margin-bottom: 12px; }
        .summary span { display: inline-block; padding: 2px 8px; border-radius: 10px; margin-right: 6px; }
        .ok { background: #c8f2cf; } .warn { background: #ffe2b3; } .bad { background: #ffc9c4; } .na { background: #ececec; }
        mark.ok { background: #a6e9b2; } mark.warn { background: #ffd28a; } mark.bad { background: #ffb0a8; }
        .legend { border: 1px solid #d2d2d7; border-radius: 6px; padding: 8px 10px; margin: 10px 0 14px; }
        .legend ol { margin: 4px 0 4px 18px; padding: 0; }
        .ref { border: 1px solid #d2d2d7; border-radius: 6px; margin: 12px 0; padding: 8px 10px; page-break-inside: avoid; }
        .ref.verified { border-left: 5px solid #34c759; } .ref.review { border-left: 5px solid #ff9500; }
        .ref.issues, .ref.notfound, .ref.failed { border-left: 5px solid #ff3b30; }
        .head { display: flex; gap: 8px; align-items: baseline; margin-bottom: 6px; }
        .label { font-weight: 700; } .badge { padding: 1px 7px; border-radius: 8px; font-size: 10px; font-weight: 600; }
        .src { margin-left: auto; color: #6e6e73; font-size: 10px; }
        .side { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 6px; }
        .side > div { background: #fafafa; border-radius: 4px; padding: 6px; }
        .cap { font-size: 9px; text-transform: uppercase; letter-spacing: .05em; color: #6e6e73; margin-bottom: 2px; }
        .ident { font-size: 10px; margin: 4px 0 6px; } .ident b { margin-right: 4px; }
        table { border-collapse: collapse; width: 100%; table-layout: fixed; }
        th, td { border: 1px solid #fff; padding: 3px 5px; text-align: left; vertical-align: top; word-wrap: break-word; }
        th { background: #f2f2f7; font-size: 10px; } td.f { width: 70px; font-weight: 600; background: #f2f2f7; }
        td.n { width: 30%; color: #3a3a3c; font-size: 10px; }
        .ev { color: #6e6e73; } .ev .y { color: #1f8a3a; } .ev .x { color: #c4281c; }
        .note { color: #b25000; font-size: 10px; margin-top: 4px; }
        </style></head><body>
        <h1>Reference check</h1>
        <div class="meta">\(escape(source ?? "")) · \(escape(formatter.string(from: date))) · \(references.count) references</div>
        <div class="summary"><span class="ok">\(verified) verified\(resolvedCount > 0 ? " (\(resolvedCount) resolved manually)" : "")</span><span class="warn">\(review) to review</span><span class="bad">\(withIssues) with issues</span><span class="bad">\(notFound) not found</span><span class="na">\(references.count - checked.count) not checked</span></div>
        <div class="legend">
        <span class="ok">&nbsp;Green&nbsp;</span> <b>Confirmed.</b> A field is green only if
        <ol>
        <li>the cited work was identified with certainty (the DOI or AISeL link in the reference leads to the record) or with high confidence (title, every author and the year agree),</li>
        <li>the value comes from a publisher-registered record (DOI metadata at doi.org/Crossref, or the paper’s AIS eLibrary page) or from two independent databases that agree, and no publisher-registered source disagrees,</li>
        <li>the reference gives exactly the same value – only capitalisation, accents, punctuation and line breaks are ignored (the evidence says when); volume, issue and pages must appear in a recognisable place.</li>
        </ol>
        <span class="warn">&nbsp;Amber&nbsp;</span> Matches, but one of these conditions is not met – check manually.
        <span class="bad">&nbsp;Red&nbsp;</span> Different from, or missing compared with, the record.
        <span class="na">&nbsp;Grey&nbsp;</span> No source has the field.
        <b>Resolved</b> references were accepted manually by the user despite the findings. They count as verified, but their table keeps the automatic colours.
        The evidence column lists what every source says (✓ agrees with the reference, ✗ differs, – no value).
        </div>

        """

        for ref in references {
            let result = results[ref.id]
            let verdict = result.map(automatic)
            let resolution = result.flatMap { automatic($0) != .verified ? resolutions[ref.id] : nil }
            let (cls, badge, badgeClass): (String, String, String) = {
                if let verdict, resolution != nil {
                    return ("verified", "Resolved manually (was: \(verdict.title))", "ok")
                }
                switch verdict {
                case .verified?: return ("verified", "Verified", "ok")
                case .needsReview(let n)?: return ("review", n == 1 ? "1 field unconfirmed" : "\(n) fields unconfirmed", "warn")
                case .issues(let n)?: return ("issues", n == 1 ? "1 issue" : "\(n) issues", "bad")
                case .notFound?: return ("notfound", "Not found", "bad")
                case .failed?: return ("failed", "Lookup failed", "bad")
                case nil: return ("", "Not checked", "na")
                }
            }()
            html += "<div class=\"ref \(cls)\"><div class=\"head\"><span class=\"label\">[\(escape(ref.label))]</span>"
            html += "<span class=\"badge \(badgeClass)\">\(badge)</span>"
            if let citations {
                let n = citations.count(for: ref.id)
                html += "<span class=\"badge \(n == 0 ? "bad" : "na")\">\(n == 0 ? "Not cited in text (issue)" : "Cited \(n)× in text")</span>"
            }
            if let m = result?.metadata {
                html += "<span class=\"src\">Record: \(escape(m.provider)) (\(escape(m.authority.label)))"
                if let link = m.doi.map({ "https://doi.org/\($0)" }) ?? m.url {
                    html += " · <a href=\"\(escape(link))\">\(escape(link))</a>"
                }
                html += "</span>"
            }
            html += "</div><div class=\"side\"><div><div class=\"cap\">Original reference</div>"
            html += highlighted(ref.raw, result?.highlights ?? [])
            html += "</div><div><div class=\"cap\">Retrieved metadata</div>"
            html += result?.metadata.map { escape($0.formattedCitation) } ?? "<i>–</i>"
            html += "</div></div>"
            if let resolution {
                let when = DateFormatter.localizedString(from: resolution.date, dateStyle: .medium, timeStyle: .short)
                html += "<div class=\"ident\"><b>Resolved by the user on \(escape(when))</b>"
                if let note = resolution.note { html += " – \(escape(note))" }
                html += ". The table shows the automatic result.</div>"
            }
            if let result, result.metadata != nil {
                html += "<div class=\"ident\">"
                if let id = result.identification {
                    html += "<b>\(escape(id.title)):</b>\(escape(id.reason)) "
                }
                if !result.sources.isEmpty {
                    html += " Sources asked: " + result.sources
                        .map { "\(escape($0.name)) \($0.found ? "✓" : "–")" }.joined(separator: ", ")
                }
                html += "</div>"
            }
            if let fields = result?.fields, !fields.isEmpty {
                html += "<table><tr><th style=\"width:70px\">Field</th><th>Original</th><th>Retrieved</th><th style=\"width:30%\">Evidence</th></tr>"
                for f in fields {
                    let c = cssClass(f.status)
                    html += "<tr><td class=\"f\">\(escape(f.field))</td>"
                    html += "<td class=\"\(c)\">\(escape(f.original ?? "—"))</td>"
                    html += "<td class=\"\(c)\">\(escape(f.retrieved ?? "—"))</td>"
                    html += "<td class=\"n\">\(escape(f.explanation ?? f.note ?? statusText(f.status)))"
                    if let note = f.note, f.explanation != nil, note != f.explanation { html += "<br>\(escape(note))" }
                    for e in f.evidence {
                        let mark = e.agrees == true ? "<span class=\"y\">✓</span>" : (e.agrees == false ? "<span class=\"x\">✗</span>" : "–")
                        html += "<div class=\"ev\">\(mark) \(escape(e.source)): \(escape(e.value ?? "no value"))</div>"
                    }
                    html += "</td></tr>"
                }
                html += "</table>"
            }
            for note in result?.notes ?? [] { html += "<div class=\"note\">\(escape(note))</div>" }
            html += "</div>\n"
        }
        html += "</body></html>"
        return html
    }

    static func cssClass(_ s: MatchStatus) -> String {
        switch s {
        case .match: return "ok"
        case .unconfirmed: return "warn"
        case .mismatch, .missing: return "bad"
        case .unavailable: return "na"
        }
    }

    public static func statusText(_ s: MatchStatus) -> String { s.title }

    static func highlighted(_ raw: String, _ highlights: [Highlight]) -> String {
        let chars = Array(raw)
        var out = ""
        var pos = 0
        for h in highlights where h.start >= pos && h.end <= chars.count && h.start < h.end {
            out += escape(String(chars[pos..<h.start]))
            out += "<mark class=\"\(cssClass(h.status))\">\(escape(String(chars[h.start..<h.end])))</mark>"
            pos = h.end
        }
        out += escape(String(chars[pos...]))
        return out
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
