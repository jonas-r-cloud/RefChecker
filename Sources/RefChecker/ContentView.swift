import SwiftUI
import RefCheckerCore

extension MatchStatus {
    var color: Color {
        switch self {
        case .match: return Color.green.opacity(0.28)
        case .unconfirmed: return Color.orange.opacity(0.28)
        case .mismatch, .missing: return Color.red.opacity(0.28)
        case .unavailable: return Color.gray.opacity(0.15)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            InputPane()
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 600)
            ReportView()
                .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showOpenPanel() } label: {
                    Label("Open Paper", systemImage: "doc.badge.plus")
                }
                .help("Open a PDF or text file")

                if model.isChecking {
                    Button { model.cancel() } label: { Label("Stop", systemImage: "stop.circle") }
                        .help("Stop checking")
                } else {
                    Button { model.checkAll() } label: { Label("Check References", systemImage: "checkmark.seal") }
                        .disabled(model.references.isEmpty)
                        .help("Retrieve metadata for all references and compare")
                }

                Button { model.exportHTML() } label: { Label("Export HTML", systemImage: "square.and.arrow.up") }
                    .disabled(model.results.isEmpty)
                    .help("Save the side-by-side report as HTML")

                Button { model.printReport() } label: { Label("Print", systemImage: "printer") }
                    .disabled(model.results.isEmpty)
                    .help("Print the side-by-side report (or save it as PDF)")
            }
        }
        .navigationTitle(model.sourceName ?? "RefChecker")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil },
                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct InputPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reference list")
                .font(.headline)
            Text("Extracted from the paper. You can edit it or paste a reference list here, then split it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.removedLines.isEmpty {
                DisclosureGroup("Removed \(model.removedLines.count) header/footer lines") {
                    ScrollView {
                        Text(model.removedLines.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                .font(.caption)
            }
            TextEditor(text: $model.sectionText)
                .font(.system(size: 11, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("Split into References") { model.parseSection() }
                    .disabled(model.sectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text("\(model.references.count) references")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

struct ReportView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", problems = "To check", verified = "Verified"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var filter: Filter = .all

    var body: some View {
        if model.references.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Open a paper to check its references")
                    .font(.title3)
                Text("Drop a PDF here, use File › Open Paper… (⌘O), or paste a reference list on the left.")
                    .foregroundStyle(.secondary)
                Button("Open Paper…") { model.showOpenPanel() }
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                SummaryBar(filter: $filter)
                Legend()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleReferences) { ref in
                            ReferenceCard(reference: ref, result: model.results[ref.id],
                                          isChecking: model.inProgress.contains(ref.id))
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var visibleReferences: [ParsedReference] {
        switch filter {
        case .all: return model.references
        case .verified: return model.references.filter { model.results[$0.id]?.verdict == .verified }
        case .problems: return model.references.filter {
            guard let v = model.results[$0.id]?.verdict else { return false }
            return v != .verified
        }
        }
    }
}

struct SummaryBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var filter: ReportView.Filter

    var body: some View {
        HStack(spacing: 10) {
            Pill(text: "\(model.verifiedCount) verified", color: MatchStatus.match.color)
            Pill(text: "\(model.needsReviewCount) to review", color: MatchStatus.unconfirmed.color)
            Pill(text: "\(model.issueCount) with issues", color: MatchStatus.mismatch.color)
            Pill(text: "\(model.notFoundCount) not found", color: MatchStatus.mismatch.color)
            if model.isChecking {
                ProgressView(value: Double(model.results.count), total: Double(max(model.references.count, 1)))
                    .frame(width: 120)
                Text("\(model.results.count)/\(model.references.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Show", selection: $filter) {
                ForEach(ReportView.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Explains the colours, so users know exactly what "green" promises.
struct Legend: View {
    @State private var showRules = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            item(.match, "Confirmed", "identical to a trusted record of this exact work")
            item(.unconfirmed, "Unconfirmed", "matches, but the evidence is weaker – check")
            item(.mismatch, "Wrong / missing", "")
            item(.unavailable, "No data", "")
            Spacer()
            Button("What does green guarantee?") { showRules.toggle() }
                .buttonStyle(.link)
                .font(.caption)
                .popover(isPresented: $showRules, arrowEdge: .bottom) { RulesView().frame(width: 460) }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func item(_ status: MatchStatus, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(status.color).frame(width: 12, height: 12)
            Text(title).font(.caption.weight(.semibold))
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct RulesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("A field is green only if all three hold:").font(.headline)
                rule("1", "The right work was found",
                     "Certain: the DOI or AISeL link printed in the reference leads to the record. High confidence: title, every author and the year agree. Otherwise every field stays amber at best, because the record may be a different work (e.g. the journal version of a conference paper).")
                rule("2", "The value is backed by a trustworthy source",
                     "Either a publisher-registered record (DOI metadata at doi.org/Crossref, or the paper's AIS eLibrary page), or two independent databases (e.g. DBLP and OpenAlex) that agree. If a publisher-registered source disagrees, the field is amber.")
                rule("3", "The reference says exactly the same",
                     "Compared character by character, ignoring only capitalisation, accents, punctuation and line breaks (the evidence column says when that was needed). Volume, issue and pages must appear in a recognisable place such as “vol. 12”, “12(3)” or “45–67”.")
                Divider()
                Text("Every field lists its evidence: which sources were asked and what each one says. Use “Open record” on a card to look at the source yourself.")
                    .font(.callout)
                Text("Green cannot catch errors that the publisher's own metadata contains, nor tell you whether citing the work is appropriate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxHeight: 460)
    }

    private func rule(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.headline).frame(width: 18, height: 18).background(Circle().fill(MatchStatus.match.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}
