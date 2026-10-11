import AppKit
import Carbon.HIToolbox

/// Registers a global ⌘. hotkey via the Carbon Hot Key API.
/// (CGEvent taps are available too, but RegisterEventHotKey is the
/// least invasive approach — no event-tap permission needed, and it
/// piggy-backs on the Accessibility grant we already require.)
final class HotkeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onFire() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4B464958 /* 'KFIX' */),
                               id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_Period),
                            UInt32(cmdKey),
                            id,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    deinit {
        if let h = hotKeyRef { UnregisterEventHotKey(h) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
