import AppKit

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate{
    
    var statusBarController = StatusBarController()

    lazy var globalShortcutController: GlobalShortcutController = {
        let controller = GlobalShortcutController()
        controller.onKeyDown = { [weak self] in
            self?.statusBarController.expandCollapseIfNeeded(trigger: .globalShortcut)
        }
#if HIDEOUT_DIAGNOSTICS
        controller.onDiagnosticsKeyDown = {
            HideoutDiagnostics.openDiagnosticsFolder(source: "globalShortcut")
        }
#endif
        return controller
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        detectLTRLang()
        setupAutoStartApp()
        registerDefaultValues()
        setupGlobalShortcut()
        openPreferencesIfNeeded()

#if HIDEOUT_DIAGNOSTICS
        let info = Bundle.main.infoDictionary ?? [:]
        HideoutDiagnostics.record("application.didFinishLaunching", fields: [
            "version": info["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info["CFBundleVersion"] as? String ?? "unknown",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "autoHide": String(Preferences.isAutoHide),
            "autoHideDelaySeconds": String(Preferences.numberOfSecondForAutoHide),
            "fullStatusBarOnExpand": String(Preferences.useFullStatusBarOnExpandEnabled),
            "hoverToExpand": String(Preferences.hoverToExpand),
            "preferencesWindowOnLaunch": String(Preferences.isShowPreference),
            "globalShortcutConfigured": String(Preferences.globalKey != nil),
            "screenCount": String(NSScreen.screens.count)
        ])
#endif
    }

#if HIDEOUT_DIAGNOSTICS
    func applicationWillTerminate(_ notification: Notification) {
        HideoutDiagnostics.record("application.willTerminate")
    }
#endif

    @IBAction func showAboutWindow(_ sender: Any?) {
        Util.showAboutWindow()
    }

    @IBAction func showPreferencesWindow(_ sender: Any?) {
        Util.showPrefWindow()
    }
    
    func openPreferencesIfNeeded() {
        if Preferences.isShowPreference {
            Util.showPrefWindow()
        }
    }
    
    func setupAutoStartApp() {
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
    }
    
    func registerDefaultValues() {
         UserDefaults.standard.register(defaults: [
            UserDefaults.Key.isAutoStart: false,
            UserDefaults.Key.isShowPreference: true,
            UserDefaults.Key.isAutoHide: true,
            UserDefaults.Key.numberOfSecondForAutoHide: 10.0
         ])
    }

    func setupGlobalShortcut() {
#if HIDEOUT_DIAGNOSTICS
        _ = globalShortcutController
#endif
        if let globalKey = Preferences.globalKey {
            globalShortcutController.register(
                keyCode: globalKey.keyCode,
                modifiers: globalKey.carbonFlags
            )
        }
    }
    
    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases
        
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
        statusBarController.updateGlyphPositionConstraint()
    }
   
}
