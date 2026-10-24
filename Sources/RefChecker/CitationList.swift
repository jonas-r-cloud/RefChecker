import SwiftUI
import RefCheckerCore

/// The places in the text where a reference is cited.
struct CitationList: View {
    @Environment(\.reportFontScale) private var scale
    let reference: ParsedReference
    let snippets: [String]
    let style: CitationIndex.Style

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snippets.isEmpty ? "[\(reference.label)] is not cited in the text" : "[\(reference.label)] is cited \(snippets.count)× in the text")
                .font(.rf(.headline, scale))
            Text(style == .numbered ? "Matched: numbered citations such as [3] or [2, 5–7]."
                                    : "Matched: the first author's family name followed by the year, e.g. “Smith et al. (2020)” or “(Smith, 2020)”.")
                .font(.rf(.caption, scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !snippets.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(snippets.enumerated()), id: \.offset) { n, snippet in
                            Text("\(n + 1). \(snippet)")
                                .font(.rf(.caption, scale))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(14)
        .frame(width: 440)
    }
}
