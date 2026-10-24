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
    @AppStorage(SettingsKey.reportFontSize) private var reportFontSize = TextSize.reportDefault
    @State private var confirmReset = false

    var body: some View {
        HSplitView {
            InputPane()
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 600)
            ReportView()
                .environment(\.reportFontScale, CGFloat(reportFontSize / TextSize.reportDefault))
                .frame(minWidth: model.showBrowser ? 520 : 640, maxWidth: .infinity, maxHeight: .infinity)
            if model.showBrowser {
                BrowserPane(browser: model.browser)
                    .frame(minWidth: 380, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
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

                Toggle(isOn: $model.showBrowser) { Label("Browser", systemImage: "sidebar.right") }
                    .help("Show or hide the browser pane (⇧⌘B)")

                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset All", systemImage: "trash")
                }
                .disabled(model.references.isEmpty && model.sectionText.isEmpty && model.sourceName == nil)
                .help("Remove the paper, all references and all results")
            }
        }
        .navigationTitle(model.sourceName ?? "RefChecker")
        .confirmationDialog("Reset all?", isPresented: $confirmReset) {
            Button("Reset All", role: .destructive) { model.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The paper, the reference list and all check results are removed. Settings and the references you marked as resolved are kept.")
        }
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
    @AppStorage(SettingsKey.referenceListFontSize) private var fontSize = TextSize.referenceListDefault

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
            SectionSearchBar(controller: model.textController)
            SectionTextView(text: $model.sectionText, controller: model.textController, fontSize: fontSize)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("Split into References") { model.parseSection() }
                    .disabled(model.sectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                if let problems = extractionProblems {
                    Label("\(model.references.count) references – check the split", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(problems)
                } else {
                    Text("\(model.references.count) references")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }
}

extension InputPane {
    /// Only shown when the split looks incomplete: leftover text, numbering gaps, suspicious entries.
    var extractionProblems: String? {
        guard let x = model.extraction, !x.isComplete || !x.suspicious.isEmpty else { return nil }
        var lines: [String] = []
        if !x.leftovers.isEmpty { lines.append("Text belonging to no reference: " + x.leftovers.map { "“\($0)”" }.joined(separator: "; ")) }
        if let n = x.numbering, !n.missing.isEmpty { lines.append("Missing numbers: " + n.missing.map { "[\($0)]" }.joined(separator: ", ")) }
        if let n = x.numbering, !n.duplicates.isEmpty { lines.append("Numbers used twice: " + n.duplicates.map { "[\($0)]" }.joined(separator: ", ")) }
        lines += x.suspicious.map { "[\($0.label)] \($0.reason)" }
        return lines.joined(separator: "\n")
    }
}

struct ReportView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", problems = "To check", verified = "Verified"
        // Selected via the summary pills.
        case review = "To review", issues = "With issues", notFound = "Not found"
        var id: String { rawValue }
        static let segments: [Filter] = [.all, .problems, .verified]
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.reportFontScale) private var scale
    @State private var filter: Filter = .all

    var body: some View {
        if model.references.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Open a paper to check its references")
                    .font(.rf(.title3, scale))
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
        case .verified: return model.references.filter { model.effectiveVerdict($0) == .verified }
        case .problems: return model.references.filter {
            guard let v = model.effectiveVerdict($0) else { return false }
            return v != .verified
        }
        case .review, .issues, .notFound: return model.references.filter {
            switch model.effectiveVerdict($0) {
            case .needsReview?: return filter == .review
            case .issues?: return filter == .issues
            case .notFound?, .failed?: return filter == .notFound
            default: return false
            }
        }
        }
    }
}

struct SummaryBar: View {
    @Environment(\.reportFontScale) private var scale
    @EnvironmentObject private var model: AppModel
    @Binding var filter: ReportView.Filter

    var body: some View {
        HStack(spacing: 10) {
            pill(.verified, "\(model.verifiedCount) verified" + (model.resolvedCount > 0 ? " (\(model.resolvedCount) resolved by you)" : ""),
                 MatchStatus.match.color)
            pill(.review, "\(model.needsReviewCount) to review", MatchStatus.unconfirmed.color)
            pill(.issues, "\(model.issueCount) with issues", MatchStatus.mismatch.color)
            pill(.notFound, "\(model.notFoundCount) not found", MatchStatus.mismatch.color)
            if model.isChecking {
                ProgressView(value: Double(model.results.count), total: Double(max(model.references.count, 1)))
                    .frame(width: 120)
                Text("\(model.results.count)/\(model.references.count)")
                    .font(.rf(.caption, scale, monospacedDigits: true))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Show", selection: $filter) {
                ForEach(ReportView.Filter.segments) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Clicking a pill shows only those references; clicking it again shows all.
    private func pill(_ target: ReportView.Filter, _ text: String, _ color: Color) -> some View {
        Button {
            filter = filter == target ? .all : target
        } label: {
            Pill(text: text, color: color, isSelected: filter == target)
        }
        .buttonStyle(.plain)
        .help(filter == target ? "Show all references" : "Show only these references")
    }
}

/// Explains the colours, so users know exactly what "green" promises.
struct Legend: View {
    @Environment(\.reportFontScale) private var scale
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
                .font(.rf(.caption, scale))
                .popover(isPresented: $showRules, arrowEdge: .bottom) { RulesView().frame(width: 460) }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func item(_ status: MatchStatus, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(status.color).frame(width: 12, height: 12)
            Text(title).font(.rf(.caption, scale, .semibold))
            if !detail.isEmpty { Text(detail).font(.rf(.caption, scale)).foregroundStyle(.secondary) }
        }
    }
}

struct RulesView: View {
    @Environment(\.reportFontScale) private var scale
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("A field is green only if all three hold:").font(.rf(.headline, scale))
                rule("1", "The right work was found",
                     "Certain: the DOI or AISeL link printed in the reference leads to the record. High confidence: title, every author and the year agree. Otherwise every field stays amber at best, because the record may be a different work (e.g. the journal version of a conference paper).")
                rule("2", "The value is backed by a trustworthy source",
                     "Either a publisher-registered record (DOI metadata at doi.org/Crossref, or the paper's AIS eLibrary page), or two independent databases (e.g. DBLP and OpenAlex) that agree. If a publisher-registered source disagrees, the field is amber.")
                rule("3", "The reference says exactly the same",
                     "Compared character by character, ignoring only capitalisation, accents, punctuation and line breaks (the evidence column says when that was needed). Volume, issue and pages must appear in a recognisable place such as “vol. 12”, “12(3)” or “45–67”.")
                Divider()
                Text("Every field lists its evidence: which sources were asked and what each one says. Use “Open record” on a card to look at the source yourself.")
                    .font(.rf(.callout, scale))
                Text("Green cannot catch errors that the publisher's own metadata contains, nor tell you whether citing the work is appropriate.")
                    .font(.rf(.callout, scale))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxHeight: 460)
    }

    private func rule(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.rf(.headline, scale)).frame(width: 18, height: 18).background(Circle().fill(MatchStatus.match.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rf(.subheadline, scale, .semibold))
                Text(text).font(.rf(.callout, scale)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Pill: View {
    @Environment(\.reportFontScale) private var scale
    let text: String
    let color: Color
    var isSelected = false

    var body: some View {
        Text(text)
            .font(.rf(.caption, scale, isSelected ? .bold : .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
            .overlay(Capsule().stroke(Color.primary.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5))
            .contentShape(Capsule())
    }
}
