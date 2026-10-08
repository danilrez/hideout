import AppKit
import Carbon

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0

        if contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if contains(.option) {
            flags |= UInt32(optionKey)
        }
        if contains(.control) {
            flags |= UInt32(controlKey)
        }
        if contains(.shift) {
            flags |= UInt32(shiftKey)
        }

        return flags
    }
}

private enum GlobalShortcutConstants {
    static let eventHotKeySignature: OSType = 0x486F7574 // "Hout"
    static let menuBarToggleEventHotKeyID: UInt32 = 1
#if HIDEOUT_DIAGNOSTICS
    static let diagnosticsEventHotKeyID: UInt32 = 2
    static let diagnosticsFallbackEventHotKeyID: UInt32 = 3
#endif
    static let eventSpec = [
        EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
    ]
}

@MainActor
final class GlobalShortcutController {
    var onKeyDown: (() -> Void)?
#if HIDEOUT_DIAGNOSTICS
    var onDiagnosticsKeyDown: (() -> Void)?
#endif

    private var eventHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
#if HIDEOUT_DIAGNOSTICS
    private var diagnosticsConfigurationMonitor: Timer?
    private var diagnosticsConfigurationEnabled = false
#endif

    init() {
        installEventHandler()
#if HIDEOUT_DIAGNOSTICS
        synchronizeDiagnosticsShortcuts()
        diagnosticsConfigurationMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronizeDiagnosticsShortcuts()
            }
        }
#endif
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        register(
            keyCode: keyCode,
            modifiers: modifiers,
            hotKeyID: GlobalShortcutConstants.menuBarToggleEventHotKeyID,
            action: "menuBarToggle"
        )
#if HIDEOUT_DIAGNOSTICS
        synchronizeDiagnosticsShortcuts()
#endif
    }

#if HIDEOUT_DIAGNOSTICS
    private func synchronizeDiagnosticsShortcuts() {
        let shouldEnable = HideoutDiagnostics.isEnabled
        guard shouldEnable != diagnosticsConfigurationEnabled else { return }

        diagnosticsConfigurationEnabled = shouldEnable
        if shouldEnable {
            registerDiagnosticsShortcuts()
            HideoutDiagnostics.record("diagnostics.configurationEnabled")
        } else {
            unregisterDiagnosticsShortcuts()
        }
    }

    private func registerDiagnosticsShortcuts() {
        let modifiers = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
        var registeredShortcuts: [String] = []

        if register(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: modifiers,
            hotKeyID: GlobalShortcutConstants.diagnosticsEventHotKeyID,
            action: "openDiagnosticsPrimary"
        ) {
            registeredShortcuts.append("⌃⌥⌘D")
        }

        if register(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: modifiers,
            hotKeyID: GlobalShortcutConstants.diagnosticsFallbackEventHotKeyID,
            action: "openDiagnosticsFallback"
        ) {
            registeredShortcuts.append("⌃⌥⌘L")
        }

        HideoutDiagnostics.record("diagnostics.shortcutsAvailable", fields: [
            "shortcuts": registeredShortcuts.joined(separator: ",")
        ])
    }

    private func unregisterDiagnosticsShortcuts() {
        unregister(hotKeyID: GlobalShortcutConstants.diagnosticsEventHotKeyID)
        unregister(hotKeyID: GlobalShortcutConstants.diagnosticsFallbackEventHotKeyID)
    }
#endif

    @discardableResult
    private func register(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyID: UInt32,
        action: String
    ) -> Bool {
        unregister(hotKeyID: hotKeyID)

        let carbonHotKeyID = EventHotKeyID(
            signature: GlobalShortcutConstants.eventHotKeySignature,
            id: hotKeyID
        )
        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            carbonHotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registeredHotKey
        )

        guard status == noErr, let registeredHotKey else {
            NSLog("GlobalShortcut: failed to register shortcut (status: %d)", status)
            HideoutDiagnostics.record("globalShortcut.registrationFailed", fields: [
                "action": action,
                "status": String(status)
            ])
            return false
        }

        eventHotKeys[hotKeyID] = registeredHotKey
        HideoutDiagnostics.record("globalShortcut.registered", fields: ["action": action])
        return true
    }

    func unregister() {
        unregister(hotKeyID: GlobalShortcutConstants.menuBarToggleEventHotKeyID)
    }

    private func unregister(hotKeyID: UInt32) {
        guard let eventHotKey = eventHotKeys.removeValue(forKey: hotKeyID) else { return }

        let status = UnregisterEventHotKey(eventHotKey)
        if status != noErr {
            NSLog("GlobalShortcut: failed to unregister shortcut (status: %d)", status)
            HideoutDiagnostics.record("globalShortcut.unregistrationFailed", fields: [
                "hotKeyID": String(hotKeyID),
                "status": String(status)
            ])
        }
    }

    private func installEventHandler() {
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalShortcutEventHandler,
            GlobalShortcutConstants.eventSpec.count,
            GlobalShortcutConstants.eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            NSLog("GlobalShortcut: failed to install event handler (status: %d)", status)
            return
        }
    }

    nonisolated fileprivate func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == GlobalShortcutConstants.eventHotKeySignature
        else {
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }

        let registeredHotKeyID = hotKeyID.id
        if registeredHotKeyID == GlobalShortcutConstants.menuBarToggleEventHotKeyID {
            Task { @MainActor [weak self] in
                guard let self, self.eventHotKeys[registeredHotKeyID] != nil else { return }
                self.onKeyDown?()
            }
            return noErr
        }

#if HIDEOUT_DIAGNOSTICS
        if registeredHotKeyID == GlobalShortcutConstants.diagnosticsEventHotKeyID
            || registeredHotKeyID == GlobalShortcutConstants.diagnosticsFallbackEventHotKeyID {
            Task { @MainActor [weak self] in
                guard let self, self.eventHotKeys[registeredHotKeyID] != nil else { return }
                self.onDiagnosticsKeyDown?()
            }
            return noErr
        }
#endif

        return OSStatus(eventNotHandledErr)
    }

    isolated deinit {
#if HIDEOUT_DIAGNOSTICS
        diagnosticsConfigurationMonitor?.invalidate()
#endif
        for eventHotKey in eventHotKeys.values {
            let status = UnregisterEventHotKey(eventHotKey)
            if status != noErr {
                NSLog("GlobalShortcut: failed to unregister shortcut (status: %d)", status)
            }
        }
        if let eventHandler {
            let status = RemoveEventHandler(eventHandler)
            if status != noErr {
                NSLog("GlobalShortcut: failed to remove event handler (status: %d)", status)
            }
        }
    }
}

private func globalShortcutEventHandler(
    eventHandlerCall: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let controller = Unmanaged<GlobalShortcutController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return controller.handleCarbonEvent(event)
}
