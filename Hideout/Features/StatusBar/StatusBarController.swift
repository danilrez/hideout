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

enum StatusBarTransitionTrigger: String {
    case launch
    case menuBarButton
    case globalShortcut
    case autoHide
    case hover
    case layoutRecovery
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

    static func hasExpectedItemOrder(
        arrowFrame: CGRect,
        anchorFrame: CGRect,
        isLTR: Bool
    ) -> Bool {
        isLTR ? arrowFrame.minX >= anchorFrame.minX : arrowFrame.minX <= anchorFrame.minX
    }

    static func hasChevronMaintainedOffsetFromAnchor(
        arrowFrame: CGRect,
        anchorFrame: CGRect,
        referenceArrowFrame: CGRect,
        referenceAnchorFrame: CGRect
    ) -> Bool {
        let currentOffset = arrowFrame.minX - anchorFrame.minX
        let referenceOffset = referenceArrowFrame.minX - referenceAnchorFrame.minX
        // Ignore small frame jitter, but treat movement across half the chevron
        // button as a meaningful layout change.
        let toleratedDrift = max(2, arrowFrame.width / 2)
        return abs(currentOffset - referenceOffset) <= toleratedDrift
    }

    static func isChevronSeparatedFromAnchor(
        arrowFrame: CGRect,
        anchorFrame: CGRect,
        isLTR: Bool
    ) -> Bool {
        if isLTR {
            return arrowFrame.minX >= anchorFrame.maxX
        }
        return arrowFrame.maxX <= anchorFrame.minX
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

#if HIDEOUT_DIAGNOSTICS
@MainActor
private final class DiagnosticsMenuVisibilityDelegate: NSObject, NSMenuDelegate {
    weak var diagnosticsItem: NSMenuItem?

    func menuNeedsUpdate(_ menu: NSMenu) {
        diagnosticsItem?.isHidden = !HideoutDiagnostics.isEnabled
    }
}
#endif

@MainActor
class StatusBarController {
    
    //MARK: - Variables
    private var timer: Timer?
    private var diagnosticsHeartbeatTimer: Timer?
    private var layoutWatchdogTimer: Timer?
    private var layoutWatchdogBaselineTask: Task<Void, Never>?
    private var layoutWatchdogGeneration = 0
    // Native menu-bar controls can shift the chevron without hiding its status item.
    private var collapsedChevronReferenceFrames: (arrow: CGRect, anchor: CGRect)?
    private var layoutRecoveryRequiresManualCollapse = false
    
    //MARK: - BarItems

    // Created and named in declaration order on purpose: a status item registers
    // with the menu bar under its autosave name, and on macOS 27 every new name
    // lands left of the previous one, so the item order is anchor, spacers, arrow.
    private static let expandedButtonLength: CGFloat = 24
    private static let expandedAnchorLength: CGFloat = 20
#if HIDEOUT_DIAGNOSTICS
    private static let diagnosticsMenuItemTag = 2
#endif
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
#if HIDEOUT_DIAGNOSTICS
    private var diagnosticsMenuVisibilityDelegate: DiagnosticsMenuVisibilityDelegate?
#endif
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing collapsedBoundaryLength while the bar is collapsed.
        return self.collapseAnchor.length > Self.expandedAnchorLength
    }
    
    private var isCollapseAnchorPositionValid: Bool {
        guard
            let arrowFrame = btnExpandCollapse.button?.frameOnScreen,
            let anchorFrame = collapseAnchor.button?.frameOnScreen
        else { return false }

        return StatusBarLayout.hasExpectedItemOrder(
            arrowFrame: arrowFrame,
            anchorFrame: anchorFrame,
            isLTR: Constant.isUsingLTRLanguage
        )
    }

    private var isChevronSeparatedWhenExpanded: Bool {
        guard
            !isCollapsed,
            let arrowFrame = btnExpandCollapse.button?.frameOnScreen,
            let anchorFrame = collapseAnchor.button?.frameOnScreen
        else { return false }

        return StatusBarLayout.isChevronSeparatedFromAnchor(
            arrowFrame: arrowFrame,
            anchorFrame: anchorFrame,
            isLTR: Constant.isUsingLTRLanguage
        )
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
        recordStatusBarState(
            inflated ? "statusBar.spacersInflated" : "statusBar.spacersDeflated",
            additionalFields: [
                "requestedInflated": String(inflated),
                "activeCount": String(activeCount)
            ]
        )
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
#if HIDEOUT_DIAGNOSTICS
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
#endif
        recordStatusBarState("statusBarController.initialized")
#if HIDEOUT_DIAGNOSTICS
        startDiagnosticsHeartbeat()
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: 10)
        }
        
        autoCollapseIfNeeded()
    }
    
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
#if HIDEOUT_DIAGNOSTICS
        NSWorkspace.shared.notificationCenter.removeObserver(self)
#endif
        hoverDwellTimer?.invalidate()
#if HIDEOUT_DIAGNOSTICS
        diagnosticsHeartbeatTimer?.invalidate()
#endif
        layoutWatchdogTimer?.invalidate()
        layoutWatchdogBaselineTask?.cancel()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func startDiagnosticsHeartbeat() {
#if HIDEOUT_DIAGNOSTICS
        diagnosticsHeartbeatTimer?.invalidate()
        diagnosticsHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordStatusBarState("statusBar.heartbeat")
            }
        }
#endif
    }

    private func startLayoutWatchdog() {
        guard layoutWatchdogTimer == nil, layoutWatchdogBaselineTask == nil else { return }
        layoutWatchdogGeneration += 1
        let generation = layoutWatchdogGeneration
        collapsedChevronReferenceFrames = nil
        recordStatusBarState("statusBar.layoutWatchdog.baselinePending")
        layoutWatchdogBaselineTask = Task { @MainActor [weak self] in
            do {
                // Let AppKit finish applying the new status-item lengths before
                // treating the resulting frames as the collapsed reference.
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard let self else { return }
            guard self.layoutWatchdogGeneration == generation else { return }
            self.layoutWatchdogBaselineTask = nil
            guard self.isCollapsed else { return }
            guard let referenceFrames = self.chevronFramesOnScreen else {
                self.checkCollapsedLayout()
                return
            }

            self.collapsedChevronReferenceFrames = referenceFrames
            self.recordStatusBarState("statusBar.layoutWatchdog.started", additionalFields: [
                "referenceChevronOffsetFromAnchor": self.scalar(
                    referenceFrames.arrow.minX - referenceFrames.anchor.minX
                )
            ])
            self.startLayoutWatchdogTimer(generation: generation)
        }
    }

    private func startLayoutWatchdogTimer(generation: Int) {
        layoutWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.layoutWatchdogGeneration == generation else { return }
                self.checkCollapsedLayout()
            }
        }
    }

    private func stopLayoutWatchdog() {
        layoutWatchdogGeneration += 1
        layoutWatchdogTimer?.invalidate()
        layoutWatchdogTimer = nil
        layoutWatchdogBaselineTask?.cancel()
        layoutWatchdogBaselineTask = nil
        collapsedChevronReferenceFrames = nil
    }

    private func checkCollapsedLayout() {
        guard isCollapsed else {
            stopLayoutWatchdog()
            return
        }

        let currentFrames = chevronFramesOnScreen
        let failureReason: String?
        if !btnExpandCollapse.isVisible {
            failureReason = "chevronItemHidden"
        } else if btnExpandCollapse.button == nil {
            failureReason = "chevronButtonMissing"
        } else if btnExpandCollapse.button?.isHidden == true {
            failureReason = "chevronButtonHidden"
        } else if btnExpandCollapse.button?.window?.isVisible != true {
            failureReason = "chevronWindowHidden"
        } else if currentFrames == nil {
            failureReason = "chevronFrameUnavailable"
        } else if let currentFrames,
                  !StatusBarLayout.hasExpectedItemOrder(
                    arrowFrame: currentFrames.arrow,
                    anchorFrame: currentFrames.anchor,
                    isLTR: Constant.isUsingLTRLanguage
                  ) {
            failureReason = "chevronMovedAcrossAnchor"
        } else if let currentFrames,
                  let referenceFrames = collapsedChevronReferenceFrames,
                  !StatusBarLayout.hasChevronMaintainedOffsetFromAnchor(
                    arrowFrame: currentFrames.arrow,
                    anchorFrame: currentFrames.anchor,
                    referenceArrowFrame: referenceFrames.arrow,
                    referenceAnchorFrame: referenceFrames.anchor
                  ) {
            failureReason = "chevronShiftedDuringCollapse"
        } else if collapsedChevronReferenceFrames == nil {
            failureReason = "chevronReferenceUnavailable"
        } else {
            failureReason = nil
        }

        guard let failureReason else {
            return
        }

        recordStatusBarState("statusBar.layoutWatchdog.warning", additionalFields: [
            "reason": failureReason,
            "referenceChevronOffsetFromAnchor": collapsedChevronReferenceFrames.map {
                scalar($0.arrow.minX - $0.anchor.minX)
            } ?? "unavailable",
            "currentChevronOffsetFromAnchor": currentFrames.map {
                scalar($0.arrow.minX - $0.anchor.minX)
            } ?? "unavailable"
        ])
        layoutRecoveryRequiresManualCollapse = true
        timer?.invalidate()
        timer = nil
        recordStatusBarState("statusBar.layoutRecovery.started", additionalFields: [
            "reason": failureReason
        ])
        expandMenubar(trigger: .layoutRecovery, scheduleAutoHide: false)
    }

    @objc private func handleSystemWillSleep() {
#if HIDEOUT_DIAGNOSTICS
        recordStatusBarState("system.willSleep")
#endif
    }

    @objc private func handleSystemDidWake() {
#if HIDEOUT_DIAGNOSTICS
        recordStatusBarState("system.didWake")
        scheduleLayoutCheckpoints(after: "system.didWake", trigger: nil)
#endif
    }

    private func recordStatusBarState(_ event: String, additionalFields: [String: String] = [:]) {
#if HIDEOUT_DIAGNOSTICS
        guard HideoutDiagnostics.isEnabled else { return }

        let screens = NSScreen.screens.enumerated().map { index, screen in
            "\(index):frame=\(rectDescription(screen.frame)),visible=\(rectDescription(screen.visibleFrame))"
        }
        var fields = [
            "collapsed": String(isCollapsed),
            "anchorPositionValid": String(isCollapseAnchorPositionValid),
            "layoutRecoveryRequiresManualCollapse": String(layoutRecoveryRequiresManualCollapse),
            "collapseUnit": scalar(StatusBarController.collapseUnit),
            "collapsedBoundaryLength": scalar(collapsedBoundaryLength),
            "activeSpacerCount": String(activeSpacerCount),
            "arrow": statusItemDescription(btnExpandCollapse),
            "anchor": statusItemDescription(collapseAnchor),
            "spacers": spacers.enumerated().map { index, item in
                "\(index):visible=\(item.isVisible),length=\(scalar(item.length))"
            }.joined(separator: ";"),
            "glyphImagePresent": String(toggleGlyphView?.image != nil),
            "separatorImagePresent": String(separatorView?.image != nil),
            "layoutDirectionLTR": String(Constant.isUsingLTRLanguage),
            "autoHide": String(Preferences.isAutoHide),
            "autoHideDelaySeconds": String(Preferences.numberOfSecondForAutoHide),
            "fullStatusBarOnExpand": String(Preferences.useFullStatusBarOnExpandEnabled),
            "hoverToExpand": String(Preferences.hoverToExpand),
            "activationPolicy": String(NSApp.activationPolicy().rawValue),
            "screenCount": String(screens.count),
            "screens": screens.joined(separator: ";")
        ]
        fields.merge(additionalFields, uniquingKeysWith: { _, newValue in newValue })
        HideoutDiagnostics.record(event, fields: fields)
#endif
    }

    private func statusItemDescription(_ item: NSStatusItem) -> String {
        let button = item.button
        let origin = button?.getOrigin.map { "\(scalar($0.x)),\(scalar($0.y))" } ?? "nil"
        let frame = button.map { rectDescription($0.frame) } ?? "nil"
        let screenFrame = button?.frameOnScreen.map(rectDescription) ?? "nil"
        let windowVisible = button?.window?.isVisible ?? false
        let buttonHidden = button?.isHidden ?? true
        return "visible=\(item.isVisible),length=\(scalar(item.length)),button=\(button != nil),buttonHidden=\(buttonHidden),windowVisible=\(windowVisible),origin=\(origin),frame=\(frame),screenFrame=\(screenFrame)"
    }

    private var chevronFramesOnScreen: (arrow: CGRect, anchor: CGRect)? {
        guard
            let arrowFrame = btnExpandCollapse.button?.frameOnScreen,
            let anchorFrame = collapseAnchor.button?.frameOnScreen
        else { return nil }
        return (arrow: arrowFrame, anchor: anchorFrame)
    }

    private func rectDescription(_ rect: CGRect) -> String {
        "\(scalar(rect.origin.x)),\(scalar(rect.origin.y)),\(scalar(rect.width)),\(scalar(rect.height))"
    }

    private func scalar(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func scheduleLayoutCheckpoints(after event: String, trigger: StatusBarTransitionTrigger?) {
#if HIDEOUT_DIAGNOSTICS
        for delay in [0.15, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                var fields = ["after": event, "delaySeconds": String(delay)]
                if let trigger {
                    fields["trigger"] = trigger.rawValue
                }
                self.recordStatusBarState("statusBar.layoutCheckpoint", additionalFields: fields)
            }
        }
#endif
    }

    // Opt-in via `defaults write com.danilrez.hideout hoverToExpand -bool true`.
    // No monitor is installed at all unless the pref is true at launch.
    private func setupHoverToExpandIfEnabled() {
        guard Preferences.hoverToExpand else {
            HideoutDiagnostics.record("hover.monitorDisabled")
            return
        }
        HideoutDiagnostics.record("hover.monitorEnabled")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleHoverMouseMoved()
            }
        }
    }

    private func handleHoverMouseMoved() {
        guard isCollapsed && isMouseInMenuBar else {
            if hoverDwellTimer != nil {
                recordStatusBarState("hover.dwellCancelled", additionalFields: [
                    "collapsed": String(isCollapsed),
                    "mouseInMenuBar": String(isMouseInMenuBar)
                ])
            }
            hoverDwellTimer?.invalidate()
            hoverDwellTimer = nil
            return
        }
        // Short dwell so a pointer merely passing through doesn't expand.
        guard hoverDwellTimer == nil else { return }
        recordStatusBarState("hover.dwellScheduled")
        hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseInMenuBar {
                    self.expandMenubar(trigger: .hover)
                } else {
                    self.recordStatusBarState("hover.dwellExpiredWithoutExpand", additionalFields: [
                        "collapsed": String(self.isCollapsed),
                        "mouseInMenuBar": String(self.isMouseInMenuBar)
                    ])
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE items when collapsed, or a
        // display hot-plug leaves the divider and spacers at stale lengths.
        let wasCollapsed = isCollapsed
        recordStatusBarState("screen.parametersChanged.before", additionalFields: [
            "wasCollapsed": String(wasCollapsed)
        ])
        updateCollapsedLengths()
        if wasCollapsed {
            collapseAnchor.length = collapsedBoundaryLength
            setSpacersInflated(true)
        }
        recordStatusBarState("screen.parametersChanged.after", additionalFields: [
            "wasCollapsed": String(wasCollapsed)
        ])
        scheduleLayoutCheckpoints(after: "screen.parametersChanged", trigger: nil)
    }

    private func updateCollapsedLengths() {
        // One collapse unit is applied to every display's copy of the divider.
        // Spacers cover the remaining width on wider displays, while
        // displaced icons go into macOS 27's native overflow menu.
        let screenWidths = NSScreen.screens.map { $0.frame.width }
        let narrowestWidth = screenWidths.min() ?? 1728
        let widestWidth = screenWidths.max() ?? 1728
        collapsedBoundaryLength = StatusBarLayout.collapseUnit(narrowestDisplayWidth: narrowestWidth)
        HideoutDiagnostics.record("statusBar.collapseDimensionsUpdated", fields: [
            "screenCount": String(screenWidths.count),
            "narrowestDisplayWidth": scalar(narrowestWidth),
            "widestDisplayWidth": scalar(widestWidth),
            "collapseUnit": scalar(collapsedBoundaryLength),
            "activeSpacerCount": String(activeSpacerCount)
        ])
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        recordStatusBarState("statusBar.restore.begin")
        btnExpandCollapse.isVisible = true
        collapseAnchor.isVisible = true
        recordStatusBarState("statusBar.restore.end")
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
        recordStatusBarState("statusBar.uiConfigured")
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
            guard !event.modifierFlags.contains(.command) else {
                HideoutDiagnostics.record("statusBar.inputIgnored", fields: ["reason": "commandDrag"])
                return
            }
        }

        if let event = NSApp.currentEvent,
           event.type == .leftMouseUp || event.type == .rightMouseUp {
            let point = sender.convert(event.locationInWindow, from: nil)
            guard let toggleGlyphView, toggleGlyphView.frame.contains(point) else {
                HideoutDiagnostics.record("statusBar.inputIgnored", fields: [
                    "reason": toggleGlyphView == nil ? "glyphMissing" : "outsideGlyph",
                    "eventType": String(event.type.rawValue),
                    "point": "\(scalar(point.x)),\(scalar(point.y))",
                    "glyphFrame": toggleGlyphView.map { rectDescription($0.frame) } ?? "nil"
                ])
                return
            }
        }

        switch ExpandCollapseActionResolver.action(for: NSApp.currentEvent) {
        case .toggle:
            expandCollapseIfNeeded(trigger: .menuBarButton)
        case .contextMenu:
            // Right-click opens the same menu as the collapse divider,
            // making settings reachable from the control everyone clicks.
            recordStatusBarState("statusBar.contextMenuRequested")
            showContextMenu(from: sender)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let menu = collapseAnchor.menu, btnExpandCollapse.menu == nil else {
            HideoutDiagnostics.record("statusBar.contextMenuUnavailable", fields: [
                "anchorMenuPresent": String(collapseAnchor.menu != nil),
                "arrowAlreadyHasMenu": String(btnExpandCollapse.menu != nil)
            ])
            return
        }

        // Let the status item present its native pull-down menu. A generic popup
        // can scroll its first rows offscreen when opened at the menu bar edge.
        btnExpandCollapse.menu = menu
        defer { btnExpandCollapse.menu = nil }
        button.performClick(nil)
    }
    
    func expandCollapseIfNeeded(trigger: StatusBarTransitionTrigger = .menuBarButton) {
        //prevented rapid click cause icon show many in Dock
        guard !isToggle else {
            recordStatusBarState("statusBar.toggleIgnored", additionalFields: [
                "reason": "debounce",
                "trigger": trigger.rawValue
            ])
            return
        }
        isToggle = true
        recordStatusBarState("statusBar.toggleRequested", additionalFields: [
            "trigger": trigger.rawValue
        ])
        if isCollapsed {
            expandMenubar(trigger: trigger)
        } else {
            if trigger == .menuBarButton || trigger == .globalShortcut {
                layoutRecoveryRequiresManualCollapse = false
            }
            collapseMenuBar(trigger: trigger)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    // macOS 27's shared menu-bar window may not have item frames for a beat
    // after launch, so the position guard would skip the first collapse.
    // Retry a few times; if the items were cmd-dragged out of order the guard
    // stays false and we stop, same as before.
    private func collapseMenuBarOnLaunch(attemptsLeft: Int) {
        let positionValid = isCollapseAnchorPositionValid
        let chevronSeparated = isChevronSeparatedWhenExpanded
        if (positionValid && chevronSeparated) || attemptsLeft <= 0 {
            recordStatusBarState("statusBar.launchCollapseReady", additionalFields: [
                "attemptsLeft": String(attemptsLeft),
                "anchorPositionValid": String(positionValid),
                "chevronSeparatedWhenExpanded": String(chevronSeparated)
            ])
            collapseMenuBar(trigger: .launch)
            return
        }
        recordStatusBarState("statusBar.launchCollapseRetry", additionalFields: [
            "attemptsLeft": String(attemptsLeft),
            "anchorPositionValid": String(positionValid),
            "chevronSeparatedWhenExpanded": String(chevronSeparated)
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: attemptsLeft - 1)
        }
    }

    private func collapseMenuBar(trigger: StatusBarTransitionTrigger) {
        let positionValid = isCollapseAnchorPositionValid
        let chevronSeparated = isChevronSeparatedWhenExpanded
        let alreadyCollapsed = isCollapsed
        recordStatusBarState("statusBar.collapseRequested", additionalFields: [
            "trigger": trigger.rawValue,
            "anchorPositionValid": String(positionValid),
            "chevronSeparatedWhenExpanded": String(chevronSeparated),
            "alreadyCollapsed": String(alreadyCollapsed)
        ])
        guard positionValid && chevronSeparated && !alreadyCollapsed else {
            let geometryInvalid = !positionValid || !chevronSeparated
            recordStatusBarState("statusBar.collapseSkipped", additionalFields: [
                "trigger": trigger.rawValue,
                "reason": alreadyCollapsed
                    ? "alreadyCollapsed"
                    : (positionValid ? "chevronOverlapsExpandedAnchor" : "anchorPositionInvalid")
            ])
            if geometryInvalid && !alreadyCollapsed {
                layoutRecoveryRequiresManualCollapse = true
                timer?.invalidate()
                timer = nil
                recordStatusBarState("statusBar.layoutRecovery.suspended", additionalFields: [
                    "reason": positionValid ? "chevronOverlapsExpandedAnchor" : "anchorPositionInvalid",
                    "trigger": trigger.rawValue
                ])
            }
            return
        }

        collapseAnchor.length = self.collapsedBoundaryLength
        setSpacersInflated(true)
        toggleGlyphView?.image = Assets.expandImage
        let previousActivationPolicy = NSApp.activationPolicy().rawValue
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        recordStatusBarState("statusBar.collapseApplied", additionalFields: [
            "trigger": trigger.rawValue,
            "previousActivationPolicy": String(previousActivationPolicy),
            "activationPolicy": String(NSApp.activationPolicy().rawValue)
        ])
        startLayoutWatchdog()
        scheduleLayoutCheckpoints(after: "collapse", trigger: trigger)
    }

    private func expandMenubar(
        trigger: StatusBarTransitionTrigger,
        scheduleAutoHide: Bool = true
    ) {
        guard isCollapsed else {
            recordStatusBarState("statusBar.expandSkipped", additionalFields: [
                "trigger": trigger.rawValue,
                "reason": "alreadyExpanded"
            ])
            return
        }
        recordStatusBarState("statusBar.expandRequested", additionalFields: [
            "trigger": trigger.rawValue
        ])
        stopLayoutWatchdog()
        collapseAnchor.length = Self.expandedAnchorLength
        setSpacersInflated(false)
        toggleGlyphView?.image = Assets.collapseImage
        if scheduleAutoHide {
            autoCollapseIfNeeded(reason: "expanded")
        } else {
            timer?.invalidate()
            timer = nil
            recordStatusBarState("autoHide.timerNotScheduled", additionalFields: [
                "reason": "layoutRecovery"
            ])
        }
        
        let previousActivationPolicy = NSApp.activationPolicy().rawValue
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
        recordStatusBarState("statusBar.expandApplied", additionalFields: [
            "trigger": trigger.rawValue,
            "previousActivationPolicy": String(previousActivationPolicy),
            "activationPolicy": String(NSApp.activationPolicy().rawValue)
        ])
        scheduleLayoutCheckpoints(after: "expand", trigger: trigger)
    }
    
    private func autoCollapseIfNeeded(reason: String = "requested") {
        guard !layoutRecoveryRequiresManualCollapse else {
            recordStatusBarState("autoHide.timerNotScheduled", additionalFields: [
                "reason": "layoutRecoveryRequiresManualCollapse"
            ])
            return
        }
        guard Preferences.isAutoHide else {
            recordStatusBarState("autoHide.timerNotScheduled", additionalFields: ["reason": "disabled"])
            return
        }
        guard !isCollapsed else {
            recordStatusBarState("autoHide.timerNotScheduled", additionalFields: ["reason": "alreadyCollapsed"])
            return
        }

        startTimerToAutoHide(reason: reason)
    }

    private func startTimerToAutoHide(reason: String) {
        timer?.invalidate()
        let delay = Preferences.numberOfSecondForAutoHide
        recordStatusBarState("autoHide.timerScheduled", additionalFields: [
            "reason": reason,
            "delaySeconds": String(delay)
        ])
        self.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard Preferences.isAutoHide else {
                    self.recordStatusBarState("autoHide.timerIgnored", additionalFields: ["reason": "disabledBeforeFire"])
                    return
                }
                // Don't yank the bar shut mid-interaction: while the pointer is in the
                // menubar (hovering, clicking, dragging icons), defer and re-arm.
                // Intentionally unbounded; each re-arm invalidates the previous timer,
                // so deferral never accumulates timers.
                let mouseInMenuBar = self.isMouseInMenuBar
                let preferencesWindowVisible = self.isPreferencesWindowVisible
                self.recordStatusBarState("autoHide.timerFired", additionalFields: [
                    "mouseInMenuBar": String(mouseInMenuBar),
                    "preferencesWindowVisible": String(preferencesWindowVisible)
                ])
                if mouseInMenuBar || preferencesWindowVisible {
                    self.startTimerToAutoHide(reason: "deferredInteraction")
                } else {
                    self.collapseMenuBar(trigger: .autoHide)
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

#if HIDEOUT_DIAGNOSTICS
        let diagnosticsItem = NSMenuItem(
            title: "Open Diagnostics Folder".localized,
            action: #selector(openDiagnosticsFolder),
            keyEquivalent: ""
        )
        diagnosticsItem.tag = Self.diagnosticsMenuItemTag
        diagnosticsItem.isHidden = !HideoutDiagnostics.isEnabled
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)
        let diagnosticsMenuDelegate = DiagnosticsMenuVisibilityDelegate()
        diagnosticsMenuDelegate.diagnosticsItem = diagnosticsItem
        diagnosticsMenuVisibilityDelegate = diagnosticsMenuDelegate
        menu.delegate = diagnosticsMenuDelegate
#endif
        
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
        recordStatusBarState("preferences.changed")
        autoCollapseIfNeeded(reason: "preferencesChanged")
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }

    @objc func openAboutWindow() {
        Util.showAboutWindow()
    }

#if HIDEOUT_DIAGNOSTICS
    @objc func openDiagnosticsFolder() {
        HideoutDiagnostics.openDiagnosticsFolder(source: "menuBar")
    }
#endif
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}
