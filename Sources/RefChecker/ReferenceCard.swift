import SwiftUI
import RefCheckerCore

/// One reference: original text and retrieved metadata side by side, how the record
/// was identified, and the field-by-field comparison with its evidence.
struct ReferenceCard: View {
    @Environment(\.reportFontScale) private var scale
    @EnvironmentObject private var model: AppModel
    let reference: ParsedReference
    let result: ReferenceResult?
    let isChecking: Bool
    @State private var showResolveForm = false
    @State private var showCitations = false
    @State private var noteDraft = ""

    private var resolution: Resolution? { model.resolution(for: reference) }
    /// Resolving makes sense only for checked references that are not verified anyway.
    private var canResolve: Bool { verdict.map { $0 != .verified } ?? false }
    /// The checker's verdict, counting "not cited in the text" as an issue.
    private var verdict: Verdict? { model.automaticVerdict(reference) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 12) {
                Panel("Original reference") {
                    Text(highlightedReference)
                        .font(.rf(.body, scale))
                        .textSelection(.enabled)
                }
                Panel("Retrieved metadata" + (result?.metadata.map { " · \($0.provider) (\($0.authority.label))" } ?? "")) {
                    if let meta = result?.metadata {
                        Text(meta.formattedCitation)
                            .font(.rf(.body, scale))
                            .textSelection(.enabled)
                    } else {
                        Text(placeholder)
                            .font(.rf(.body, scale))
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let result, result.metadata != nil {
                IdentificationRow(result: result)
            }

            if let resolution, canResolve {
                ResolutionRow(resolution: resolution) { model.unresolve(reference) }
            }

            if let fields = result?.fields, !fields.isEmpty {
                FieldTable(fields: fields)
            }

            if model.isUncited(reference) {
                Label("Not cited in the text – counted as an issue. Remove the reference, add a citation, or resolve it if the citation is written in a form the app does not recognise.",
                      systemImage: "quote.bubble")
                    .font(.rf(.caption, scale))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(result?.notes ?? [], id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.rf(.caption, scale))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isInBrowser ? Color.accentColor : borderColor,
                                                          lineWidth: isInBrowser ? 2 : 1))
    }

    private var isInBrowser: Bool { model.showBrowser && model.browserReferenceID == reference.id }

    private var header: some View {
        HStack(spacing: 8) {
            Text("[\(reference.label)]")
                .font(.rf(.headline, scale, monospacedDigits: true))
            VerdictBadge(verdict: verdict, isChecking: isChecking, resolved: resolution != nil)
            if let citations = model.citations {
                let snippets = citations.occurrences[reference.id] ?? []
                Button { showCitations = true } label: {
                    Label(snippets.isEmpty ? "Not cited in text" : "Cited \(snippets.count)×", systemImage: "quote.bubble")
                }
                .font(.rf(.caption, scale))
                .foregroundStyle(snippets.isEmpty ? Color.red : Color.secondary)
                .buttonStyle(.borderless)
                .help(snippets.isEmpty ? "No citation of this reference was found in the paper's text"
                                       : "Show where the paper cites this reference")
                .popover(isPresented: $showCitations, arrowEdge: .bottom) {
                    CitationList(reference: reference, snippets: snippets, style: citations.style)
                        .environment(\.reportFontScale, scale)
                }
            }
            Spacer()
            if canResolve {
                if resolution != nil {
                    Button { model.unresolve(reference) } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                    }
                    .font(.rf(.caption, scale))
                    .buttonStyle(.borderless)
                    .help("Undo “resolved” – the reference shows its automatic verdict again")
                } else {
                    Button {
                        noteDraft = ""
                        showResolveForm = true
                    } label: {
                        Label("Resolve", systemImage: "checkmark.circle")
                    }
                    .font(.rf(.caption, scale))
                    .buttonStyle(.borderless)
                    .help("Mark as resolved: counts as verified, the field colours stay as they are")
                    .popover(isPresented: $showResolveForm, arrowEdge: .bottom) { resolveForm }
                }
            }
            Button {
                model.revealInList(reference)
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show this reference in the reference list")
            Button {
                model.showInBrowser(reference)
            } label: {
                Label(result?.metadata != nil ? "Website" : "Search Scholar", systemImage: "globe")
            }
            .font(.rf(.caption, scale))
            .buttonStyle(.borderless)
            .help(result?.metadata != nil
                  ? "Open the record's website in the browser pane: \(model.webURL(for: reference).absoluteString)"
                  : "Search Google Scholar for this reference in the browser pane")
            if let url = recordURL {
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                    .font(.rf(.caption, scale))
                    .help("Open in your default browser: \(url.absoluteString)")
            }
            Button {
                model.check([reference])
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check this reference again")
            .disabled(isChecking)
        }
    }

    private var resolveForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mark [\(reference.label)] as resolved").font(.rf(.headline, scale))
            Text("The reference will count as verified. The field colours and the evidence stay as the check found them, and the badge shows that you resolved it.")
                .font(.rf(.caption, scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Reason (optional), e.g. “venue abbreviation is fine”", text: $noteDraft, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showResolveForm = false }
                    .keyboardShortcut(.cancelAction)
                Button("Mark as Resolved") {
                    model.resolve(reference, note: noteDraft)
                    showResolveForm = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var recordURL: URL? {
        guard let meta = result?.metadata else { return nil }
        if let doi = meta.doi { return URL(string: "https://doi.org/\(doi)") }
        return (meta.url ?? meta.links.first).flatMap { URL(string: $0) }
    }

    private var placeholder: String {
        if isChecking { return "Searching…" }
        switch result?.verdict {
        case .notFound?: return "No matching record found at the enabled providers."
        case .failed(let message)?: return message
        default: return "Not checked yet."
        }
    }

    private var borderColor: Color {
        if resolution != nil && canResolve { return .green.opacity(0.6) }
        switch verdict {
        case .verified?: return .green.opacity(0.6)
        case .needsReview?: return .orange.opacity(0.7)
        case .issues?, .notFound?, .failed?: return .red.opacity(0.6)
        case nil: return Color.secondary.opacity(0.25)
        }
    }

    private var highlightedReference: AttributedString {
        var text = AttributedString(reference.raw)
        let count = text.characters.count
        for h in result?.highlights ?? [] where h.start >= 0 && h.end <= count && h.start < h.end {
            let lower = text.characters.index(text.startIndex, offsetBy: h.start)
            let upper = text.characters.index(lower, offsetBy: h.end - h.start)
            text[lower..<upper].backgroundColor = h.status.color
        }
        return text
    }
}

/// "Identified with certainty: the DOI printed in the reference resolves to this record."
/// plus which sources were asked and which found the work.
struct IdentificationRow: View {
    @Environment(\.reportFontScale) private var scale
    let result: ReferenceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let id = result.identification {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: icon(id.level))
                        .foregroundStyle(id.level == .probable ? Color.orange : Color.green)
                    Text(id.title).font(.rf(.caption, scale, .semibold))
                    Text(id.reason).font(.rf(.caption, scale)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !result.sources.isEmpty {
                HStack(spacing: 10) {
                    Text("Sources asked:").font(.rf(.caption, scale)).foregroundStyle(.secondary)
                    ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                        Label(source.name, systemImage: source.found ? "checkmark.circle" : "minus.circle")
                            .font(.rf(.caption, scale))
                            .foregroundStyle(source.found ? Color.primary : Color.secondary)
                            .help(source.found ? "\(source.name) has this work" : "\(source.name) did not return this work")
                    }
                }
            }
        }
    }

    private func icon(_ level: Identification.Level) -> String {
        switch level {
        case .certain: return "checkmark.seal.fill"
        case .high: return "checkmark.seal"
        case .probable: return "questionmark.diamond"
        }
    }
}

struct Panel<Content: View>: View {
    @Environment(\.reportFontScale) private var scale
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.rf(.caption2, scale, .semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }
}

/// "Resolved by you on 22 Oct 2026 – venue abbreviation is fine"
struct ResolutionRow: View {
    @Environment(\.reportFontScale) private var scale
    let resolution: Resolution
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Color.green)
            Text("Resolved by you on \(resolution.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.rf(.caption, scale, .semibold))
            if let note = resolution.note {
                Text("– \(note)").font(.rf(.caption, scale)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The table below still shows the automatic result.").font(.rf(.caption, scale)).foregroundStyle(.secondary)
            Spacer()
            Button("Undo", action: undo).font(.rf(.caption, scale)).buttonStyle(.link)
        }
    }
}

struct VerdictBadge: View {
    @Environment(\.reportFontScale) private var scale
    let verdict: Verdict?
    let isChecking: Bool
    var resolved = false

    var body: some View {
        if isChecking {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.rf(.caption, scale))
            }
        } else if let verdict, resolved, verdict != .verified {
            HStack(spacing: 4) {
                Label("Resolved", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.rf(.caption, scale, .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(MatchStatus.match.color))
                Text("was: \(verdict.title)")
                    .font(.rf(.caption, scale))
                    .foregroundStyle(.secondary)
            }
            .help("Marked as resolved by you; counts as verified. The automatic verdict was “\(verdict.title)”.")
        } else if let verdict {
            Label(verdict.title, systemImage: style(verdict).icon)
                .font(.rf(.caption, scale, .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(style(verdict).status.color))
        } else {
            Text("Not checked")
                .font(.rf(.caption, scale))
                .foregroundStyle(.secondary)
        }
    }

    private func style(_ verdict: Verdict) -> (icon: String, status: MatchStatus) {
        switch verdict {
        case .verified: return ("checkmark.seal.fill", .match)
        case .needsReview: return ("exclamationmark.triangle.fill", .unconfirmed)
        case .issues, .notFound, .failed: return ("xmark.octagon.fill", .mismatch)
        }
    }
}

struct FieldTable: View {
    @Environment(\.reportFontScale) private var scale
    let fields: [FieldComparison]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                headerCell("Field").frame(width: 80, alignment: .leading)
                headerCell("Original")
                headerCell("Retrieved")
                headerCell("Evidence").frame(width: 230, alignment: .leading)
            }
            ForEach(fields) { field in
                GridRow {
                    Label(field.field, systemImage: icon(field.status))
                        .font(.rf(.caption, scale, .semibold))
                        .padding(4)
                        .frame(width: 80, alignment: .leading)
                        .help(field.status.title)
                    valueCell(field.original, field.status)
                    valueCell(field.retrieved, field.status)
                    EvidenceCell(field: field)
                        .frame(width: 230, alignment: .leading)
                }
            }
        }
    }

    private func icon(_ status: MatchStatus) -> String {
        switch status {
        case .match: return "checkmark.seal.fill"
        case .unconfirmed: return "exclamationmark.triangle"
        case .mismatch, .missing: return "xmark.circle"
        case .unavailable: return "circle.dashed"
        }
    }

    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(.rf(.caption2, scale, .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueCell(_ value: String?, _ status: MatchStatus) -> some View {
        Text(value ?? "—")
            .font(.rf(.caption, scale))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(status.color)
    }
}

/// Why a field has its colour, and what each source says.
struct EvidenceCell: View {
    @Environment(\.reportFontScale) private var scale
    let field: FieldComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.explanation ?? field.note ?? field.status.title)
                .font(.rf(.caption2, scale))
                .fixedSize(horizontal: false, vertical: true)
            if field.note != nil, field.explanation != nil, field.note != field.explanation {
                Text(field.note!)
                    .font(.rf(.caption2, scale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(field.evidence.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: e.agrees == true ? "checkmark" : (e.agrees == false ? "xmark" : "minus"))
                        .foregroundStyle(e.agrees == true ? Color.green : (e.agrees == false ? Color.red : Color.secondary))
                    Text(e.source).fontWeight(.medium)
                    Text(e.value ?? "no value")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.rf(.caption2, scale))
                .help("\(e.source) (\(e.authority.label)): \(e.value ?? "no value")")
            }
        }
        .padding(4)
    }
}
