import Cocoa

@MainActor
extension NSStackView {
    func removeAllSubViews() {
        for view in self.views {
            // Deactivate constraints before removal or they leak on every
            // tutorial-view rebuild.
            NSLayoutConstraint.deactivate(view.constraints)
            view.removeFromSuperview()
        }
    }
}
