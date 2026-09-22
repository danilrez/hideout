import AppKit

@MainActor
extension NSWindow {
    func bringToFront() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
