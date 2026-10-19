// Standalone test runner. The conversion tables are read from the real macOS
// keyboard layouts, so these tests check what the app will actually do.
//
//   ./test.sh

import Foundation

var failures = 0
var passes = 0

func expect(_ name: String, _ got: String, _ expected: String, input: String) {
    if got == expected {
        passes += 1
        print("  ok   \(name): \(input.debugDescription) -> \(got.debugDescription)")
    } else {
        failures += 1
        print("  FAIL \(name):")
        print("       input:    \(input.debugDescription)")
        print("       expected: \(expected.debugDescription)")
        print("       got:      \(got.debugDescription)")
    }
}

func layout(_ other: String) -> LayoutPair {
    guard let pair = InputSources.pair(englishID: "com.apple.keylayout.ABC",
                                       otherID: "com.apple.keylayout.\(other)") else {
        fatalError("layout \(other) not installed")
    }
    return pair
}

var pair = layout("Hebrew")
func check(_ name: String, _ input: String, _ expected: String) {
    expect(name, pair.convert(input), expected, input: input)
}

// MARK: - Apple "Hebrew"

print("\n== Hebrew: every letter key, both directions ==")
let letters: [(String, String)] = [
    ("q", "/"), ("e", "ק"), ("r", "ר"), ("t", "א"), ("y", "ט"), ("u", "ו"), ("i", "ן"),
    ("o", "ם"), ("p", "פ"), ("a", "ש"), ("s", "ד"), ("d", "ג"), ("f", "כ"), ("g", "ע"),
    ("h", "י"), ("j", "ח"), ("k", "ל"), ("l", "ך"), (";", "ף"), ("z", "ז"), ("x", "ס"),
    ("c", "ב"), ("v", "ה"), ("b", "נ"), ("n", "מ"), ("m", "צ"), (",", "ת"), (".", "ץ"),
    ("/", "."), ("'", ","),
]
for (en, he) in letters {
    check("en->he \(en)", en, he)
    // Hebrew -> English needs Hebrew context: punctuation alone reads as English.
    check("he->en \(he)", "ש" + he, "a" + en)
}

print("\n== Hebrew: punctuation and shifted keys ==")
check("w -> geresh", "w", "\u{05F3}")
check("brackets swap", "[]", "][")
check("parens swap", "(x)", ")ס(")
check("< > swap", "<>", "><")
check("& -> shekel", "&", "\u{20AA}")
check("doublequote -> gershayim", "\"", "\u{05F4}")
check("backtick -> semicolon", "`", ";")
check("capitals share the key", "Hello", "יקךךם")
check("shifted D is not „", "D", "ג")
check("digits and spaces pass through", "abc 123", "שנב 123")

print("\n== Hebrew: back to English ==")
check("how are you (geresh)", "ים\u{05F3} שרק טםו", "how are you")
check("plain ' is also w", "ים' שרק טםו", "how are you")
check("curly quote is also w", "ים\u{2019}", "how")
check("gershayim -> \"", "ש\u{05F4}ח", "a\"j")
check("shekel -> &", "ש\u{20AA}ל", "a&k")
check("hello", "יקךךם", "hello")

// MARK: - Hebrew-PC

print("\n== Hebrew-PC (W types a plain apostrophe) ==")
pair = layout("Hebrew-PC")
check("w -> '", "w", "'")
check("' key -> comma", "'", ",")
check("comma -> tav", ",", "ת")
check("how are you", "how are you", "ים' שרק טםו")
check("back to how are you", "ים' שרק טםו", "how are you")
check("tav and comma back", "ש,ת", "a',")
check("smart-quoted w back", "ים\u{2018}", "how")
check("smart-quoted ' key -> comma", "a\u{2019}b", "ש,נ")
check("backtick -> backslash", "`", "\\")
check("& unchanged", "&", "&")

// MARK: - Other languages

print("\n== Russian (generated the same way) ==")
pair = layout("Russian")
check("ghbdtn -> привет", "ghbdtn", "привет")
check("capitals stay capital", "Ghbdtn", "Привет")
check("back to English", "руддщ", "hello")
expect("language code", pair.otherLanguage, "ru", input: "Russian")

print("\n== Arabic ==")
pair = layout("Arabic")
expect("language code", pair.otherLanguage, "ar", input: "Arabic")
expect("round trip", pair.convert(pair.convert("hello")), "hello", input: "hello")

// MARK: - Smart conversion

print("\n== Smart (word-by-word) conversion ==")
pair = layout("Hebrew-PC")
// A tiny fake dictionary stands in for the system spell checker.
let dict: Set<String> = ["bang", "want", "to", "אם", "today", "שלום", "מה", "נשמע",
                         "hello", "how", "are", "you", "ים", "I", "love", "אני",
                         "שבת", "the", "price", "בלחם"]
func smart(_ name: String, _ input: String, _ expected: String) {
    expect(name, pair.smartConvert(input) { w, _ in dict.contains(w) }, expected, input: input)
}
smart("mixed: hebrew + wrong english", "שלום nv bang", "שלום מה נשמע")
smart("mixed: english + wrong hebrew", "hello שרק you", "hello are you")
smart("mixed keeps spacing", "I  love\tשבת  טםו", "I  love\tשבת  you")
smart("unknown follows majority (tie converts)", "שלום nv xyzq", "שלום מה סטז/")
smart("only real words -> convert all", "I love", "ן ךםהק")
smart("trailing punctuation", "אני love akuo.", "אני love שלוםץ")
smart("single valid word still converts", "hello", "יקךךם")
smart("real-both word trailing after converted", "שלום nv bang", "שלום מה נשמע")
smart("real-both word before a kept word stays", "I want to ckjo today", "I want to בלחם today")
smart("numbers stay as typed", "the price 50, akuo", "the price 50, שלום")
smart("all wrong layout", "nv bang", "מה נשמע")

print("\n----")
print("Passed: \(passes)   Failed: \(failures)")
exit(failures == 0 ? 0 : 1)
