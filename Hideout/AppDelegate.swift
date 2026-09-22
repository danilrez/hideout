import AppKit

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate{
    
    var statusBarController = StatusBarController()

    lazy var globalShortcutController: GlobalShortcutController = {
        let controller = GlobalShortcutController()
        controller.onKeyDown = { [weak self] in
            self?.statusBarController.expandCollapseIfNeeded()
        }
        return controller
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupAutoStartApp()
        registerDefaultValues()
        setupGlobalShortcut()
        openPreferencesIfNeeded()
        detectLTRLang()
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
            UserDefaults.Key.numberOfSecondForAutoHide: 10.0,
            UserDefaults.Key.areSeparatorsHidden: false
         ])
    }
    
    func setupGlobalShortcut() {
        guard let globalKey = Preferences.globalKey else {return}
        globalShortcutController.register(
            keyCode: globalKey.keyCode,
            modifiers: globalKey.carbonFlags
        )
    }
    
    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases
        
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
    }
   
}
