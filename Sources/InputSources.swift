import Carbon

/// Reads and switches the user's enabled keyboard layouts (Text Input Sources).
enum InputSources {

    private static let hebrewIDs = [
        "com.apple.keylayout.Hebrew-PC",
        "com.apple.keylayout.Hebrew",
    ]

    /// The Hebrew layout the user actually types with: the selected one if it
    /// is Hebrew, otherwise the first enabled Hebrew layout.
    static func hebrewLayout() -> KeyboardConverter.HebrewLayout {
        guard let src = hebrewSource() else { return .apple }
        return id(of: src) == "com.apple.keylayout.Hebrew-PC" ? .pc : .apple
    }

    /// Switch the active keyboard to Hebrew or to an English (ASCII) layout.
    static func select(hebrew: Bool) {
        let target = hebrew ? hebrewSource() : englishSource()
        if let target = target, id(of: target) != id(of: current()) {
            TISSelectInputSource(target)
        }
    }

    // MARK: - Lookup

    private static func current() -> TISInputSource {
        TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }

    private static func enabledLayouts() -> [TISInputSource] {
        let props = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        return TISCreateInputSourceList(props, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func hebrewSource() -> TISInputSource? {
        let cur = current()
        if hebrewIDs.contains(id(of: cur)) { return cur }
        let enabled = enabledLayouts()
        for wanted in hebrewIDs {
            if let src = enabled.first(where: { id(of: $0) == wanted }) { return src }
        }
        return nil
    }

    private static func englishSource() -> TISInputSource? {
        let cur = current()
        if isEnglish(cur) { return cur }
        return enabledLayouts().first(where: isEnglish)
    }

    private static func isEnglish(_ src: TISInputSource) -> Bool {
        let langs = property(src, kTISPropertyInputSourceLanguages) as? [String] ?? []
        let ascii = (property(src, kTISPropertyInputSourceIsASCIICapable) as? Bool) ?? false
        return ascii && langs.first == "en"
    }

    private static func id(of src: TISInputSource) -> String {
        property(src, kTISPropertyInputSourceID) as? String ?? ""
    }

    private static func property(_ src: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    }
}
