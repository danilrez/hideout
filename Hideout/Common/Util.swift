import AppKit
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemServing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class SystemLoginItem: LoginItemServing {
    static let shared = SystemLoginItem()

    private init() {}

    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
enum AutoStart {
    @discardableResult
    static func apply(enabled: Bool, service: any LoginItemServing = SystemLoginItem.shared) -> Bool {
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            return false
        }

        return enabled ? service.status == .enabled : service.status == .notRegistered
    }
}

@MainActor
class Util {

    @discardableResult
    static func setUpAutoStart(isAutoStart: Bool) -> Bool {
        // SMAppService registers the main app itself as a login item;
        // no helper app, no distributed-notification kill dance.
        let succeeded = AutoStart.apply(enabled: isAutoStart)
        if !succeeded {
            NSLog("AutoStart: \(isAutoStart ? "register" : "unregister") did not reach the requested state")
        }
        NSLog("AutoStart: SMAppService.mainApp.status = \(SMAppService.mainApp.status.rawValue)")
        return succeeded
    }

    static func showPrefWindow() {
        guard let prefWindow = PreferencesWindowController.shared.window else { return }
        prefWindow.bringToFront()

        // Order the window first; AppKit may restore its frame while bringing it
        // on screen, so centering before this point can be overwritten.
        guard let screen = prefWindow.screen ?? NSScreen.main else { return }
        prefWindow.setFrameOrigin(
            WindowPlacement.centeredOrigin(
                for: prefWindow.frame,
                in: screen.visibleFrame
            )
        )
    }

    static func showAboutWindow() {
        let controller = AboutWindowController.shared
        controller.showWindow(nil)
        guard let aboutWindow = controller.window else { return }

        aboutWindow.bringToFront()
        guard let screen = aboutWindow.screen ?? NSScreen.main else { return }
        aboutWindow.setFrameOrigin(
            WindowPlacement.centeredOrigin(
                for: aboutWindow.frame,
                in: screen.visibleFrame
            )
        )
    }

}
