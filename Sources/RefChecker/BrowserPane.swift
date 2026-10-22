import SwiftUI
import AppKit
import WebKit

/// The web view of the optional browser pane. Kept alive while the pane is hidden,
/// so its page and history survive toggling.
@MainActor
final class BrowserModel: NSObject, ObservableObject, WKUIDelegate {
    let webView: WKWebView
    @Published var urlString = ""
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        // Some publisher sites only serve full pages to browsers they recognise.
        configuration.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.uiDelegate = self
        observations = [
            webView.observe(\.url) { [weak self] wv, _ in
                Task { @MainActor in self?.urlString = wv.url?.absoluteString ?? "" }
            },
            webView.observe(\.title) { [weak self] wv, _ in
                Task { @MainActor in self?.title = wv.title ?? "" }
            },
            webView.observe(\.canGoBack) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoForward = wv.canGoForward }
            },
            webView.observe(\.isLoading) { [weak self] wv, _ in
                Task { @MainActor in self?.isLoading = wv.isLoading }
            },
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                Task { @MainActor in self?.progress = wv.estimatedProgress }
            }
        ]
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Opens an address, or searches Google Scholar for anything that is not one.
    func open(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let url = URL(string: text), url.scheme == "http" || url.scheme == "https" {
            load(url)
        } else if text.range(of: "^10\\.\\d{4,9}/\\S+$", options: .regularExpression) != nil,
                  let url = URL(string: "https://doi.org/\(text)") {
            load(url)
        } else if !text.contains(" "), text.contains("."), let url = URL(string: "https://\(text)") {
            load(url)
        } else {
            load(Self.scholarSearch(text))
        }
    }

    static func scholarSearch(_ query: String) -> URL {
        var c = URLComponents(string: "https://scholar.google.com/scholar")!
        c.queryItems = [URLQueryItem(name: "q", value: String(query.prefix(300)))]
        return c.url!
    }

    func openInDefaultBrowser() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    // Links that want a new window (target="_blank") open in the pane instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct BrowserPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var browser: BrowserModel
    @State private var address = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                    .help("Back")
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                    .help("Forward")
                Button {
                    if browser.isLoading { browser.webView.stopLoading() } else { browser.webView.reload() }
                } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                }
                .help(browser.isLoading ? "Stop" : "Reload")
                TextField("Address, DOI or search", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { browser.open(address) }
                Button { browser.openInDefaultBrowser() } label: { Image(systemName: "safari") }
                    .disabled(browser.urlString.isEmpty)
                    .help("Open in your default browser")
                Button { model.showBrowser = false } label: { Image(systemName: "sidebar.right") }
                    .help("Hide browser")
            }
            .buttonStyle(.borderless)
            .padding(6)

            ProgressView(value: browser.isLoading ? browser.progress : 0)
                .progressViewStyle(.linear)
                .frame(height: 2)
                .opacity(browser.isLoading ? 1 : 0)
            Divider()

            ZStack {
                WebView(webView: browser.webView)
                if browser.urlString.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "globe").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("Click \(Image(systemName: "globe")) on a reference to open the website of its record here.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .onAppear { address = browser.urlString }
        .onChange(of: browser.urlString) { address = $0 }
    }
}
