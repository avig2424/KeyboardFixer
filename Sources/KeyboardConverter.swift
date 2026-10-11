import Foundation

/// Hebrew <-> US QWERTY conversion by physical key position. The tables below
/// were generated from the actual macOS layouts via `UCKeyTranslate` (see
/// tools/dump_layout.swift) so every key — letters, punctuation, brackets, and
/// shifted symbols — matches what you really type.
enum KeyboardConverter {

    /// The macOS Hebrew layouts we know how to map. They share the letters
    /// but differ on a few punctuation keys (most notably W).
    enum HebrewLayout {
        case apple   // com.apple.keylayout.Hebrew
        case pc      // com.apple.keylayout.Hebrew-PC
    }

    /// Which Hebrew layout the user types with. Set before each conversion
    /// from the enabled input sources (see `InputSources`).
    static var layout: HebrewLayout = .apple

    /// Keys that produce the same thing on both Hebrew layouts. Keyed by the
    /// *exact* US character, so shifted symbols (e.g. "(") map correctly.
    /// Uppercase letters are handled by case-folding in `convert(_:)`.
    private static let common: [Character: Character] = [
        // Top letter row (w differs per layout)
        "q": "/", "e": "ק", "r": "ר", "t": "א",
        "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        // Home row
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע",
        "h": "י", "j": "ח", "k": "ל", "l": "ך", ";": "ף",
        "'": ",",
        // Bottom row
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ",
        "n": "מ", "m": "צ", ",": "ת", ".": "ץ", "/": ".",
        // Brackets (swapped on Hebrew layouts)
        "[": "]", "]": "[",
        "(": ")", ")": "(", "{": "}", "}": "{",
        "<": ">", ">": "<",
    ]

    /// Apple "Hebrew": W gives a geresh, plus a few extra symbols.
    private static let appleExtras: [Character: Character] = [
        "w": "\u{05F3}",   // ׳ HEBREW PUNCTUATION GERESH
        "\\": "\u{05BF}",  // ֿ HEBREW POINT RAFE
        "`": ";",
        "&": "\u{20AA}",   // ₪ NEW SHEQEL SIGN
        "\"": "\u{05F4}",  // ״ HEBREW PUNCTUATION GERSHAYIM
    ]

    /// "Hebrew-PC": W gives a plain apostrophe; the ` and § keys differ.
    private static let pcExtras: [Character: Character] = [
        "w": "'",
        "`": "\\", "~": "|",
        "§": ";", "±": "~",
    ]

    private static let appleEnToHe = common.merging(appleExtras) { $1 }
    private static let pcEnToHe    = common.merging(pcExtras) { $1 }
    private static let appleHeToEn = reversed(appleEnToHe)
    private static let pcHeToEn    = reversed(pcEnToHe)

    private static func reversed(_ table: [Character: Character]) -> [Character: Character] {
        var m: [Character: Character] = [:]
        for (k, v) in table { m[v] = k }
        // The W key's output varies by layout and app: a geresh (Apple
        // layout), a plain ' (PC layout), or a curly ‘ ’ when the app applies
        // smart quotes. Map them all back to w; likewise ״ / curly quotes to ".
        // None of these can come from another key, so this is safe for both.
        m["\u{05F3}"] = "w"   // ׳ HEBREW PUNCTUATION GERESH
        m["'"]        = "w"
        m["\u{2018}"] = "w"   // ‘ LEFT SINGLE QUOTATION MARK
        m["\u{2019}"] = "w"   // ’ RIGHT SINGLE QUOTATION MARK
        m["\u{05F4}"] = "\""  // ״ HEBREW PUNCTUATION GERSHAYIM
        m["\u{201C}"] = "\""  // “ LEFT DOUBLE QUOTATION MARK
        m["\u{201D}"] = "\""  // ” RIGHT DOUBLE QUOTATION MARK
        m["\u{20AA}"] = "&"   // ₪ — typed via Shift-7 on the Apple layout
        return m
    }

    /// US character -> the character the same physical key produces on the
    /// current Hebrew layout.
    static var englishToHebrew: [Character: Character] {
        layout == .pc ? pcEnToHe : appleEnToHe
    }

    static var hebrewToEnglish: [Character: Character] {
        layout == .pc ? pcHeToEn : appleHeToEn
    }

    enum Language { case hebrew, english }

    /// Word-by-word conversion for mixed text. Each word is classified:
    ///  - keep:      a real word as typed only,
    ///  - convert:   a real word only after conversion,
    ///  - both:      a real word either way (short words like "to" / "אם"),
    ///  - neither:   not a real word either way (names, typos, slang),
    ///  - no letters (numbers, lone punctuation): always left as typed.
    /// "both" words stay as typed, unless they sit between converted words or
    /// trail after one (you kept typing in the wrong layout up to the cursor).
    /// "neither" words follow their neighbours.
    ///
    /// `isWord` is the dictionary lookup (the system spell checker in the app).
    /// When nothing is clearly in the wrong layout, or nothing is clearly
    /// right, this falls back to converting everything, since the user asked
    /// for a conversion.
    static func smartConvert(_ input: String,
                             isWord: (String, Language) -> Bool) -> String {
        enum Kind { case keep, convert, both, neither, noLetters }

        // Split into alternating word / whitespace runs, keeping the
        // whitespace exactly as it was.
        var tokens: [(text: String, isSpace: Bool)] = []
        for ch in input {
            let space = ch.isWhitespace
            if let last = tokens.last, last.isSpace == space {
                tokens[tokens.count - 1].text.append(ch)
            } else {
                tokens.append((String(ch), space))
            }
        }

        let words = tokens.indices.filter { !tokens[$0].isSpace }
        let kinds = words.map { classify(tokens[$0].text) }
        guard kinds.contains(.convert), kinds.contains(.keep) else { return convert(input) }

        // Resolve "both" / "neither" from the nearest decided word on each side.
        let decided = kinds.indices.filter { kinds[$0] == .keep || kinds[$0] == .convert }
        var shouldConvert = kinds.map { $0 == .convert }
        for i in kinds.indices where kinds[i] == .both || kinds[i] == .neither {
            let left  = decided.last(where: { $0 < i }).map { kinds[$0] }
            let right = decided.first(where: { $0 > i }).map { kinds[$0] }
            if kinds[i] == .both {
                shouldConvert[i] = left == .convert && (right == .convert || right == nil)
            } else {
                shouldConvert[i] = left == .convert || right == .convert
            }
        }

        var out = ""
        for (n, i) in words.enumerated() { tokens[i].text = shouldConvert[n] ? convert(tokens[i].text) : tokens[i].text }
        for token in tokens { out += token.text }
        return out

        func classify(_ word: String) -> Kind {
            guard word.contains(where: \.isLetter) else { return .noLetters }
            let lang: Language = containsHebrew(word) ? .hebrew : .english
            let otherLang: Language = lang == .hebrew ? .english : .hebrew
            // As typed, only strip punctuation that stays punctuation after
            // conversion: in "ים'" the ' is the W key, part of the word.
            let core = trim(word) { !$0.isLetter && !convert(String($0)).contains(where: \.isLetter) }
            let converted = trim(convert(word)) { !$0.isLetter }
            // Trailing punctuation often converts into a letter ("akuo." ->
            // "שלוםץ"), so also check the conversion of the letters alone.
            let lettersOnly = trim(convert(trim(word) { !$0.isLetter })) { !$0.isLetter }

            let validAsTyped = valid(core, lang)
            let validConverted = valid(converted, otherLang) || valid(lettersOnly, otherLang)
            switch (validAsTyped, validConverted) {
            case (true, false): return .keep
            case (false, true): return .convert
            case (true, true):  return .both
            default:            return .neither
            }
        }

        func valid(_ word: String, _ lang: Language) -> Bool {
            // Single Hebrew letters (ו, ה, ש...) are prefixes, not words, but
            // the spell checker accepts them.
            if lang == .hebrew && word.count < 2 { return false }
            return !word.isEmpty && isWord(word, lang)
        }

        func trim(_ s: String, _ strip: (Character) -> Bool) -> String {
            String(s.drop(while: strip).reversed().drop(while: strip).reversed())
        }
    }

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
        var table = useHebrewToEnglish ? hebrewToEnglish : englishToHebrew
        if !useHebrewToEnglish {
            // Smart quotes turn the ' key into a curly quote; it's still the
            // ' key, which types a comma on Hebrew.
            table["\u{2018}"] = ","
            table["\u{2019}"] = ","
        }
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
