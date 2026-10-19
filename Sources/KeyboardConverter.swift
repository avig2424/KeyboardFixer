import Foundation

/// Converts text typed in the wrong keyboard layout, by physical key position,
/// between an English layout and one other layout (Hebrew, Russian, Arabic…).
///
/// The tables are not hand-written: `LayoutPair.init(keys:otherLanguage:)`
/// builds them from what each physical key types on the two layouts, which the
/// app reads from the user's own enabled keyboards (see `InputSources`).
struct LayoutPair {

    /// What one physical key types on each layout.
    struct Key {
        let english: String
        let other: String
        let shifted: Bool
    }

    /// English character -> what the same key types on the other layout.
    private(set) var toOther: [Character: Character] = [:]
    /// Other-layout character -> what the same key types in English.
    private(set) var toEnglish: [Character: Character] = [:]
    /// Unicode scalars of letters only the other layout types; their presence
    /// marks text as typed in the other layout.
    private(set) var otherScalars: Set<UInt32> = []
    /// Spell-check language code of the other layout ("he", "ru"…).
    let otherLanguage: String

    init(keys: [Key], otherLanguage: String) {
        self.otherLanguage = otherLanguage

        let unshiftedOther = Dictionary(
            keys.filter { !$0.shifted }.map { ($0.english.lowercased(), $0.other) },
            uniquingKeysWith: { first, _ in first })

        // Unshifted keys first, so plain letters win when a character is
        // typed by more than one key (e.g. ש by both a and Shift-a).
        for key in keys.sorted(by: { !$0.shifted && $1.shifted }) {
            guard key.english != key.other,
                  key.english.count == 1, key.other.count == 1 else { continue }
            let e = Character(key.english)
            var o = Character(key.other)

            // Shifted letters: Russian types the capital (Ф), which we keep;
            // Hebrew types the same letter or a pointed/odd form (שׁ, „), which
            // we treat as the plain letter.
            if key.shifted, e.isLetter, let plain = unshiftedOther[key.english.lowercased()],
               plain.count == 1, key.other != plain, key.other.lowercased() != plain {
                if toEnglish[o] == nil { toEnglish[o] = Character(key.english.lowercased()) }
                o = Character(plain)
            }

            if toOther[e] == nil { toOther[e] = o }
            if toEnglish[o] == nil { toEnglish[o] = e }
            if !o.isASCII, o.isLetter || o.unicodeScalars.contains(where: { $0.properties.isAlphabetic }) {
                otherScalars.formUnion(o.unicodeScalars.map(\.value))
            }
        }

        // Apps with smart quotes turn ' and " into curly quotes. Map those to
        // the same keys. Hebrew's W key types a geresh (׳) or a plain '
        // depending on the layout; accept both.
        for (curly, straight) in [("\u{2018}", "'"), ("\u{2019}", "'"),
                                  ("\u{201C}", "\""), ("\u{201D}", "\"")] {
            let c = Character(curly), s = Character(straight)
            if toOther[c] == nil, let o = toOther[s] { toOther[c] = o }
        }
        for group in [["'", "\u{05F3}", "\u{2018}", "\u{2019}"],
                      ["\"", "\u{05F4}", "\u{201C}", "\u{201D}"]] {
            let chars = group.map { Character($0) }
            guard let english = chars.compactMap({ toEnglish[$0] }).first else { continue }
            for c in chars where toEnglish[c] == nil { toEnglish[c] = english }
        }
    }

    /// True if the text contains letters only the other layout types.
    func containsOther(_ s: String) -> Bool {
        s.unicodeScalars.contains { otherScalars.contains($0.value) }
    }

    /// Convert in whichever direction makes sense based on the detected script.
    func convert(_ input: String) -> String {
        let toEnglishDirection = containsOther(input)
        let table = toEnglishDirection ? toEnglish : toOther
        var out = ""
        out.reserveCapacity(input.count)

        for ch in input {
            if let mapped = table[ch] {
                out.append(mapped)
            } else if !toEnglishDirection, let mapped = table[Character(ch.lowercased())] {
                // Capitals with no shifted mapping share the lowercase key.
                out.append(mapped)
            } else {
                // Digits, spaces, untouched punctuation: pass through.
                out.append(ch)
            }
        }
        return out
    }

    enum Language { case english, other }

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
    func smartConvert(_ input: String,
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

        for (n, i) in words.enumerated() where shouldConvert[n] {
            tokens[i].text = convert(tokens[i].text)
        }
        return tokens.map(\.text).joined()

        func classify(_ word: String) -> Kind {
            guard word.contains(where: \.isLetter) else { return .noLetters }
            let lang: Language = containsOther(word) ? .other : .english
            let otherLang: Language = lang == .other ? .english : .other
            // As typed, only strip punctuation that stays punctuation after
            // conversion: in "ים'" the ' is the W key, part of the word.
            let core = trim(word) { !$0.isLetter && !convert(String($0)).contains(where: \.isLetter) }
            let converted = trim(convert(word)) { !$0.isLetter }
            // Trailing punctuation often converts into a letter ("akuo." ->
            // "שלוםץ"), so also check the conversion of the letters alone.
            let lettersOnly = trim(convert(trim(word) { !$0.isLetter })) { !$0.isLetter }

            let validAsTyped = !core.isEmpty && isWord(core, lang)
            let validConverted = (!converted.isEmpty && isWord(converted, otherLang)) ||
                                 (!lettersOnly.isEmpty && isWord(lettersOnly, otherLang))
            switch (validAsTyped, validConverted) {
            case (true, false): return .keep
            case (false, true): return .convert
            case (true, true):  return .both
            default:            return .neither
            }
        }

        func trim(_ s: String, _ strip: (Character) -> Bool) -> String {
            String(s.drop(while: strip).reversed().drop(while: strip).reversed())
        }
    }
}
