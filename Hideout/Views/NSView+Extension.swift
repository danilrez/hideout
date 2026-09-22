import Foundation
import AppKit
@MainActor
extension NSView {
    // Convert the view's own frame to screen space. macOS 27 hosts the menu bar
    // items in one window, so the view's frame distinguishes one item from
    // another; window.origin alone does not.
    var getOrigin: CGPoint? {
        guard let window = self.window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil)).origin
    }
}
