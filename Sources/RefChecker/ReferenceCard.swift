import SwiftUI
import RefCheckerCore

/// One reference: original text and retrieved metadata side by side, how the record
/// was identified, and the field-by-field comparison with its evidence.
struct ReferenceCard: View {
    @EnvironmentObject private var model: AppModel
    let reference: ParsedReference
    let result: ReferenceResult?
    let isChecking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 12) {
                Panel("Original reference") {
                    Text(highlightedReference)
                        .textSelection(.enabled)
                }
                Panel("Retrieved metadata" + (result?.metadata.map { " · \($0.provider) (\($0.authority.label))" } ?? "")) {
                    if let meta = result?.metadata {
                        Text(meta.formattedCitation)
                            .textSelection(.enabled)
                    } else {
                        Text(placeholder)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let result, result.metadata != nil {
                IdentificationRow(result: result)
            }

            if let fields = result?.fields, !fields.isEmpty {
                FieldTable(fields: fields)
            }

            ForEach(result?.notes ?? [], id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("[\(reference.label)]")
                .font(.headline.monospacedDigit())
            VerdictBadge(verdict: result?.verdict, isChecking: isChecking)
            Spacer()
            if let url = recordURL {
                Link(destination: url) { Label("Open record", systemImage: "arrow.up.right.square") }
                    .font(.caption)
                    .help(url.absoluteString)
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

    private var recordURL: URL? {
        guard let meta = result?.metadata else { return nil }
        if let doi = meta.doi { return URL(string: "https://doi.org/\(doi)") }
        return (meta.url ?? meta.links.first).flatMap(URL.init(string:))
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
        switch result?.verdict {
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
    let result: ReferenceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let id = result.identification {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: icon(id.level))
                        .foregroundStyle(id.level == .probable ? Color.orange : Color.green)
                    Text(id.title).font(.caption.weight(.semibold))
                    Text(id.reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !result.sources.isEmpty {
                HStack(spacing: 10) {
                    Text("Sources asked:").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                        Label(source.name, systemImage: source.found ? "checkmark.circle" : "minus.circle")
                            .font(.caption)
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
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }
}

struct VerdictBadge: View {
    let verdict: Verdict?
    let isChecking: Bool

    var body: some View {
        if isChecking {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption)
            }
        } else if let verdict {
            Label(verdict.title, systemImage: style(verdict).icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(style(verdict).status.color))
        } else {
            Text("Not checked")
                .font(.caption)
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
                        .font(.caption.weight(.semibold))
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
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueCell(_ value: String?, _ status: MatchStatus) -> some View {
        Text(value ?? "—")
            .font(.caption)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(status.color)
    }
}

/// Why a field has its colour, and what each source says.
struct EvidenceCell: View {
    let field: FieldComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.explanation ?? field.note ?? field.status.title)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
            if field.note != nil, field.explanation != nil, field.note != field.explanation {
                Text(field.note!)
                    .font(.caption2)
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
                .font(.caption2)
                .help("\(e.source) (\(e.authority.label)): \(e.value ?? "no value")")
            }
        }
        .padding(4)
    }
}
