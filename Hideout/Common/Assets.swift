import AppKit

@MainActor
struct Assets {
    static var appIcon: NSImage? {
        NSImage(named: NSImage.Name("AppIcon"))
    }

    static func systemSymbol(named name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    static var expandImage: NSImage? {
        systemSymbol(named: "chevron.backward")
    }

    static var collapseImage: NSImage? {
        systemSymbol(named: "chevron.forward")
    }

    static var separatorImage: NSImage? {
        systemSymbol(named: "poweron")
    }

    static var dotImage: NSImage? {
        systemSymbol(named: "circlebadge.fill")
    }
}
