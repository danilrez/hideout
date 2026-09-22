import Cocoa
import Carbon
import HotKey

@MainActor
class PreferencesViewController: NSViewController {
    // MARK: - Controls
    // The storyboard only provides the view-controller shell. The controls and
    // their actions belong here so the layout has a single source of truth.
    private let textFieldTitle = NSTextField(labelWithString: "")
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
    private let settingsColumnInset: CGFloat = 22
    
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
        loadHotkey()
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
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        let tutorialContainer = NSView()
        tutorialContainer.translatesAutoresizingMaskIntoConstraints = false
        tutorialContainer.heightAnchor.constraint(equalToConstant: 160).isActive = true

        let tutorialContent = NSView()
        tutorialContent.translatesAutoresizingMaskIntoConstraints = false
        tutorialContainer.addSubview(tutorialContent)
        NSLayoutConstraint.activate([
            tutorialContent.centerXAnchor.constraint(equalTo: tutorialContainer.centerXAnchor),
            tutorialContent.widthAnchor.constraint(equalTo: tutorialContainer.widthAnchor, multiplier: 0.72),
            tutorialContent.topAnchor.constraint(equalTo: tutorialContainer.topAnchor),
            tutorialContent.bottomAnchor.constraint(equalTo: tutorialContainer.bottomAnchor)
        ])
        rootStack.addArrangedSubview(tutorialContainer)
        tutorialContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        setupTutorialCard(tutorialContent)

        let settingsCard = makeUnifiedSettingsCard()
        settingsCard.heightAnchor.constraint(equalToConstant: 176).isActive = true
        rootStack.addArrangedSubview(settingsCard)
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
        btnShortcut.bezelStyle = .glass
        btnShortcut.borderShape = .roundedRectangle

        btnClear.translatesAutoresizingMaskIntoConstraints = false
        btnClear.title = "⌫"
        btnClear.target = self
        btnClear.action = #selector(unregister(_:))
        btnClear.isEnabled = false
        btnClear.controlSize = .regular
        btnClear.bezelStyle = .glass
        btnClear.borderShape = .roundedRectangle
        btnClear.widthAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func localizedMainString(_ objectID: String, fallback: String) -> String {
        Bundle.main.localizedString(
            forKey: "\(objectID).title",
            value: fallback,
            table: "Main"
        )
    }

    private func setupTutorialCard(_ contentView: NSView) {
        textFieldTitle.stringValue = localizedMainString(
            "k7C-e5-6a0",
            fallback: "In your Mac's menu bar, hold ⌘ and drag icons\nbetween sections to configure Hideout."
        )
        textFieldTitle.translatesAutoresizingMaskIntoConstraints = false
        textFieldTitle.alignment = .center
        textFieldTitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        textFieldTitle.textColor = .secondaryLabelColor
        textFieldTitle.maximumNumberOfLines = 2
        textFieldTitle.cell?.wraps = true
        textFieldTitle.cell?.lineBreakMode = .byWordWrapping

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
        hiddenLabel.translatesAutoresizingMaskIntoConstraints = false
        shownLabel.translatesAutoresizingMaskIntoConstraints = false
        tutorialHiddenLabel = hiddenLabel
        tutorialShownLabel = shownLabel

        contentView.addSubview(textFieldTitle)
        contentView.addSubview(statusBarStackView)
        contentView.addSubview(arrowPointToHiddenImage)
        contentView.addSubview(hiddenLabel)
        contentView.addSubview(shownLabel)

        NSLayoutConstraint.activate([
            textFieldTitle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            textFieldTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            textFieldTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            textFieldTitle.heightAnchor.constraint(equalToConstant: 38),

            statusBarStackView.topAnchor.constraint(equalTo: textFieldTitle.bottomAnchor, constant: 14),
            statusBarStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            statusBarStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            statusBarStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusBarStackView.heightAnchor.constraint(equalToConstant: 22),

            arrowPointToHiddenImage.topAnchor.constraint(equalTo: statusBarStackView.bottomAnchor, constant: 7),
            arrowPointToHiddenImage.widthAnchor.constraint(equalToConstant: 20),
            arrowPointToHiddenImage.heightAnchor.constraint(equalToConstant: 20),
            hiddenLabel.topAnchor.constraint(equalTo: arrowPointToHiddenImage.bottomAnchor, constant: 2),
            hiddenLabel.heightAnchor.constraint(equalToConstant: 24),
            hiddenLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            hiddenLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            shownLabel.topAnchor.constraint(equalTo: hiddenLabel.topAnchor),
            shownLabel.heightAnchor.constraint(equalTo: hiddenLabel.heightAnchor),
            shownLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            shownLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            hiddenLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            shownLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func makeBehaviorContent() -> NSView {
        let contentView = NSView()
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 11
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
            section.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            section.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
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
        section.addArrangedSubview(makeBodyLabel("Use a shortcut to show or hide the menu bar."))

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
            section.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            section.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
        return contentView
    }

    private func makeUnifiedSettingsCard() -> NSView {
        let container = AdaptiveSettingsCardView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let columns = NSView()
        columns.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(columns)

        let behaviorContent = makeBehaviorContent()
        behaviorContent.translatesAutoresizingMaskIntoConstraints = false
        columns.addSubview(behaviorContent)

        let shortcutContent = makeShortcutContent()
        shortcutContent.translatesAutoresizingMaskIntoConstraints = false
        columns.addSubview(shortcutContent)

        let divider = AdaptiveSeparatorView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            columns.topAnchor.constraint(equalTo: container.topAnchor),
            columns.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            behaviorContent.leadingAnchor.constraint(equalTo: columns.leadingAnchor),
            behaviorContent.trailingAnchor.constraint(equalTo: columns.centerXAnchor),
            behaviorContent.topAnchor.constraint(equalTo: columns.topAnchor),
            behaviorContent.bottomAnchor.constraint(equalTo: columns.bottomAnchor),
            shortcutContent.leadingAnchor.constraint(equalTo: columns.centerXAnchor),
            shortcutContent.trailingAnchor.constraint(equalTo: columns.trailingAnchor),
            shortcutContent.topAnchor.constraint(equalTo: columns.topAnchor),
            shortcutContent.bottomAnchor.constraint(equalTo: columns.bottomAnchor),
            divider.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            divider.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
            divider.widthAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    private func makeSectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
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
        appDelegate.hotKey = nil
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
        appDelegate.hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: event.modifierFlags.carbonFlags))
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
    
    private func loadHotkey() {
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
        
        
        let images = ["drop", "bag", "gamecontroller", "poweron", "chevron.forward", "battery.100", "wifi", "magnifyingglass", "switch.2"].map { symbolName in
            NSImageView(image: Assets.systemSymbol(named: symbolName)!)
        }
        
        
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
        statusBarStackView.addArrangedSubview(dateTimeLabel)
        NSLayoutConstraint.activate([dateTimeLabel.heightAnchor.constraint(equalToConstant: imageWidth)
        ])
       
        updateTutorialArrowConstraints(
            hiddenArrowAnchor: statusBarStackView.arrangedSubviews[3].centerXAnchor
        )
    }

    private func updateTutorialArrowConstraints(
        hiddenArrowAnchor: NSLayoutXAxisAnchor
    ) {
        NSLayoutConstraint.deactivate(tutorialArrowConstraints)
        NSLayoutConstraint.deactivate(tutorialStateLabelConstraints)
        tutorialArrowConstraints = [
            arrowPointToHiddenImage.centerXAnchor.constraint(equalTo: hiddenArrowAnchor)
        ]
        tutorialStateLabelConstraints = []

        if
            let hiddenLabel = tutorialHiddenLabel,
            let shownLabel = tutorialShownLabel,
            statusBarStackView.arrangedSubviews.count > 6
        {
            let hiddenIcon = statusBarStackView.arrangedSubviews[1]
            let firstShownIcon = statusBarStackView.arrangedSubviews[5]
            let secondShownIcon = statusBarStackView.arrangedSubviews[6]
            tutorialStateLabelConstraints = [
                hiddenLabel.centerXAnchor.constraint(equalTo: hiddenIcon.centerXAnchor),
                shownLabel.centerXAnchor.constraint(
                    equalTo: firstShownIcon.trailingAnchor,
                    constant: statusBarStackView.spacing / 2
                ),
                shownLabel.centerXAnchor.constraint(
                    lessThanOrEqualTo: secondShownIcon.centerXAnchor
                )
            ]
        }

        NSLayoutConstraint.activate(tutorialArrowConstraints + tutorialStateLabelConstraints)
    }
}
