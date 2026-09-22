import Cocoa

@MainActor
class AboutViewController: NSViewController {

    private let imageViewTop = NSImageView()
    private let lblVersion = NSTextField(labelWithString: "")
    
    static func initWithStoryboard() -> AboutViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "aboutVC") as! AboutViewController
        return vc
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        NSLayoutConstraint.deactivate(view.constraints)
        view.subviews.forEach { $0.removeFromSuperview() }

        imageViewTop.image = Assets.appIcon
        imageViewTop.imageScaling = .scaleProportionallyDown
        imageViewTop.translatesAutoresizingMaskIntoConstraints = false

        lblVersion.font = NSFont.systemFont(ofSize: 13)
        lblVersion.textColor = .secondaryLabelColor
        lblVersion.alignment = .center
        lblVersion.translatesAutoresizingMaskIntoConstraints = false

        if let version = Bundle.main.releaseVersionNumber {
            lblVersion.stringValue = "Version \(version) (beta)"
        }

        let hero = NSStackView()
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = 22
        hero.translatesAutoresizingMaskIntoConstraints = false

        let heroText = NSStackView()
        heroText.orientation = .vertical
        heroText.alignment = .leading
        heroText.spacing = 5
        heroText.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Hideout")
        title.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "A quiet place for your menu bar")
        subtitle.font = NSFont.systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabelColor

        heroText.addArrangedSubview(title)
        heroText.addArrangedSubview(subtitle)
        heroText.addArrangedSubview(lblVersion)
        hero.addArrangedSubview(imageViewTop)
        hero.addArrangedSubview(heroText)

        let links = NSStackView()
        links.orientation = .vertical
        links.alignment = .leading
        links.spacing = 10
        links.translatesAutoresizingMaskIntoConstraints = false
        links.addArrangedSubview(makeLinkRow(
            title: "GitHub",
            href: "https://github.com/danilrez",
            symbolName: "apple.terminal"
        ))
        links.addArrangedSubview(makeLinkRow(
            title: "Email us",
            href: "mailto:code.cli.agent@gmail.com",
            symbolName: "envelope.fill"
        ))

        let copyright = NSTextField(labelWithString: "MIT © Danil Reznichenko")
        copyright.font = NSFont.systemFont(ofSize: 11)
        copyright.textColor = .tertiaryLabelColor
        copyright.alignment = .center

        let contentStack = NSStackView(views: [hero, links, copyright])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 22
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            imageViewTop.widthAnchor.constraint(equalToConstant: 92),
            imageViewTop.heightAnchor.constraint(equalToConstant: 92),
            contentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -36)
        ])
    }

    private func makeLinkRow(title: String, href: String, symbolName: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage()
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let link = HyperlinkTextField(frame: .zero)
        link.stringValue = title
        link.href = href
        link.isBezeled = false
        link.drawsBackground = false
        link.isEditable = false
        link.isSelectable = false
        link.focusRingType = .none
        link.font = NSFont.systemFont(ofSize: 13)
        link.textColor = .linkColor

        row.addArrangedSubview(imageView)
        row.addArrangedSubview(link)
        return row
    }

}
