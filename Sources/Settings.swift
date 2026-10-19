import AppKit
import Carbon.HIToolbox

/// User preferences, stored in UserDefaults.
enum Settings {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let switchKeyboard = "switchKeyboardAfterConvert"
        static let smartMode = "smartMode"
        static let noSelection = "noSelectionBehavior"
        static let otherLayout = "otherLayoutID"
        static let shortcutKey = "shortcutKeyCode"
        static let shortcutMods = "shortcutModifiers"
        static let onboarded = "hasCompletedSetup"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.switchKeyboard: true,
            Key.smartMode: true,
            Key.noSelection: NoSelection.wholeField.rawValue,
            Key.shortcutKey: Int(kVK_ANSI_Period),
            Key.shortcutMods: Int(cmdKey),
        ])
    }

    /// Switch the active keyboard to the converted language afterwards.
    static var switchKeyboard: Bool {
        get { defaults.bool(forKey: Key.switchKeyboard) }
        set { defaults.set(newValue, forKey: Key.switchKeyboard) }
    }

    /// Convert mixed text word by word instead of all at once.
    static var smartMode: Bool {
        get { defaults.bool(forKey: Key.smartMode) }
        set { defaults.set(newValue, forKey: Key.smartMode) }
    }

    /// What to convert when nothing is selected.
    enum NoSelection: String {
        case wholeField, currentLine
    }

    static var noSelection: NoSelection {
        get { NoSelection(rawValue: defaults.string(forKey: Key.noSelection) ?? "") ?? .wholeField }
        set { defaults.set(newValue.rawValue, forKey: Key.noSelection) }
    }

    /// Input source ID of the second-language layout; nil picks automatically.
    static var otherLayoutID: String? {
        get { defaults.string(forKey: Key.otherLayout) }
        set { defaults.set(newValue, forKey: Key.otherLayout) }
    }

    static var shortcut: Shortcut {
        get {
            Shortcut(keyCode: UInt32(defaults.integer(forKey: Key.shortcutKey)),
                     modifiers: UInt32(defaults.integer(forKey: Key.shortcutMods)))
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.shortcutKey)
            defaults.set(Int(newValue.modifiers), forKey: Key.shortcutMods)
        }
    }

    static var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }
}

/// A global shortcut: a key code plus Carbon modifier flags.
struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var m: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        modifiers = m
    }

    /// A usable global shortcut needs ⌘, ⌥ or ⌃ — otherwise it would
    /// swallow normal typing.
    var isValid: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey) != 0  { f.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0   { f.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0     { f.insert(.command) }
        return f
    }

    /// The key alone, for menu key equivalents ("." or " "), if it has one.
    var keyEquivalent: String? {
        switch Int(keyCode) {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        default:
            if let f = Shortcut.functionKeys[Int(keyCode)] {
                return String(Character(UnicodeScalar(NSF1FunctionKey + f)!))
            }
            return InputSources.englishLabel(for: UInt16(keyCode))?.lowercased()
        }
    }

    /// Human-readable form, e.g. "⌃⇧Space" or "⌘.".
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0  { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0   { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0     { s += "⌘" }
        return s + keyName
    }

    private var keyName: String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let f = Shortcut.functionKeys[Int(keyCode)] { return "F\(f + 1)" }
            return InputSources.englishLabel(for: UInt16(keyCode)) ?? "Key \(keyCode)"
        }
    }

    /// Key code -> zero-based function key number.
    private static let functionKeys: [Int: Int] = [
        kVK_F1: 0, kVK_F2: 1, kVK_F3: 2, kVK_F4: 3, kVK_F5: 4, kVK_F6: 5,
        kVK_F7: 6, kVK_F8: 7, kVK_F9: 8, kVK_F10: 9, kVK_F11: 10, kVK_F12: 11,
        kVK_F13: 12, kVK_F14: 13, kVK_F15: 14, kVK_F16: 15, kVK_F17: 16,
        kVK_F18: 17, kVK_F19: 18, kVK_F20: 19,
    ]
}
