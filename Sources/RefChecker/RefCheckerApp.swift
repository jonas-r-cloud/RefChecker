import SwiftUI
import AppKit

@main
struct RefCheckerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("RefChecker") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Paper…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .printItem) {
                Button("Export Report as HTML…") { model.exportHTML() }
                    .keyboardShortcut("e")
                    .disabled(model.results.isEmpty)
                Button("Print Report…") { model.printReport() }
                    .keyboardShortcut("p")
                    .disabled(model.results.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button(model.showBrowser ? "Hide Browser" : "Show Browser") { model.showBrowser.toggle() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Reference List…") { model.textController.showFindBar() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
            CommandMenu("References") {
                Button("Split into References") { model.parseSection() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Check All References") { model.checkAll() }
                    .keyboardShortcut("k")
                    .disabled(model.references.isEmpty || model.isChecking)
                Button("Stop Checking") { model.cancel() }
                    .keyboardShortcut(".")
                    .disabled(!model.isChecking)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (e.g. `swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
