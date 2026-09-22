import AppKit

enum WindowPlacement {
    static func centeredOrigin(for windowFrame: NSRect, in visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - windowFrame.width / 2,
            y: visibleFrame.midY - windowFrame.height / 2
        )
    }
}

@MainActor
extension NSWindow {
    func bringToFront() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
