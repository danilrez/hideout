import Cocoa

@MainActor
class PreferencesViewController: NSViewController {
    // MARK: - Controls
    // The storyboard only provides the view-controller shell. The controls and
    // their actions belong here so the layout has a single source of truth.
    private let tutorialTitleLabel = NSTextField(labelWithString: "")
    private let statusBarStackView = NSStackView()
    private let arrowPointToHiddenImage = NSImageView()

    private let checkBoxAutoHide = NSButton()
    private let checkBoxLogin = NSButton()
    private let checkBoxShowPreferences = NSButton()
    private let checkBoxUseFullStatusbar = NSButton()
    private let timePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let btnClear = NSButton()
    private let btnShortcut = NSButton()

    private var tutorialArrowConstraints: [NSLayoutConstraint] = []
    private var tutorialStateLabelConstraints: [NSLayoutConstraint] = []
    private var tutorialHiddenLabel: NSTextField?
    private var tutorialShownLabel: NSTextField?
    private let settingsColumnInset: CGFloat = 16
    
    public var listening = false {
        didSet {
            let isHighlight = listening
            
            DispatchQueue.main.async { [weak self] in
                self?.btnShortcut.highlight(isHighlight)
            }
        }
    }
    
    //MARK: - VC Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupModernLayout()
        updateData()
        loadGlobalShortcut()
        hideStatusBar()
        NotificationCenter.default.addObserver(self, selector: #selector(updateData), name: .prefsChanged, object: nil)
    }

    deinit {
        // Balance the viewDidLoad observer (PRs #335/#346).
        NotificationCenter.default.removeObserver(self, name: .prefsChanged, object: nil)
    }

    static func initWithStoryboard() -> PreferencesViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "prefVC") as! PreferencesViewController
        return vc
    }

    // MARK: - Modern layout

    private func setupModernLayout() {
        NSLayoutConstraint.deactivate(view.constraints)
        view.subviews.forEach { $0.removeFromSuperview() }

        configureControls()

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        let tutorialContent = NSView()
        tutorialContent.translatesAutoresizingMaskIntoConstraints = false
        tutorialContent.heightAnchor.constraint(equalToConstant: 148).isActive = true
        rootStack.addArrangedSubview(tutorialContent)
        tutorialContent.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        setupTutorialContent(tutorialContent)

        let tutorialSeparator = NSBox()
        tutorialSeparator.boxType = .separator
        tutorialSeparator.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(tutorialSeparator)
        NSLayoutConstraint.activate([
            tutorialSeparator.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: settingsColumnInset),
            tutorialSeparator.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -settingsColumnInset),
            tutorialSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
        rootStack.setCustomSpacing(12, after: tutorialContent)
        rootStack.setCustomSpacing(4, after: tutorialSeparator)

        let settingsContent = makeSettingsContent()
        settingsContent.heightAnchor.constraint(equalToConstant: 168).isActive = true
        rootStack.addArrangedSubview(settingsContent)
        settingsContent.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        let footer = makeSettingsFooter()
        footer.heightAnchor.constraint(equalToConstant: 26).isActive = true
        rootStack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        rootStack.setCustomSpacing(12, after: settingsContent)
    }

    private func configureControls() {
        let switches = [
            checkBoxLogin,
            checkBoxShowPreferences,
            checkBoxUseFullStatusbar,
            checkBoxAutoHide
        ]
        switches.forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setButtonType(.switch)
            button.controlSize = .regular
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }

        checkBoxLogin.title = localizedMainString(
            "W1G-55-zGo",
            fallback: "Start Hideout when I log in"
        )
        checkBoxLogin.target = self
        checkBoxLogin.action = #selector(loginCheckChanged(_:))

        checkBoxShowPreferences.title = localizedMainString(
            "hCh-Ue-NgH",
            fallback: "Show preferences on launch"
        )
        checkBoxShowPreferences.target = self
        checkBoxShowPreferences.action = #selector(showPreferencesChanged(_:))

        checkBoxUseFullStatusbar.title = localizedMainString(
            "8z8-6N-wnc",
            fallback: "Use the full MenuBar on expanding"
        )
        checkBoxUseFullStatusbar.target = self
        checkBoxUseFullStatusbar.action = #selector(useFullStatusBarOnExpandChanged(_:))

        checkBoxAutoHide.title = NSLocalizedString(
            "Auto-hide after",
            comment: "Short label for automatic menu bar icon hiding"
        )
        checkBoxAutoHide.target = self
        checkBoxAutoHide.action = #selector(autoHideCheckChanged(_:))
        checkBoxAutoHide.cell?.wraps = false
        checkBoxAutoHide.cell?.lineBreakMode = .byTruncatingTail
        checkBoxAutoHide.setContentHuggingPriority(.defaultLow, for: .horizontal)
        checkBoxAutoHide.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timePopup.translatesAutoresizingMaskIntoConstraints = false
        timePopup.controlSize = .regular
        timePopup.removeAllItems()
        timePopup.addItems(withTitles: [
            localizedMainString("bzS-lm-JvT", fallback: "5 seconds"),
            localizedMainString("z2X-nw-vxX", fallback: "10 seconds"),
            localizedMainString("rdn-Xm-fZD", fallback: "15 seconds"),
            localizedMainString("Ch6-Z2-LyX", fallback: "30 seconds"),
            localizedMainString("Zkr-Xd-Ffh", fallback: "1 minute")
        ])
        timePopup.target = self
        timePopup.action = #selector(timePopupDidSelected(_:))
        timePopup.widthAnchor.constraint(equalToConstant: 108).isActive = true

        btnShortcut.translatesAutoresizingMaskIntoConstraints = false
        btnShortcut.title = "Set Shortcut".localized
        btnShortcut.target = self
        btnShortcut.action = #selector(register(_:))
        btnShortcut.controlSize = .regular
        btnShortcut.bezelStyle = .push

        btnClear.translatesAutoresizingMaskIntoConstraints = false
        btnClear.title = "⌫"
        btnClear.target = self
        btnClear.action = #selector(unregister(_:))
        btnClear.isEnabled = false
        btnClear.controlSize = .regular
        btnClear.bezelStyle = .push
        btnClear.widthAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func localizedMainString(_ objectID: String, fallback: String) -> String {
        Bundle.main.localizedString(
            forKey: "\(objectID).title",
            value: fallback,
            table: "Main"
        )
    }

    private func setupTutorialContent(_ contentView: NSView) {
        tutorialTitleLabel.stringValue = "How to use"
        tutorialTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        tutorialTitleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        tutorialTitleLabel.textColor = .labelColor

        let instructionLabel = NSTextField(
            labelWithString: "Hold ⌘ and drag icons between the Hidden and Shown sections."
        )
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        instructionLabel.textColor = .secondaryLabelColor

        let previewSurface = NSVisualEffectView()
        previewSurface.material = .underWindowBackground
        previewSurface.blendingMode = .withinWindow
        previewSurface.state = .active
        previewSurface.wantsLayer = true
        previewSurface.layer?.cornerRadius = 6
        previewSurface.layer?.masksToBounds = true
        previewSurface.translatesAutoresizingMaskIntoConstraints = false

        statusBarStackView.translatesAutoresizingMaskIntoConstraints = false
        statusBarStackView.alignment = .centerY
        statusBarStackView.spacing = 12
        statusBarStackView.distribution = .fill

        // The arrow is owned entirely by the modern tutorial layout.
        arrowPointToHiddenImage.translatesAutoresizingMaskIntoConstraints = false
        let tutorialArrowImage = Assets.systemSymbol(named: "arrow.up")
        arrowPointToHiddenImage.image = tutorialArrowImage
        arrowPointToHiddenImage.imageScaling = .scaleProportionallyDown
        arrowPointToHiddenImage.contentTintColor = .secondaryLabelColor

        let hiddenLabel = makeBodyLabel(
            localizedMainString("cXt-8R-PHo", fallback: "Hidden")
        )
        let shownLabel = makeBodyLabel(
            localizedMainString("iyS-g5-5mk", fallback: "Shown")
        )
        hiddenLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        shownLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hiddenLabel.translatesAutoresizingMaskIntoConstraints = false
        shownLabel.translatesAutoresizingMaskIntoConstraints = false
        tutorialHiddenLabel = hiddenLabel
        tutorialShownLabel = shownLabel

        contentView.addSubview(tutorialTitleLabel)
        contentView.addSubview(instructionLabel)
        contentView.addSubview(previewSurface)
        previewSurface.addSubview(statusBarStackView)
        contentView.addSubview(arrowPointToHiddenImage)
        contentView.addSubview(hiddenLabel)
        contentView.addSubview(shownLabel)

        NSLayoutConstraint.activate([
            tutorialTitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            tutorialTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsColumnInset),
            tutorialTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -settingsColumnInset),

            instructionLabel.topAnchor.constraint(equalTo: tutorialTitleLabel.bottomAnchor, constant: 4),
            instructionLabel.leadingAnchor.constraint(equalTo: tutorialTitleLabel.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -settingsColumnInset),

            previewSurface.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 12),
            previewSurface.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsColumnInset),
            previewSurface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsColumnInset),
            previewSurface.heightAnchor.constraint(equalToConstant: 36),

            statusBarStackView.leadingAnchor.constraint(greaterThanOrEqualTo: previewSurface.leadingAnchor, constant: 12),
            statusBarStackView.trailingAnchor.constraint(lessThanOrEqualTo: previewSurface.trailingAnchor, constant: -12),
            statusBarStackView.centerXAnchor.constraint(equalTo: previewSurface.centerXAnchor),
            statusBarStackView.centerYAnchor.constraint(equalTo: previewSurface.centerYAnchor),
            statusBarStackView.heightAnchor.constraint(equalToConstant: 24),

            arrowPointToHiddenImage.topAnchor.constraint(equalTo: previewSurface.bottomAnchor, constant: 6),
            arrowPointToHiddenImage.widthAnchor.constraint(equalToConstant: 16),
            arrowPointToHiddenImage.heightAnchor.constraint(equalToConstant: 16),
            hiddenLabel.topAnchor.constraint(equalTo: arrowPointToHiddenImage.bottomAnchor, constant: 2),
            hiddenLabel.heightAnchor.constraint(equalToConstant: 16),
            hiddenLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            hiddenLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            shownLabel.topAnchor.constraint(equalTo: hiddenLabel.topAnchor),
            shownLabel.heightAnchor.constraint(equalTo: hiddenLabel.heightAnchor),
            shownLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            shownLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            hiddenLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            shownLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    private func makeBehaviorContent() -> NSView {
        let contentView = NSView()
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        section.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(section)

        let title = makeSectionHeader("Behavior")
        section.addArrangedSubview(title)
        section.addArrangedSubview(checkBoxLogin)
        section.addArrangedSubview(checkBoxShowPreferences)
        section.addArrangedSubview(checkBoxUseFullStatusbar)

        let autoHideRow = NSStackView(views: [checkBoxAutoHide, timePopup])
        autoHideRow.orientation = .horizontal
        autoHideRow.alignment = .centerY
        autoHideRow.spacing = 8
        autoHideRow.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(autoHideRow)

        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsColumnInset),
            section.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsColumnInset),
            section.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            section.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
            autoHideRow.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            autoHideRow.trailingAnchor.constraint(equalTo: section.trailingAnchor)
        ])
        return contentView
    }

    private func makeShortcutContent() -> NSView {
        let contentView = NSView()
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 12
        section.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(section)

        section.addArrangedSubview(makeSectionHeader(
            localizedMainString("HJP-Lf-rxm", fallback: "Keyboard shortcut")
        ))
        let shortcutDescription = makeBodyLabel("Use a shortcut to show or hide the menu bar.")
        shortcutDescription.alignment = .left
        section.addArrangedSubview(shortcutDescription)
        shortcutDescription.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        let shortcutRow = NSStackView(views: [btnShortcut, btnClear])
        shortcutRow.orientation = .horizontal
        shortcutRow.alignment = .centerY
        shortcutRow.spacing = 6
        shortcutRow.translatesAutoresizingMaskIntoConstraints = false
        btnShortcut.widthAnchor.constraint(equalToConstant: 158).isActive = true
        section.addArrangedSubview(shortcutRow)

        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsColumnInset),
            section.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsColumnInset),
            section.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            section.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])
        return contentView
    }

    private func makeSettingsContent() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let behaviorContent = makeBehaviorContent()
        behaviorContent.translatesAutoresizingMaskIntoConstraints = false

        let shortcutContent = makeShortcutContent()
        shortcutContent.translatesAutoresizingMaskIntoConstraints = false

        let columnSplit = NSLayoutGuide()
        container.addLayoutGuide(columnSplit)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(behaviorContent)
        container.addSubview(shortcutContent)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            columnSplit.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            columnSplit.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.485),

            separator.centerXAnchor.constraint(equalTo: columnSplit.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            separator.widthAnchor.constraint(equalToConstant: 1),

            behaviorContent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            behaviorContent.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
            behaviorContent.topAnchor.constraint(equalTo: container.topAnchor),
            behaviorContent.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            shortcutContent.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            shortcutContent.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shortcutContent.topAnchor.constraint(equalTo: container.topAnchor),
            shortcutContent.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeSettingsFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let helpPrompt = NSTextField(labelWithString: "Need help or want to contribute?")
        helpPrompt.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpPrompt.textColor = .secondaryLabelColor

        let links = NSStackView(views: [
            makeFooterLink(
                title: "GitHub",
                href: "https://github.com/danilrez/hideout"
            ),
            makeFooterLink(
                title: "Email us",
                href: "mailto:code.cli.agent@gmail.com"
            )
        ])
        links.orientation = .horizontal
        links.alignment = .centerY
        links.spacing = 16
        links.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [helpPrompt, spacer, links])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: settingsColumnInset),
            row.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -settingsColumnInset),
            row.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])

        return footer
    }

    private func makeFooterLink(title: String, href: String) -> HyperlinkTextField {
        let link = HyperlinkTextField(frame: .zero)
        link.stringValue = title
        link.href = href
        link.isBezeled = false
        link.drawsBackground = false
        link.isEditable = false
        link.isSelectable = false
        link.focusRingType = .none
        link.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        link.textColor = .linkColor
        link.setContentHuggingPriority(.required, for: .horizontal)
        return link
    }

    private func makeSectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
        return label
    }

    private func makeBodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.cell?.wraps = true
        label.cell?.lineBreakMode = .byWordWrapping
        return label
    }
    
    //MARK: - Actions
    @IBAction func loginCheckChanged(_ sender: NSButton) {
        Preferences.isAutoStart = sender.state == .on
    }
    
    @IBAction func autoHideCheckChanged(_ sender: NSButton) {
        Preferences.isAutoHide = sender.state == .on
    }
    
    @IBAction func showPreferencesChanged(_ sender: NSButton) {
        Preferences.isShowPreference = sender.state == .on
    }
    
    @IBAction func useFullStatusBarOnExpandChanged(_ sender: NSButton) {
        Preferences.useFullStatusBarOnExpandEnabled = sender.state == .on
    }
    
    
    @IBAction func timePopupDidSelected(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        if let selectedInSecond = SelectedSecond(rawValue: selectedIndex)?.toSeconds() {
            Preferences.numberOfSecondForAutoHide = selectedInSecond
        }
    }
    
    // When the set shortcut button is pressed start listening for the new shortcut
    @IBAction func register(_ sender: Any) {
        listening = true
        view.window?.makeFirstResponder(nil)
    }
    
    // If the shortcut is cleared, clear the UI and tell AppDelegate to stop listening to the previous keybind.
    @IBAction func unregister(_ sender: Any?) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.globalShortcutController.unregister()
        btnShortcut.title = "Set Shortcut".localized
        listening = false
        btnClear.isEnabled = false
        
        // Remove globalkey from userdefault
        Preferences.globalKey = nil
    }
    
    public func updateGlobalShortcut(_ event: NSEvent) {
        self.listening = false
        
        guard let characters = event.charactersIgnoringModifiers else {return}
        
        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: event.modifierFlags.carbonFlags,
            characters: characters,
            keyCode: uint32(event.keyCode))
        
        Preferences.globalKey = newGlobalKeybind
        
        updateKeybindButton(newGlobalKeybind)
        btnClear.isEnabled = true
        
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.globalShortcutController.register(
            keyCode: UInt32(event.keyCode),
            modifiers: event.modifierFlags.carbonFlags
        )
    }
    
    public func updateModiferFlags(_ event: NSEvent) {
        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: 0,
            characters: nil,
            keyCode: uint32(event.keyCode))
        
        updateModifierbindButton(newGlobalKeybind)
        
    }
    
    @objc private func updateData(){
        checkBoxUseFullStatusbar.state = Preferences.useFullStatusBarOnExpandEnabled ? .on : .off
        checkBoxLogin.state = Preferences.isAutoStart ? .on : .off
        checkBoxAutoHide.state = Preferences.isAutoHide ? .on : .off
        checkBoxShowPreferences.state = Preferences.isShowPreference ? .on : .off
        timePopup.selectItem(at: SelectedSecond.secondToPossition(seconds: Preferences.numberOfSecondForAutoHide))
    }
    
    private func loadGlobalShortcut() {
        if let globalKey = Preferences.globalKey {
            updateKeybindButton(globalKey)
            updateClearButton(globalKey)
        }
    }

    // Set the shortcut button to show the keys to press
    private func updateKeybindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
        btnShortcut.title = globalKeybindPreference.description
        
        if globalKeybindPreference.description.count <= 1 {
            unregister(nil)
        }
    }
    
    // Set the shortcut button to show the modifier to press
      private func updateModifierbindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
          btnShortcut.title = globalKeybindPreference.description
          
          if globalKeybindPreference.description.isEmpty {
              unregister(nil)
          }
      }
    
    // If a keybind is set, allow users to clear it by enabling the clear button.
    private func updateClearButton(_ globalKeybindPreference : GlobalKeybindPreferences?) {
        btnClear.isEnabled = globalKeybindPreference != nil
    }
}

//MARK: - Show tutorial
extension PreferencesViewController {
    
    func hideStatusBar() {
        statusBarStackView.removeAllSubViews()
        let imageWidth: CGFloat = 16
        
        
        let hiddenIcons = ["drop", "bag", "gamecontroller", "cloud", "headphones"].map { symbolName in
            NSImageView(image: Assets.systemSymbol(named: symbolName)!)
        }
        let shownIcons = ["display", "speaker.wave.2", "moon", "battery.100", "wifi", "magnifyingglass", "switch.2"].map { symbolName in
            NSImageView(image: Assets.systemSymbol(named: symbolName)!)
        }

        let separatorImage = NSImageView(image: Assets.separatorImage!)
        separatorImage.alphaValue = 0.6
        let images = hiddenIcons + [separatorImage, NSImageView(image: Assets.collapseImage!)] + shownIcons
        
        
        for image in images {
            statusBarStackView.addArrangedSubview(image)
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: imageWidth),
                image.heightAnchor.constraint(equalToConstant: imageWidth)
                
            ])
            image.contentTintColor = .labelColor
        }
        let dateTimeLabel = NSTextField()
        dateTimeLabel.stringValue = Date.dateString() + " " + Date.timeString()
        dateTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        dateTimeLabel.isBezeled = false
        dateTimeLabel.isEditable = false
        dateTimeLabel.sizeToFit()
        dateTimeLabel.backgroundColor = .clear
        dateTimeLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        statusBarStackView.addArrangedSubview(dateTimeLabel)
        NSLayoutConstraint.activate([dateTimeLabel.heightAnchor.constraint(equalToConstant: imageWidth)
        ])
       
        updateTutorialArrowConstraints(
            hiddenArrowAnchor: separatorImage.centerXAnchor,
            hiddenLabelAnchor: hiddenIcons[hiddenIcons.count / 2].centerXAnchor,
            shownLabelAnchor: shownIcons[shownIcons.count / 2].centerXAnchor
        )
    }

    private func updateTutorialArrowConstraints(
        hiddenArrowAnchor: NSLayoutXAxisAnchor,
        hiddenLabelAnchor: NSLayoutXAxisAnchor,
        shownLabelAnchor: NSLayoutXAxisAnchor
    ) {
        NSLayoutConstraint.deactivate(tutorialArrowConstraints)
        NSLayoutConstraint.deactivate(tutorialStateLabelConstraints)
        tutorialArrowConstraints = [
            arrowPointToHiddenImage.centerXAnchor.constraint(equalTo: hiddenArrowAnchor)
        ]
        tutorialStateLabelConstraints = []

        if
            let hiddenLabel = tutorialHiddenLabel,
            let shownLabel = tutorialShownLabel
        {
            tutorialStateLabelConstraints = [
                hiddenLabel.centerXAnchor.constraint(equalTo: hiddenLabelAnchor),
                shownLabel.centerXAnchor.constraint(equalTo: shownLabelAnchor)
            ]
        }

        NSLayoutConstraint.activate(tutorialArrowConstraints + tutorialStateLabelConstraints)
    }
}
