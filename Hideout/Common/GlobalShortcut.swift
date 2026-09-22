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
    static let eventHotKeyID: UInt32 = 1
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

    private var eventHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        let hotKeyID = EventHotKeyID(
            signature: GlobalShortcutConstants.eventHotKeySignature,
            id: GlobalShortcutConstants.eventHotKeyID
        )
        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registeredHotKey
        )

        guard status == noErr, let registeredHotKey else {
            NSLog("GlobalShortcut: failed to register shortcut (status: %d)", status)
            return
        }

        eventHotKey = registeredHotKey
    }

    func unregister() {
        guard let eventHotKey else { return }

        let status = UnregisterEventHotKey(eventHotKey)
        if status != noErr {
            NSLog("GlobalShortcut: failed to unregister shortcut (status: %d)", status)
        }
        self.eventHotKey = nil
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
              hotKeyID.signature == GlobalShortcutConstants.eventHotKeySignature,
              hotKeyID.id == GlobalShortcutConstants.eventHotKeyID
        else {
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }

        Task { @MainActor [weak self] in
            guard let self, self.eventHotKey != nil else { return }
            self.onKeyDown?()
        }
        return noErr
    }

    isolated deinit {
        unregister()
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
