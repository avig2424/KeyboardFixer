import Carbon

/// Reads and switches the user's keyboard layouts (Text Input Sources).
///
/// "English" is an ASCII-capable English layout (ABC, U.S., British…).
/// "Other" is a layout that can't type English (Hebrew, Russian, Arabic…).
enum InputSources {

    /// A layout the user can pick as their second language.
    struct Layout {
        let id: String
        let name: String
    }

    /// The fallback second language when none is enabled.
    private static let defaultOtherID = "com.apple.keylayout.Hebrew"

    // MARK: - Conversion table

    /// The conversion table between the user's English layout and their
    /// chosen other layout, built from what each key actually types.
    static func currentPair() -> LayoutPair? {
        guard let english = englishSource(), let other = otherSource() else { return nil }
        return pair(english: english, other: other)
    }

    /// Build a table for two layouts by input source ID (used by the tests).
    static func pair(englishID: String, otherID: String) -> LayoutPair? {
        guard let english = source(id: englishID), let other = source(id: otherID) else { return nil }
        return pair(english: english, other: other)
    }

    private static func pair(english: TISInputSource, other: TISInputSource) -> LayoutPair? {
        guard let en = layoutData(english), let ot = layoutData(other) else { return nil }
        var keys: [LayoutPair.Key] = []
        // Virtual key codes 0...50 cover the letter rows, number row, and
        // punctuation (including the ISO § key, 10).
        for code in UInt16(0)...50 {
            for shifted in [false, true] {
                guard let e = type(en, code, shifted), let o = type(ot, code, shifted) else { continue }
                keys.append(.init(english: e, other: o, shifted: shifted))
            }
        }
        let language = languages(of: other).first ?? "he"
        return LayoutPair(keys: keys, otherLanguage: language)
    }

    // MARK: - Switching

    /// Switch the active keyboard to the other layout or to English.
    static func select(other: Bool) {
        let target = other ? otherSource() : englishSource()
        if let target = target, id(of: target) != id(of: current()) {
            TISSelectInputSource(target)
        }
    }

    // MARK: - Choosing layouts

    /// Enabled layouts that can serve as the second language.
    static func enabledOtherLayouts() -> [Layout] {
        enabledLayouts().filter { !isASCII($0) }.map {
            Layout(id: id(of: $0), name: property($0, kTISPropertyLocalizedName) as? String ?? id(of: $0))
        }
    }

    /// Name of the layout "Automatic" currently resolves to.
    static func automaticOtherLayoutName() -> String? {
        otherSource(chosen: nil).flatMap { property($0, kTISPropertyLocalizedName) as? String }
    }

    /// The other layout to use: the one picked in Settings if it's still
    /// enabled, else the active one, else the first enabled, else Hebrew.
    private static func otherSource(chosen: String? = Settings.otherLayoutID) -> TISInputSource? {
        let enabled = enabledLayouts().filter { !isASCII($0) }
        if let chosen = chosen,
           let src = enabled.first(where: { id(of: $0) == chosen }) { return src }
        let cur = current()
        if !isASCII(cur) && isKeyboardLayout(cur) { return cur }
        return enabled.first ?? source(id: defaultOtherID)
    }

    private static func englishSource() -> TISInputSource? {
        let cur = current()
        if isEnglish(cur) { return cur }
        return enabledLayouts().first(where: isEnglish) ?? source(id: "com.apple.keylayout.ABC")
    }

    // MARK: - TIS helpers

    private static func current() -> TISInputSource {
        TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }

    private static func enabledLayouts() -> [TISInputSource] {
        let props = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        return TISCreateInputSourceList(props, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func source(id: String) -> TISInputSource? {
        let props = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return (TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }

    private static func isEnglish(_ src: TISInputSource) -> Bool {
        isASCII(src) && languages(of: src).first == "en"
    }

    private static func isASCII(_ src: TISInputSource) -> Bool {
        (property(src, kTISPropertyInputSourceIsASCIICapable) as? Bool) ?? false
    }

    private static func isKeyboardLayout(_ src: TISInputSource) -> Bool {
        (property(src, kTISPropertyInputSourceType) as? String) == (kTISTypeKeyboardLayout as String)
    }

    private static func languages(of src: TISInputSource) -> [String] {
        property(src, kTISPropertyInputSourceLanguages) as? [String] ?? []
    }

    private static func id(of src: TISInputSource) -> String {
        property(src, kTISPropertyInputSourceID) as? String ?? ""
    }

    private static func property(_ src: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    }

    private static func layoutData(_ src: TISInputSource) -> Data? {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
    }

    /// What `code` types on a layout, with or without Shift.
    private static func type(_ layout: Data, _ code: UInt16, _ shifted: Bool) -> String? {
        layout.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let ptr = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            let modifiers: UInt32 = shifted ? UInt32((shiftKey >> 8) & 0xFF) : 0
            let status = UCKeyTranslate(ptr, code, UInt16(kUCKeyActionDown), modifiers,
                                        UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: length)
            return s.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F } ? s : nil
        }
    }

    /// Display string for a key code on the English layout ("." for the
    /// period key), used to show shortcuts.
    static func englishLabel(for code: UInt16) -> String? {
        guard let src = englishSource(), let data = layoutData(src) else { return nil }
        return type(data, code, false)?.uppercased()
    }
}
