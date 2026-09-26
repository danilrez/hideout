import AppKit

enum ExpandCollapseAction: Equatable {
    case toggle
    case contextMenu
}

enum ExpandCollapseActionResolver {
    static func action(for event: NSEvent?) -> ExpandCollapseAction {
        action(eventType: event?.type)
    }

    static func action(eventType: NSEvent.EventType?) -> ExpandCollapseAction {
        guard let eventType else { return .toggle }

        if eventType == .rightMouseUp {
            return .contextMenu
        }
        return .toggle
    }
}

enum StatusBarLayout {
    static func collapseUnit(narrowestDisplayWidth: CGFloat) -> CGFloat {
        max(200, (narrowestDisplayWidth / 2 - 64).rounded(.down))
    }

    static func activeSpacerCount(
        widestDisplayWidth: CGFloat,
        collapseUnit: CGFloat,
        availableSpacers: Int
    ) -> Int {
        guard collapseUnit > 0, availableSpacers > 0 else { return 0 }
        let requiredUnits = Int(ceil(widestDisplayWidth / collapseUnit))
        return min(availableSpacers, max(0, requiredUnits - 1))
    }
}

@MainActor
enum StatusBarGlyphLayout {
    static func updateEdgeConstraint(
        _ edgeConstraint: inout NSLayoutConstraint?,
        glyphView: NSView,
        button: NSView,
        isLTR: Bool,
        inset: CGFloat
    ) {
        edgeConstraint?.isActive = false
        let updatedConstraint: NSLayoutConstraint
        if isLTR {
            updatedConstraint = glyphView.trailingAnchor.constraint(
                equalTo: button.trailingAnchor,
                constant: -inset
            )
        } else {
            updatedConstraint = glyphView.leadingAnchor.constraint(
                equalTo: button.leadingAnchor,
                constant: inset
            )
        }
        updatedConstraint.isActive = true
        edgeConstraint = updatedConstraint
    }
}

@MainActor
private final class StatusBarGlyphView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private final class StatusBarSeparatorView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
class StatusBarController {
    
    //MARK: - Variables
    private var timer: Timer?
    
    //MARK: - BarItems

    // Created and named in declaration order on purpose: a status item registers
    // with the menu bar under its autosave name, and on macOS 27 every new name
    // lands left of the previous one, so the item order is anchor, spacers, arrow.
    private static let expandedButtonLength: CGFloat = 24
    private static let expandedAnchorLength: CGFloat = 20
    private let btnExpandCollapse = StatusBarController.makeItem(
        "hiddenbar_expandcollapse",
        length: StatusBarController.expandedButtonLength
    )
    private let spacers: [NSStatusItem] = StatusBarController.makeSpacers()  // macOS 27 only, empty elsewhere
    // Keep the legacy autosave name and position. The divider owns the expanding
    // collapse boundary so the chevron remains a normal, reachable status item.
    private let collapseAnchor = StatusBarController.makeItem(
        "hiddenbar_separate",
        length: StatusBarController.expandedAnchorLength
    )
    
    private var collapsedBoundaryLength: CGFloat = 2000
    private var toggleGlyphView: StatusBarGlyphView?
    private var glyphEdgeConstraint: NSLayoutConstraint?
    private var separatorView: StatusBarSeparatorView?
    private var separatorEdgeConstraint: NSLayoutConstraint?
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing collapsedBoundaryLength while the bar is collapsed.
        return self.collapseAnchor.length > Self.expandedAnchorLength
    }
    
    private var isCollapseAnchorPositionValid: Bool {
        guard
            let btnExpandCollapseX = self.btnExpandCollapse.button?.getOrigin?.x,
            let collapseAnchorX = self.collapseAnchor.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnExpandCollapseX >= collapseAnchorX
        } else {
            return btnExpandCollapseX <= collapseAnchorX
        }
    }
    
    private var isToggle = false

    // macOS 27 keeps every item's position in its own layout table, keyed by
    // autosave name, and the app can neither read nor seed it. A new item always
    // lands leftmost. The spacers can therefore only end up between the arrow
    // and the anchor if all three are registered fresh, in order, so on 27 the
    // items use new names. Upgraders drag their icons past the arrow once,
    // as on a fresh install.
    private static let autosaveSuffix = "_v27"

    // macOS 27 drops a status item whose length reaches half the display width
    // instead of clamping it (#360). Measured on 27.0: a 3008pt display keeps
    // 1480pt and drops 1500pt. One length is applied on every display's bar, so
    // the unit is sized under the NARROWEST display's cliff.
    private static var collapseUnit: CGFloat {
        let narrowest = NSScreen.screens.map { $0.frame.width }.min() ?? 1728
        return StatusBarLayout.collapseUnit(narrowestDisplayWidth: narrowest)
    }

    private static func makeItem(_ name: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.autosaveName = name + autosaveSuffix
        return item
    }

    // Below the cliff macOS pushes status items to the left of the divider into
    // its native overflow menu («), but only once they reach the frontmost app's
    // menus. One unit does not span that distance on wide displays, so fixed
    // zero-length items after the divider inflate with it. macOS overflows
    // from the left, so user icons go first and the spacers stay; surplus
    // spacers overflow themselves, which is harmless. The count is fixed so
    // every launch registers the same names: a name first seen later would land
    // leftmost, outside the block. Seven units cover a 5800pt display next to
    // an 1800pt one.
    private static func makeSpacers() -> [NSStatusItem] {
        return (0..<6).map { index in
            let item = makeItem("hiddenbar_spacer\(index)", length: 0)
            item.button?.isEnabled = false
            item.isVisible = false
            return item
        }
    }

    // Keep all six items registered so macOS 27 preserves their order, but only
    // inflate the number needed to cover the widest attached display. The
    // upstream fix inflated every spacer on every display, which caused several
    // avoidable shared-menu-bar layout passes on ordinary screens.
    private var activeSpacerCount: Int {
        guard !spacers.isEmpty else { return 0 }
        let widest = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        return StatusBarLayout.activeSpacerCount(
            widestDisplayWidth: widest,
            collapseUnit: StatusBarController.collapseUnit,
            availableSpacers: spacers.count
        )
    }

    // Keep every spacer registered, but make only the active spacers visible
    // while collapsed. Their lengths extend the divider's collapse boundary;
    // inactive spacers stay hidden at zero length.
    private func setSpacersInflated(_ inflated: Bool) {
        let activeCount = inflated ? activeSpacerCount : 0
        for (index, spacer) in spacers.enumerated() {
            let shouldBeVisible = index < activeCount
            let targetLength = shouldBeVisible ? collapsedBoundaryLength : 0

            if spacer.isVisible != shouldBeVisible {
                spacer.isVisible = shouldBeVisible
            }
            if spacer.length != targetLength {
                spacer.length = targetLength
            }
        }
    }

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?

    // True while the pointer sits in any screen's menubar band (the strip between
    // visibleFrame.maxY and frame.maxY, which is the menubar's exact height there).
    // On fullscreen spaces the menubar is hidden and the band collapses to ~zero,
    // so this returns false there: intentional, no visible menubar = no deferral.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // The preferences window is an ordinary app window, not in the menu bar, so
    // the mouse-in-menubar guard does not cover it. With "use full menu bar on
    // expanding" on, an auto-collapse deactivates the app and dismisses this
    // window mid-edit (#170, same family as #66/#151). Defer the collapse while
    // it is on screen. isWindowLoaded short-circuits without force-loading the
    // window when preferences were never opened.
    private var isPreferencesWindowVisible: Bool {
        let wc = PreferencesWindowController.shared
        return wc.isWindowLoaded && (wc.window?.isVisible ?? false)
    }
    
    //MARK: - Methods
    init() {
        updateCollapsedLengths()
        setupUI()
        restoreRemovedStatusItems()
        setupHoverToExpandIfEnabled()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: 10)
        }
        
        autoCollapseIfNeeded()
    }
    
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // Opt-in via `defaults write com.danilrez.hideout hoverToExpand -bool true`.
    // No monitor is installed at all unless the pref is true at launch.
    private func setupHoverToExpandIfEnabled() {
        guard Preferences.hoverToExpand else { return }
        NSLog("HoverToExpand: enabled, installing global mouse monitor")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleHoverMouseMoved()
            }
        }
    }

    private func handleHoverMouseMoved() {
        guard isCollapsed && isMouseInMenuBar else {
            hoverDwellTimer?.invalidate()
            hoverDwellTimer = nil
            return
        }
        // Short dwell so a pointer merely passing through doesn't expand.
        guard hoverDwellTimer == nil else { return }
        hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseInMenuBar {
                    self.expandMenubar()
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE items when collapsed, or a
        // display hot-plug leaves the divider and spacers at stale lengths.
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        if wasCollapsed {
            collapseAnchor.length = collapsedBoundaryLength
            setSpacersInflated(true)
        }
    }

    private func updateCollapsedLengths() {
        // One collapse unit is applied to every display's copy of the divider.
        // Spacers cover the remaining width on wider displays, while
        // displaced icons go into macOS 27's native overflow menu.
        collapsedBoundaryLength = StatusBarController.collapseUnit
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        collapseAnchor.isVisible = true
    }

    private func setupUI() {
        if let button = collapseAnchor.button {
            button.image = nil
            button.title = ""

            let separatorView = StatusBarSeparatorView()
            separatorView.image = Assets.separatorImage
            separatorView.imageScaling = .scaleProportionallyDown
            separatorView.alphaValue = 0.6
            separatorView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(separatorView)
            self.separatorView = separatorView

            NSLayoutConstraint.activate([
                separatorView.widthAnchor.constraint(equalToConstant: 16),
                separatorView.heightAnchor.constraint(equalToConstant: 16),
                separatorView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            updateSeparatorPositionConstraint(separatorView: separatorView, button: button)
        }
        let menu = self.getContextMenu()
        collapseAnchor.menu = menu

        updateAutoCollapseMenuTitle()
        
        if let button = btnExpandCollapse.button {
            button.image = nil
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let glyphView = StatusBarGlyphView()
            glyphView.image = Assets.collapseImage
            glyphView.imageScaling = .scaleProportionallyDown
            glyphView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(glyphView)

            let glyphInset: CGFloat = 3
            NSLayoutConstraint.activate([
                glyphView.widthAnchor.constraint(equalToConstant: 16),
                glyphView.heightAnchor.constraint(equalToConstant: 16),
                glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            toggleGlyphView = glyphView
            updateGlyphPositionConstraint(inset: glyphInset)
        }
    }

    func updateGlyphPositionConstraint(inset: CGFloat = 3) {
        guard let button = btnExpandCollapse.button, let toggleGlyphView else { return }
        StatusBarGlyphLayout.updateEdgeConstraint(
            &glyphEdgeConstraint,
            glyphView: toggleGlyphView,
            button: button,
            isLTR: Constant.isUsingLTRLanguage,
            inset: inset
        )
        if let separatorView, let separatorButton = collapseAnchor.button {
            updateSeparatorPositionConstraint(
                separatorView: separatorView,
                button: separatorButton,
                inset: inset
            )
        }
    }

    private func updateSeparatorPositionConstraint(
        separatorView: NSView,
        button: NSStatusBarButton,
        inset: CGFloat = 3
    ) {
        separatorEdgeConstraint?.isActive = false
        let updatedConstraint = Constant.isUsingLTRLanguage
            ? separatorView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -inset)
            : separatorView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: inset)
        updatedConstraint.isActive = true
        separatorEdgeConstraint = updatedConstraint
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            // Command-dragging status items should only change their order.
            guard !event.modifierFlags.contains(.command) else { return }
        }

        if let event = NSApp.currentEvent,
           event.type == .leftMouseUp || event.type == .rightMouseUp {
            let point = sender.convert(event.locationInWindow, from: nil)
            guard let toggleGlyphView, toggleGlyphView.frame.contains(point) else { return }
        }

        switch ExpandCollapseActionResolver.action(for: NSApp.currentEvent) {
        case .toggle:
            expandCollapseIfNeeded()
        case .contextMenu:
            // Right-click opens the same menu as the collapse divider,
            // making settings reachable from the control everyone clicks.
            showContextMenu(from: sender)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let menu = collapseAnchor.menu, btnExpandCollapse.menu == nil else { return }

        // Let the status item present its native pull-down menu. A generic popup
        // can scroll its first rows offscreen when opened at the menu bar edge.
        btnExpandCollapse.menu = menu
        defer { btnExpandCollapse.menu = nil }
        button.performClick(nil)
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    // macOS 27's shared menu-bar window may not have item frames for a beat
    // after launch, so the position guard would skip the first collapse.
    // Retry a few times; if the items were cmd-dragged out of order the guard
    // stays false and we stop, same as before.
    private func collapseMenuBarOnLaunch(attemptsLeft: Int) {
        if isCollapseAnchorPositionValid || attemptsLeft <= 0 {
            collapseMenuBar()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: attemptsLeft - 1)
        }
    }

    private func collapseMenuBar() {
        guard self.isCollapseAnchorPositionValid && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        collapseAnchor.length = self.collapsedBoundaryLength
        setSpacersInflated(true)
        toggleGlyphView?.image = Assets.expandImage
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        collapseAnchor.length = Self.expandedAnchorLength
        setSpacersInflated(false)
        toggleGlyphView?.image = Assets.collapseImage
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, Preferences.isAutoHide else { return }
                // Don't yank the bar shut mid-interaction: while the pointer is in the
                // menubar (hovering, clicking, dragging icons), defer and re-arm.
                // Intentionally unbounded; each re-arm invalidates the previous timer,
                // so deferral never accumulates timers.
                if self.isMouseInMenuBar || self.isPreferencesWindowVisible {
                    self.startTimerToAutoHide()
                } else {
                    self.collapseMenuBar()
                }
            }
        }
    }
    
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        let aboutItem = NSMenuItem(
            title: "About Hideout".localized,
            action: #selector(openAboutWindow),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())

        let prefItem = NSMenuItem(title: "Settings...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: ",")
        prefItem.keyEquivalentModifierMask = [.command]
        prefItem.target = self
        menu.addItem(prefItem)
        
        let toggleAutoHideItem = NSMenuItem(title: "Toggle Auto Collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        toggleAutoHideItem.tag = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        return menu
    }
    
    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = collapseAnchor.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func updateAutoHide() {
        updateAutoCollapseMenuTitle()
        autoCollapseIfNeeded()
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }

    @objc func openAboutWindow() {
        Util.showAboutWindow()
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}
