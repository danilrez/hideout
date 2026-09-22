import AppKit

enum ExpandCollapseAction: Equatable {
    case toggle
    case contextMenu
    case toggleSeparators
}

enum ExpandCollapseActionResolver {
    static func action(for event: NSEvent?) -> ExpandCollapseAction {
        action(
            eventType: event?.type,
            optionPressed: event?.modifierFlags.contains(.option) ?? false
        )
    }

    static func action(eventType: NSEvent.EventType?, optionPressed: Bool) -> ExpandCollapseAction {
        guard let eventType else { return .toggle }

        if eventType == .leftMouseUp && !optionPressed {
            return .toggle
        }
        if eventType == .rightMouseUp && !optionPressed {
            return .contextMenu
        }
        return .toggleSeparators
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
class StatusBarController {
    
    //MARK: - Variables
    private var timer: Timer?
    
    //MARK: - BarItems

    // Created and named in declaration order on purpose: a status item registers
    // with the menu bar under its autosave name, and on macOS 27 every new name
    // lands left of the previous one, so the bar reads separator, spacers, arrow.
    private let btnExpandCollapse = StatusBarController.makeItem("hiddenbar_expandcollapse", length: NSStatusItem.variableLength)
    private let spacers: [NSStatusItem] = StatusBarController.makeSpacers()  // macOS 27 only, empty elsewhere
    private let btnSeparate = StatusBarController.makeItem("hiddenbar_separate", length: 1)
    
    private var btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000
    
    private let imgIconSeparator = Assets.separatorImage
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing btnHiddenCollapseLength while the bar is collapsed.
        return self.btnSeparate.length > self.btnHiddenLength
    }
    
    private var isBtnSeparateValidPosition: Bool {
        guard
            let btnExpandCollapseX = self.btnExpandCollapse.button?.getOrigin?.x,
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnExpandCollapseX >= btnSeparateX
        } else {
            return btnExpandCollapseX <= btnSeparateX
        }
    }
    
    private var isToggle = false

    // macOS 27 keeps every item's position in its own layout table, keyed by
    // autosave name, and the app can neither read nor seed it. A new item always
    // lands leftmost. The spacers can therefore only end up between the arrow
    // and the separator if all three are registered fresh, in order, so on 27 the
    // items use new names. Upgraders drag their icons past the separator once,
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

    // Below the cliff macOS 27 pushes the icons left of the separator into its
    // native overflow menu («), but only once they reach the frontmost app's
    // menus. One unit does not span that distance on wide displays, so the
    // separator gets company: zero-length items to its right that inflate with
    // it. macOS overflows from the left, so the icons go first and the spacers
    // stay; surplus spacers overflow themselves, which is harmless. The count
    // is fixed so every launch registers the same names: a name first seen on a
    // later launch would land leftmost, outside the block. Seven units cover a
    // 5800pt display next to an 1800pt one.
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
    // while collapsed. Their lengths provide the span between the arrow and
    // separator; inactive spacers stay hidden at zero length.
    private func setSpacersInflated(_ inflated: Bool) {
        let activeCount = inflated ? activeSpacerCount : 0
        for (index, spacer) in spacers.enumerated() {
            let shouldBeVisible = index < activeCount
            let targetLength = shouldBeVisible ? btnHiddenCollapseLength : 0

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
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
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
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length.
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        if wasCollapsed {
            btnSeparate.length = btnHiddenCollapseLength
            setSpacersInflated(true)
        }
    }

    private func updateCollapsedLengths() {
        // One collapse unit is applied to every display's copy of the status
        // item. Spacers cover the remaining width on wider displays, while
        // displaced icons go into macOS 27's native overflow menu.
        btnHiddenCollapseLength = StatusBarController.collapseUnit
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconSeparator
        }
        let menu = self.getContextMenu()
        btnSeparate.menu = menu

        updateAutoCollapseMenuTitle()
        
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        switch ExpandCollapseActionResolver.action(for: NSApp.currentEvent) {
        case .toggle:
            expandCollapseIfNeeded()
        case .contextMenu:
            // Right-click opens the same context menu the separator has (#356),
            // making settings reachable from the control everyone clicks.
            showContextMenu(from: sender)
        case .toggleSeparators:
            // Both option+left and option+right land here: separators toggle.
            showHideSeparators()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let menu = btnSeparate.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }
    
    private func showHideSeparators() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
    }
    
    private func hideSeparators() {
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
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
        if isBtnSeparateValidPosition || attemptsLeft <= 0 {
            collapseMenuBar()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: attemptsLeft - 1)
        }
    }

    private func collapseMenuBar() {
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        btnSeparate.length = self.btnHiddenCollapseLength
        setSpacersInflated(true)
        setSeparatorGlyphVisible(false)
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        btnSeparate.length = btnHiddenLength
        setSpacersInflated(false)
        setSeparatorGlyphVisible(true)
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
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

    // The button draws the separator glyph centered in the item's span. On
    // macOS 27 that span remains on-screen while collapsed, so hiding the glyph
    // avoids a stray separator mid-menu-bar (#360). Clicks still land on the item.
    private func setSeparatorGlyphVisible(_ visible: Bool) {
        btnSeparate.button?.image = visible ? imgIconSeparator : nil
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
        
        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
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
        guard let toggleAutoHideItem = btnSeparate.menu?.item(withTag: 1) else { return }
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
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}
