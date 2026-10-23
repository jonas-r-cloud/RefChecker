import SwiftUI
import AppKit
import RefCheckerCore

/// Drives the reference-list text view: search with highlight-all and jumping to a reference.
@MainActor
final class SectionTextController: ObservableObject {
    weak var textView: NSTextView?

    @Published var query = ""
    @Published private(set) var matches: [NSRange] = []
    @Published private(set) var current = -1

    private var highlightColor: NSColor { NSColor.findHighlightColor.withAlphaComponent(0.45) }

    /// Finds all occurrences of `query` (ignoring case and accents) and highlights them.
    func updateSearch(selectFirst: Bool = true) {
        guard let textView, let layout = textView.layoutManager else { return }
        let text = textView.string as NSString
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
        var found: [NSRange] = []
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard r.location != NSNotFound else { break }
                found.append(r)
                let next = r.location + max(r.length, 1)
                searchRange = NSRange(location: next, length: max(0, text.length - next))
            }
        }
        for r in found { layout.addTemporaryAttribute(.backgroundColor, value: highlightColor, forCharacterRange: r) }
        matches = found
        current = -1
        if selectFirst, !found.isEmpty { select(0) }
    }

    func next() {
        guard !matches.isEmpty else { return }
        select((current + 1) % matches.count)
    }

    func previous() {
        guard !matches.isEmpty else { return }
        select((current - 1 + matches.count) % matches.count)
    }

    private func select(_ index: Int) {
        current = index
        show(matches[index])
    }

    private func show(_ range: NSRange) {
        guard let textView else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    /// Scrolls the reference list to `reference` and selects its beginning.
    func reveal(_ reference: ParsedReference) {
        guard let textView else { return }
        let text = textView.string
        let ns = text as NSString
        var patterns: [String] = []
        if Int(reference.label) != nil {
            patterns.append("\\[\(reference.label)\\]")
            patterns.append("(?m)^\\s*\(reference.label)[.)]\\s")
        } else {
            patterns.append("\\[\(NSRegularExpression.escapedPattern(for: reference.label))\\]")
        }
        // The first words of the reference, allowing line breaks and hyphenation in between.
        let words = reference.raw.split(whereSeparator: \.isWhitespace).prefix(8)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        if !words.isEmpty { patterns.append(words.joined(separator: "[\\s\\-]+")) }

        for pattern in patterns {
            guard let rx = try? NSRegularExpression(pattern: pattern),
                  let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let end = min(ns.length, m.range.location + max(m.range.length, 60))
            show(NSRange(location: m.range.location, length: end - m.range.location))
            textView.window?.makeFirstResponder(textView)
            return
        }
        NSSound.beep()
    }

    /// Opens the standard find bar (also bound to ⌘F while the text has focus).
    func showFindBar() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }
}

/// Plain-text editor for the reference list with find bar and search highlighting.
struct SectionTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: SectionTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, so search matches can be highlighted with temporary attributes.
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        Self.applyStyle(textView)
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.findBarPosition = .aboveContent
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.textView = textView
        if textView.string != text {
            textView.string = text
            Self.applyStyle(textView)
            // Defer: publishing from inside a view update is not allowed.
            Task { @MainActor in controller.updateSearch(selectFirst: false) }
        }
    }

    @MainActor
    /// Like a paper's reference list: every paragraph is one reference, its wrapped lines indented.
    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = 20
        style.lineSpacing = 1
        return style
    }()

    @MainActor
    static func applyStyle(_ textView: NSTextView) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.textColor
        ]
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = attributes
        if let storage = textView.textStorage {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SectionTextView

        init(_ parent: SectionTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            let controller = parent.controller
            Task { @MainActor in controller.updateSearch(selectFirst: false) }
        }
    }
}

/// Search field with match counter and previous/next buttons.
struct SectionSearchBar: View {
    @ObservedObject var controller: SectionTextController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search reference list", text: $controller.query)
                .textFieldStyle(.plain)
                .onSubmit { controller.next() }
                .onChange(of: controller.query) { _ in controller.updateSearch() }
            if !controller.query.isEmpty {
                Text(controller.matches.isEmpty ? "No matches" : "\(controller.current + 1) of \(controller.matches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(controller.matches.isEmpty ? Color.red : Color.secondary)
                Button { controller.previous() } label: { Image(systemName: "chevron.up") }
                    .disabled(controller.matches.isEmpty)
                    .help("Previous match")
                Button { controller.next() } label: { Image(systemName: "chevron.down") }
                    .disabled(controller.matches.isEmpty)
                    .help("Next match (↩)")
                Button { controller.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary)
                    .help("Clear search")
            }
            Button { controller.showFindBar() } label: { Image(systemName: "text.magnifyingglass") }
                .help("Find & replace (⌘F in the text)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }
}
