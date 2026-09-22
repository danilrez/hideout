import Cocoa

@MainActor
final class AdaptiveSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    private func configureLayer() {
        wantsLayer = true
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}

@MainActor
final class AdaptiveSettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.shadowColor = NSColor.shadowColor.cgColor
        }
    }
}

@MainActor
class PreferencesWindowController: NSWindowController {
    
    enum MenuSegment: Int {
        case general
        case about
    }
    
    static let shared: PreferencesWindowController = {
        let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as! PreferencesWindowController
        return wc
    }()
    
    private var menuSegment: MenuSegment = .general {
        didSet {
            updateVC()
        }
    }
    
    private let preferencesVC = PreferencesViewController.initWithStoryboard()
    
    private let aboutVC = AboutViewController.initWithStoryboard()

    private var contentHostVC = NSViewController()
    private var activeViewController: NSViewController?
    private weak var segmentControl: NSSegmentedControl?

    private let segmentToolbarItemIdentifier = NSToolbarItem.Identifier(
        "F7DA19CF-BC58-47E1-8140-D04939EE4CA7"
    )
    
    override func windowDidLoad() {
        super.windowDidLoad()

        configureWindow()
        configureToolbar()
        installContentHost()
        updateVC()
    }
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        if let vc = activeViewController as? PreferencesViewController, vc.listening {
            vc.updateGlobalShortcut(event)
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if let vc = activeViewController as? PreferencesViewController, vc.listening {
            vc.updateModiferFlags(event)
        }
    }
    
    @IBAction func switchSegment(_ sender: NSSegmentedControl) {
        guard let segment = MenuSegment(rawValue: sender.indexOfSelectedItem) else {return}
        menuSegment = segment
    }
    
    private func configureWindow() {
        guard let window else { return }

        // Let the material extend under the titlebar so the header and content
        // read as one translucent surface. Child layouts use safeAreaLayoutGuide
        // to stay below the toolbar.
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .visible
        window.title = "Hideout"
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 680, height: 404)
        window.setContentSize(NSSize(width: 720, height: 404))
        window.center()
    }

    private func configureToolbar() {
        guard let toolbar = window?.toolbar else { return }

        toolbar.autosavesConfiguration = false
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [segmentToolbarItemIdentifier]

        let item: NSToolbarItem
        if let existingItem = toolbar.items.first(where: {
            $0.itemIdentifier == segmentToolbarItemIdentifier
        }) {
            item = existingItem
        } else {
            toolbar.insertItem(withItemIdentifier: segmentToolbarItemIdentifier, at: 0)
            guard let insertedItem = toolbar.items.first(where: {
                $0.itemIdentifier == segmentToolbarItemIdentifier
            }) else { return }
            item = insertedItem
        }

        let control = NSSegmentedControl(
            labels: ["General", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(switchSegment(_:))
        )
        control.frame = NSRect(x: 0, y: 0, width: 168, height: 28)
        item.view = control
        item.label = "Preferences"
        item.paletteLabel = "Preferences"

        control.role = .tabs
        control.borderShape = .capsule
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.controlSize = .regular
        control.focusRingType = .none
        control.selectedSegment = menuSegment.rawValue
        control.setAccessibilityIdentifier("preferences-tabs")
        control.setAccessibilityLabel("Preferences sections")
        segmentControl = control
    }

    private func installContentHost() {
        guard let window else { return }

        // Use the empty storyboard shell to satisfy AppKit's window-controller
        // contract, then let this controller own the actual content view.
        if let storyboardContentHost = window.contentViewController {
            contentHostVC = storyboardContentHost
        }

        let hostView = NSVisualEffectView(frame: .zero)
        hostView.material = .sidebar
        hostView.blendingMode = .behindWindow
        hostView.state = .active
        contentHostVC.view = hostView
        window.contentViewController = contentHostVC
    }

    private func updateVC() {
        guard isWindowLoaded else { return }

        let nextViewController: NSViewController
        switch menuSegment {
        case .general:
            nextViewController = preferencesVC
        case .about:
            nextViewController = aboutVC
        }

        if activeViewController !== nextViewController {
            if let activeViewController {
                activeViewController.view.removeFromSuperview()
                activeViewController.removeFromParent()
            }

            contentHostVC.addChild(nextViewController)
            let nextView = nextViewController.view
            nextView.translatesAutoresizingMaskIntoConstraints = false
            contentHostVC.view.addSubview(nextView)
            NSLayoutConstraint.activate([
                nextView.leadingAnchor.constraint(equalTo: contentHostVC.view.leadingAnchor),
                nextView.trailingAnchor.constraint(equalTo: contentHostVC.view.trailingAnchor),
                nextView.topAnchor.constraint(equalTo: contentHostVC.view.topAnchor),
                nextView.bottomAnchor.constraint(equalTo: contentHostVC.view.bottomAnchor)
            ])
            activeViewController = nextViewController
        }

        segmentControl?.selectedSegment = menuSegment.rawValue
    }
    
}
