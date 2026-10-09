import AppKit

@MainActor
class AboutViewController: NSViewController {

    override func loadView() {
        let surface = NSVisualEffectView(frame: .zero)
        surface.material = .windowBackground
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
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "A quiet place for your menu bar")
        subtitle.font = NSFont.systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor

        let version = Bundle.main.releaseVersionNumber ?? "unknown"
        let build = Bundle.main.buildVersionNumber ?? "unknown"

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .centerX
        headerStack.spacing = 6

        let versionRow = infoRow(title: "Version".localized, value: version)
        let buildRow = infoRow(title: "Build".localized, value: build)

        let rowsStack = NSStackView(views: [versionRow.row, buildRow.row])
        versionRow.titleLabel.widthAnchor.constraint(equalTo: buildRow.titleLabel.widthAnchor).isActive = true
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        let licenseLink = NSButton(
            title: "MIT License",
            target: self,
            action: #selector(openLicense(_:))
        )
        licenseLink.isBordered = false
        licenseLink.controlSize = .small
        licenseLink.attributedTitle = NSAttributedString(
            string: "MIT License",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )

        let copyright = NSTextField(labelWithString: "© 2026 Danil Reznichenko")
        copyright.font = NSFont.systemFont(ofSize: 10)
        copyright.textColor = .secondaryLabelColor

        let footerStack = NSStackView(views: [licenseLink, copyright])
        footerStack.orientation = .vertical
        footerStack.alignment = .centerX
        footerStack.spacing = 2

        let contentStack = NSStackView(views: [
            icon,
            headerStack,
            rowsStack,
            footerStack
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setCustomSpacing(12, after: icon)
        contentStack.setCustomSpacing(16, after: headerStack)
        contentStack.setCustomSpacing(16, after: rowsStack)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            contentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14)
        ])
    }

    private func infoRow(title: String, value: String) -> (row: NSStackView, titleLabel: NSTextField) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .right

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabelColor

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return (row, titleLabel)
    }

    @objc private func openLicense(_ sender: Any?) {
        openWebPage("https://github.com/danilrez/Hideout/blob/main/LICENSE")
    }

    private func openWebPage(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()
    private static let contentSize = NSSize(width: 300, height: 300)

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
