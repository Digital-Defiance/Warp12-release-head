import AppKit

/// Brings the GUI to the foreground when launched from Terminal (`swift run`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        activateAndFocusWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateAndFocusWindow()
    }

    private func activateAndFocusWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
