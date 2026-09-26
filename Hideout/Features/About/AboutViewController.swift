import AppKit

@MainActor
class AboutViewController: NSViewController {

    override func loadView() {
        let surface = NSVisualEffectView(frame: .zero)
        surface.material = .sidebar
        surface.blendingMode = .behindWindow
        surface.state = .active
        view = surface
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        NSLayoutConstraint.deactivate(view.constraints)
        view.subviews.forEach { $0.removeFromSuperview() }

        let icon = NSImageView(image: Assets.appIcon ?? NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityLabel("Hideout")
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Hideout")
        title.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "A quiet place for your menu bar")
        subtitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor

        let version = Bundle.main.releaseVersionNumber.map {
            "Version \($0) (beta)"
        } ?? "Beta"
        let versionLabel = NSTextField(labelWithString: version)
        versionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        versionLabel.textColor = .labelColor

        let copyright = NSTextField(labelWithString: "© 2025 Danil Reznichenko")
        copyright.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        copyright.textColor = .secondaryLabelColor

        let license = NSTextField(labelWithString: "MIT License")
        license.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        license.textColor = .secondaryLabelColor

        let contentStack = NSStackView(views: [
            icon,
            title,
            subtitle,
            versionLabel,
            copyright,
            license
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setCustomSpacing(12, after: icon)
        contentStack.setCustomSpacing(10, after: title)
        contentStack.setCustomSpacing(14, after: versionLabel)
        contentStack.setCustomSpacing(2, after: copyright)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            contentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()
    private static let contentSize = NSSize(width: 284, height: 252)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.title = "About Hideout"
        window.toolbar = nil
        window.contentMinSize = Self.contentSize
        window.contentViewController = AboutViewController()
        window.setContentSize(Self.contentSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
