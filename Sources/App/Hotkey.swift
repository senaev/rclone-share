import AppKit
import Carbon.HIToolbox

/// System wide shortcuts.
///
/// Carbon's `RegisterEventHotKey` is used on purpose. An `NSEvent` global
/// monitor would need Accessibility permission, which is a poor fit for an
/// ad-hoc signed app, while this route needs no permission at all.
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    /// Registers a shortcut and reports whether the system accepted it.
    ///
    /// `keyCode` is a virtual key code, so it follows the physical key and keeps
    /// working after a keyboard layout change. Registration fails when another
    /// app already owns the combination.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            Log.app.error(
                "RegisterEventHotKey(keyCode: \(keyCode), modifiers: \(modifiers))"
                + " failed with status \(status)"
            )
            return false
        }

        actions[id] = action
        references[id] = reference
        Log.app.info("Registered hotkey id \(id), keyCode \(keyCode), modifiers \(modifiers)")
        return true
    }

    fileprivate func fire(_ id: UInt32) {
        Log.app.info("Hotkey \(id) pressed")
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &spec,
            nil,
            &handler
        )

        if status == noErr {
            Log.app.info("Installed the hotkey event handler")
        } else {
            Log.app.error("InstallEventHandler failed with status \(status)")
        }
    }

    /// Four character code 'RCSH'.
    private static let signature: OSType = 0x5243_5348
}

/// A free function, because a Carbon callback must be a plain C function
/// pointer and cannot capture context.
private func hotkeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }

    DispatchQueue.main.async {
        HotkeyCenter.shared.fire(id.id)
    }
    return noErr
}

extension HotkeyCenter {
    /// Command + Shift + apostrophe, the shortcut that opens the gist form.
    static let gistKeyCode = UInt32(kVK_ANSI_Quote)
    static let gistModifiers = UInt32(cmdKey | shiftKey)
}
