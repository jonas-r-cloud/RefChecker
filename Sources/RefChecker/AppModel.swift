import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import RefCheckerCore

enum SettingsKey {
    static let contactEmail = "contactEmail"
    static let useCrossref = "useCrossref"
    static let useDBLP = "useDBLP"
    static let useOpenAlex = "useOpenAlex"
    static let useAISeL = "useAISeL"
    static let useNLM = "useNLM"
    static let requireDOI = "requireDOI"
    static let checkVolumeIssuePages = "checkVolumeIssuePages"
    static let requireArticleNumber = "requireArticleNumber"
    static let referenceListFontSize = "referenceListFontSize"
    static let reportFontSize = "reportFontSize"
    static let parallelRequests = "parallelRequests"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceName: String?
    @Published var sectionText = ""
    @Published var references: [ParsedReference] = []
    @Published var results: [Int: ReferenceResult] = [:]
    @Published var inProgress: Set<Int> = []
    @Published var isChecking = false
    @Published var notice: String?
    @Published var removedLines: [String] = []
    /// The paper's text before the reference list (only when a whole paper was opened).
    @Published var bodyText: String?
    /// Evidence that the reference list was split completely.
    @Published var extraction: ExtractionReport?
    /// How often each reference is cited in `bodyText`.
    @Published var citations: CitationIndex?
    @Published var errorMessage: String?
    @Published var showBrowser = false
    /// The reference whose website is shown in the browser pane.
    @Published var browserReferenceID: Int?

    /// Manually resolved references, by `Resolution.key(for:)`; persisted in the user defaults.
    @Published private(set) var resolutions: [String: Resolution] = AppModel.loadResolutions()

    let browser = BrowserModel()
    let textController = SectionTextController()

    private var checkTask: Task<Void, Never>?
    private var currentRun: UUID?

    // MARK: Loading

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText, .text, UTType(filenameExtension: "md") ?? .text]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a paper (PDF) or a text file containing its reference list"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let extracted = try PaperText.extract(from: url)
            let text = extracted.text
            removedLines = extracted.removed
            sourceName = url.lastPathComponent
            if let parts = ReferenceSectionExtractor.split(text) {
                sectionText = parts.section
                bodyText = parts.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parts.body
                notice = nil
            } else {
                sectionText = text
                bodyText = nil
                notice = "No “References” heading was found, so the whole text is shown. Delete everything except the reference list and choose “Split into References”."
            }
            // Without a "References" heading the whole paper is shown; leave it as is for trimming.
            parseSection(reformat: notice == nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Splits the reference list. With `reformat`, the list is rewritten as one reference per
    /// paragraph (shown with hanging indent), separated by empty lines; an empty line always splits.
    func parseSection(reformat: Bool = true) {
        cancel()
        let entries = ReferenceSplitter.split(sectionText)
        references = ReferenceParser.parse(entries: entries)
        results = [:]
        extraction = entries.isEmpty ? nil : ExtractionReport.analyze(section: sectionText, entries: entries)
        citations = bodyText.map { CitationIndex.build(body: $0, references: references) }
        if reformat, !entries.isEmpty {
            sectionText = ReferenceSplitter.format(entries)
        }
    }

    // MARK: Checking

    func checkAll() { check(references) }

    func check(_ refs: [ParsedReference]) {
        guard !refs.isEmpty else { return }
        cancel()
        for r in refs { results[r.id] = nil }
        let checker = ReferenceChecker(configuration: Self.configuration())
        let parallel = max(1, min(8, UserDefaults.standard.object(forKey: SettingsKey.parallelRequests) as? Int ?? 3))
        isChecking = true
        let run = UUID()
        currentRun = run
        checkTask = Task { [weak self] in
            await withTaskGroup(of: ReferenceResult.self) { group in
                var pending = refs[...]
                for _ in 0..<parallel {
                    guard let ref = pending.popFirst() else { break }
                    self?.inProgress.insert(ref.id)
                    group.addTask { await checker.check(ref) }
                }
                while let result = await group.next() {
                    guard let self, self.currentRun == run, !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    self.inProgress.remove(result.id)
                    self.results[result.id] = result
                    if let ref = pending.popFirst() {
                        self.inProgress.insert(ref.id)
                        group.addTask { await checker.check(ref) }
                    }
                }
            }
            guard let self, self.currentRun == run else { return }
            self.isChecking = false
            self.inProgress = []
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
        currentRun = nil
        isChecking = false
        inProgress = []
    }

    static func configuration() -> CheckerConfiguration {
        let d = UserDefaults.standard
        func flag(_ key: String) -> Bool { d.object(forKey: key) as? Bool ?? true }
        return CheckerConfiguration(
            contactEmail: d.string(forKey: SettingsKey.contactEmail),
            useCrossref: flag(SettingsKey.useCrossref),
            useDBLP: flag(SettingsKey.useDBLP),
            useOpenAlex: flag(SettingsKey.useOpenAlex),
            useAISeL: flag(SettingsKey.useAISeL),
            useNLM: flag(SettingsKey.useNLM),
            options: ComparisonOptions(requireDOI: flag(SettingsKey.requireDOI),
                                       checkVolumeIssuePages: flag(SettingsKey.checkVolumeIssuePages),
                                       requireArticleNumber: flag(SettingsKey.requireArticleNumber)))
    }

    // MARK: Browser & navigation

    /// The website of a reference's record: DOI landing page, else the provider's landing page.
    /// Unresolved references get a Google Scholar search instead.
    func webURL(for reference: ParsedReference) -> URL {
        if let meta = results[reference.id]?.metadata {
            let candidates: [String?] = [meta.doi.map { "https://doi.org/\($0)" }] + meta.links.map { Optional($0) } + [meta.url]
            if let url = candidates.compactMap({ $0 }).compactMap({ URL(string: $0) })
                .first(where: { $0.scheme == "https" || $0.scheme == "http" }) {
                return url
            }
        }
        if let doi = reference.doi, let url = URL(string: "https://doi.org/\(doi)") { return url }
        return BrowserModel.scholarSearch(reference.title ?? reference.raw)
    }

    func showInBrowser(_ reference: ParsedReference) {
        showBrowser = true
        browserReferenceID = reference.id
        browser.load(webURL(for: reference))
    }

    func revealInList(_ reference: ParsedReference) {
        textController.reveal(reference)
    }

    // MARK: Summary

    private var effectiveVerdicts: [Verdict] { references.compactMap(effectiveVerdict) }

    var verifiedCount: Int { effectiveVerdicts.filter { $0 == .verified }.count }
    var resolvedCount: Int {
        references.filter { resolution(for: $0) != nil && automaticVerdict($0).map { $0 != .verified } == true }.count
    }
    var needsReviewCount: Int {
        effectiveVerdicts.filter { if case .needsReview = $0 { return true }; return false }.count
    }
    var issueCount: Int { effectiveVerdicts.filter { if case .issues = $0 { return true }; return false }.count }
    var notFoundCount: Int {
        effectiveVerdicts.filter {
            switch $0 {
            case .notFound, .failed: return true
            default: return false
            }
        }.count
    }

    // MARK: Manual resolution

    func resolution(for reference: ParsedReference) -> Resolution? {
        resolutions[Resolution.key(for: reference)]
    }

    /// The verdict as shown: a resolved reference counts as verified.
    func effectiveVerdict(_ reference: ParsedReference) -> Verdict? {
        guard let verdict = automaticVerdict(reference) else { return nil }
        return resolution(for: reference) != nil ? .verified : verdict
    }

    /// The checker's verdict, with a reference that is never cited in the text counted as an issue.
    func automaticVerdict(_ reference: ParsedReference) -> Verdict? {
        guard let verdict = results[reference.id]?.verdict else { return nil }
        return citations?.adjusted(verdict, for: reference.id) ?? verdict
    }

    func isUncited(_ reference: ParsedReference) -> Bool {
        citations.map { $0.count(for: reference.id) == 0 } ?? false
    }

    /// Empties everything loaded: paper, reference list, results and the browser pane.
    /// Settings and the references you resolved stay.
    func resetAll() {
        cancel()
        sourceName = nil
        sectionText = ""
        references = []
        results = [:]
        removedLines = []
        bodyText = nil
        extraction = nil
        citations = nil
        notice = nil
        errorMessage = nil
        browserReferenceID = nil
        textController.query = ""
        browser.clear()
    }

    func resolve(_ reference: ParsedReference, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        resolutions[Resolution.key(for: reference)] = Resolution(note: trimmed.isEmpty ? nil : trimmed)
        saveResolutions()
    }

    func unresolve(_ reference: ParsedReference) {
        resolutions[Resolution.key(for: reference)] = nil
        saveResolutions()
    }

    private static let resolutionsKey = "resolutions"

    private static func loadResolutions() -> [String: Resolution] {
        guard let data = UserDefaults.standard.data(forKey: resolutionsKey),
              let stored = try? JSONDecoder().decode([String: Resolution].self, from: data) else { return [:] }
        return stored
    }

    private func saveResolutions() {
        if let data = try? JSONEncoder().encode(resolutions) {
            UserDefaults.standard.set(data, forKey: Self.resolutionsKey)
        }
    }

    // MARK: Output

    func reportHTML() -> String {
        let resolved = Dictionary(uniqueKeysWithValues: references.compactMap { ref in
            resolution(for: ref).map { (ref.id, $0) }
        })
        return HTMLReport.render(references: references, results: results, source: sourceName, resolutions: resolved,
                                 citations: citations)
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        let base = sourceName.map { ($0 as NSString).deletingPathExtension } ?? "references"
        panel.nameFieldStringValue = "\(base) – reference check.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportHTML().write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func printReport() {
        ReportPrinter.shared.print(html: reportHTML())
    }
}

enum PaperText {
    enum Failure: LocalizedError {
        case unreadablePDF, noText

        var errorDescription: String? {
            switch self {
            case .unreadablePDF: return "The PDF could not be opened."
            case .noText: return "The PDF contains no text layer (scanned document?). Run OCR first or paste the references manually."
            }
        }
    }

    struct Extracted {
        var text: String
        /// Running headers, footers and page numbers that were dropped.
        var removed: [String] = []
    }

    static func extract(from url: URL) throws -> Extracted {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { throw Failure.unreadablePDF }
            let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }.map(lines(of:))
            let cleaned = PageCleaner.clean(pages: pages)
            guard !cleaned.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.noText }
            return Extracted(text: cleaned.text, removed: cleaned.removed)
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return Extracted(text: text) }
        return Extracted(text: try String(contentsOf: url, encoding: .isoLatin1))
    }

    /// The visual lines of a page with their vertical position. Falls back to the
    /// plain page text (without positions) if line geometry is unavailable or incomplete.
    static func lines(of page: PDFPage) -> [PageLine] {
        let plain = page.string ?? ""
        let fallback = plain.components(separatedBy: .newlines).map { PageLine(text: $0) }
        let box = page.bounds(for: .cropBox)
        guard page.rotation % 180 == 0, box.height > 0, let selection = page.selection(for: box) else { return fallback }

        let lines = selection.selectionsByLine().compactMap { line -> PageLine? in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let b = line.bounds(for: page)
            var top = (box.maxY - b.maxY) / box.height
            var bottom = (box.maxY - b.minY) / box.height
            if page.rotation == 180 { (top, bottom) = (1 - bottom, 1 - top) }
            return PageLine(text: text, top: Double(top), bottom: Double(bottom))
        }
        // Line selections occasionally miss text that page.string has; then trust page.string.
        let lineChars = lines.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
        let plainChars = plain.filter { !$0.isWhitespace }.count
        return lineChars >= plainChars * 9 / 10 ? lines : fallback
    }
}
