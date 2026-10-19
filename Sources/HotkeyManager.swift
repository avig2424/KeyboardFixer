import AppKit
import Carbon.HIToolbox

/// Registers the global convert shortcut via the Carbon Hot Key API.
/// (CGEvent taps are available too, but RegisterEventHotKey is the
/// least invasive approach — no event-tap permission needed, and it
/// piggy-backs on the Accessibility grant we already require.)
final class HotkeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onFire() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    /// Register `shortcut`, replacing any previous one. Returns false if
    /// macOS refused it.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4B464958 /* 'KFIX' */), id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    /// Release the shortcut (e.g. while recording a new one).
    func unregister() {
        if let h = hotKeyRef { UnregisterEventHotKey(h) }
        hotKeyRef = nil
    }

    deinit {
        unregister()
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
