import Foundation

/// Standard Israeli Hebrew keyboard (Apple "Hebrew" layout) mapped to US QWERTY
/// positions. The table below was generated from the actual macOS layouts via
/// `UCKeyTranslate` (see tools/dump_layout.swift) so every key — letters,
/// punctuation, brackets, and shifted symbols — matches what you really type.
enum KeyboardConverter {

    /// US character -> the character the same physical key produces on the
    /// Apple Hebrew layout. Keyed by the *exact* US character, so shifted
    /// symbols (e.g. "(" or "&") map correctly. Uppercase letters are handled
    /// by case-folding in `convert(_:)`, not stored here.
    static let englishToHebrew: [Character: Character] = [
        // Top letter row
        "q": "/", "w": "\u{05F3}", "e": "ק", "r": "ר", "t": "א",
        "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        // Home row
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע",
        "h": "י", "j": "ח", "k": "ל", "l": "ך", ";": "ף",
        "'": ",",
        // Bottom row
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ",
        "n": "מ", "m": "צ", ",": "ת", ".": "ץ", "/": ".",
        // Brackets / backslash / backtick (base keys)
        "[": "]", "]": "[", "\\": "\u{05BF}", "`": ";",
        // Shifted symbols that differ between the two layouts
        "(": ")", ")": "(", "{": "}", "}": "{",
        "<": ">", ">": "<", "&": "\u{20AA}", "\"": "\u{05F4}",
    ]

    static let hebrewToEnglish: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (k, v) in englishToHebrew { m[v] = k }
        // The Apple "Hebrew" layout emits a geresh (U+05F3) for the w key
        // and a gershayim (U+05F4) for the " key. Some apps additionally
        // auto-correct ' into a curly U+2019. Map them all back to w / ".
        m["\u{05F3}"] = "w"   // ׳ HEBREW PUNCTUATION GERESH
        m["\u{2019}"] = "w"   // ’ RIGHT SINGLE QUOTATION MARK
        m["\u{05F4}"] = "\""  // ״ HEBREW PUNCTUATION GERSHAYIM
        m["\u{201D}"] = "\""  // ” RIGHT DOUBLE QUOTATION MARK
        return m
    }()

    /// True if the string contains any Hebrew code points (U+0590–U+05FF).
    static func containsHebrew(_ s: String) -> Bool {
        for scalar in s.unicodeScalars where (0x0590...0x05FF).contains(scalar.value) {
            return true
        }
        return false
    }

    /// Convert in whichever direction makes sense based on detected script.
    static func convert(_ input: String) -> String {
        let useHebrewToEnglish = containsHebrew(input)
        let table = useHebrewToEnglish ? hebrewToEnglish : englishToHebrew
        var out = String.UnicodeScalarView()
        out.reserveCapacity(input.unicodeScalars.count)

        for ch in input {
            // Try the character exactly as typed first — this is what makes
            // shifted symbols ( ) & " < > etc. map correctly.
            if let mapped = table[ch] {
                out.append(contentsOf: String(mapped).unicodeScalars)
                continue
            }
            // English -> Hebrew: capital letters share a physical key with
            // their lowercase form, so fall back to the lowercased character.
            if !useHebrewToEnglish {
                let lower = Character(ch.lowercased())
                if lower != ch, let mapped = table[lower] {
                    out.append(contentsOf: String(mapped).unicodeScalars)
                    continue
                }
            }
            // No mapping (digits, spaces, untouched punctuation): pass through.
            out.append(contentsOf: String(ch).unicodeScalars)
        }
        return String(String.UnicodeScalarView(out))
    }
}
