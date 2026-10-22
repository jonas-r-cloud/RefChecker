import AppKit
import WebKit

/// Renders the HTML report off-screen and opens the standard print dialog
/// (which also offers "Save as PDF").
@MainActor
final class ReportPrinter: NSObject, WKNavigationDelegate {
    static let shared = ReportPrinter()

    private var webView: WKWebView?
    private var printWindow: NSWindow?

    func print(html: String) {
        let configuration = WKWebViewConfiguration()
        if #available(macOS 13.3, *) {
            configuration.preferences.shouldPrintBackgrounds = true
        }
        let frame = NSRect(x: 0, y: 0, width: 1100, height: 1400)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        // WKWebView only prints reliably when it is hosted in a window.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.isReleasedWhenClosed = false
        self.webView = webView
        self.printWindow = window
        webView.loadHTMLString(html, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.runPrintOperation(for: webView) }
    }

    private func runPrintOperation(for webView: WKWebView) {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 28
        info.bottomMargin = 28
        info.leftMargin = 28
        info.rightMargin = 28

        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.jobTitle = "Reference check"
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
