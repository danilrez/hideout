import Cocoa

@MainActor
class PreferencesWindowController: NSWindowController {

    static let shared: PreferencesWindowController = {
        let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as! PreferencesWindowController
        return wc
    }()

    private let preferencesVC = PreferencesViewController.initWithStoryboard()

    private var contentHostVC = NSViewController()

    override func windowDidLoad() {
        super.windowDidLoad()

        configureWindow()
        installContentHost()
        installPreferencesView()
        window?.setContentSize(NSSize(width: 760, height: 448))
        window?.center()
    }
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        if preferencesVC.listening {
            preferencesVC.updateGlobalShortcut(event)
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if preferencesVC.listening {
            preferencesVC.updateModiferFlags(event)
        }
    }

    private func configureWindow() {
        guard let window else { return }

        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.titleVisibility = .visible
        window.title = "Hideout"
        window.toolbar = nil
        window.contentMinSize = NSSize(width: 720, height: 448)
    }

    private func installContentHost() {
        guard let window else { return }

        // Use the empty storyboard shell to satisfy AppKit's window-controller
        // contract, then let this controller own the actual content view.
        if let storyboardContentHost = window.contentViewController {
            contentHostVC = storyboardContentHost
        }

        let backgroundView = NSVisualEffectView(frame: .zero)
        backgroundView.material = .windowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .followsWindowActiveState
        contentHostVC.view = backgroundView
        window.contentViewController = contentHostVC
    }

    private func installPreferencesView() {
        contentHostVC.addChild(preferencesVC)
        let preferencesView = preferencesVC.view
        preferencesView.translatesAutoresizingMaskIntoConstraints = false
        contentHostVC.view.addSubview(preferencesView)
        NSLayoutConstraint.activate([
            preferencesView.leadingAnchor.constraint(equalTo: contentHostVC.view.leadingAnchor),
            preferencesView.trailingAnchor.constraint(equalTo: contentHostVC.view.trailingAnchor),
            preferencesView.topAnchor.constraint(equalTo: contentHostVC.view.topAnchor),
            preferencesView.bottomAnchor.constraint(equalTo: contentHostVC.view.bottomAnchor)
        ])
    }

}
