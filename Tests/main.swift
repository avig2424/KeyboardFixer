// Standalone test runner. Compile with:
//   swiftc -o /tmp/kf_tests Sources/KeyboardConverter.swift Tests/main.swift
//   /tmp/kf_tests

import Foundation

var failures = 0
var passes = 0

func check(_ name: String, _ input: String, _ expected: String) {
    let got = KeyboardConverter.convert(input)
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

print("\n== English -> Hebrew (every key in the table) ==")
let englishKeys = "qwertyuiopasdfghjkl;zxcvbnm,./"
for ch in englishKeys {
    let s = String(ch)
    let h = KeyboardConverter.convert(s)
    let mapped = KeyboardConverter.englishToHebrew[ch].map { String($0) } ?? "?"
    if h == mapped {
        passes += 1
        print("  ok   \(s) -> \(h)")
    } else {
        failures += 1
        print("  FAIL \(s) expected \(mapped) got \(h)")
    }
}

print("\n== Hebrew -> English (every Hebrew letter in the table) ==")
for (eng, heb) in KeyboardConverter.englishToHebrew {
    // Only test entries whose Hebrew side is actually in the Hebrew Unicode
    // block — otherwise auto-detect treats them as English direction.
    guard let scalar = String(heb).unicodeScalars.first,
          (0x0590...0x05FF).contains(scalar.value) else { continue }
    let s = String(heb)
    let back = KeyboardConverter.convert(s)
    if back == String(eng) {
        passes += 1
        print("  ok   \(heb) -> \(back)")
    } else {
        failures += 1
        print("  FAIL \(heb) expected \(eng) got \(back)")
    }
}

print("\n== Geresh / gershayim ==")
check("geresh standalone",    "\u{05F3}", "w")
check("gershayim standalone", "\u{05F4}", "\"")
// Curly quotes only get mapped when surrounded by Hebrew (real-world case).
check("curly ’ in Hebrew context",
      "\u{05D9}\u{05DD}\u{2019}", "how")
check("curly ” in Hebrew context",
      "\u{05E9}\u{201D}\u{05D7}", "a\"j")

print("\n== Real phrases ==")
check("how are you (geresh)",
      "\u{05D9}\u{05DD}\u{05F3} \u{05E9}\u{05E8}\u{05E7} \u{05D8}\u{05DD}\u{05D5}",
      "how are you")
check("שלום -> akuo", "\u{05E9}\u{05DC}\u{05D5}\u{05DD}", "akuo")
check("hello typed in Hebrew",
      "\u{05D9}\u{05E7}\u{05DA}\u{05DA}\u{05DD}", "hello")
check("uppercase Hello", "Hello", KeyboardConverter.convert("hello"))
check("digits and spaces pass through",
      "abc 123 xyz", "\u{05E9}\u{05E0}\u{05D1} 123 \u{05E1}\u{05D8}\u{05D6}")

print("\n== Punctuation ==")
check("comma",  ",", "\u{05EA}")
check("period", ".", "\u{05E5}")
check("semi",   ";", "\u{05E3}")
// q, w, /, ' are intentionally not roundtrippable: both sides land in ASCII,
// so auto-detect cannot tell which direction to go for short inputs.
check("q (single char goes en->he)", "q", "/")
check("/ (single char goes en->he)", "/", ".")

print("\n== Full keyboard: extra base keys (en->he) ==")
check("apostrophe -> comma", "'", ",")           // ' key on Hebrew = comma
check("w -> geresh",         "w", "\u{05F3}")     // ׳ HEBREW PUNCTUATION GERESH
check("backtick -> semicolon", "`", ";")          // ` key on Hebrew = ;
check("[ -> ]",  "[", "]")                        // brackets are swapped
check("] -> [",  "]", "[")
check("backslash -> rafe", "\\", "\u{05BF}")      // ֿ HEBREW POINT RAFE

print("\n== Full keyboard: shifted symbols (en->he) ==")
check("( -> )", "(", ")")                          // parens swapped (shift-9/0)
check(") -> (", ")", "(")
check("{ -> }", "{", "}")
check("} -> {", "}", "{")
check("< -> >", "<", ">")
check("> -> <", ">", "<")
check("& -> shekel", "&", "\u{20AA}")             // ₪ NEW SHEQEL SIGN
check("doublequote -> gershayim", "\"", "\u{05F4}") // ״ HEBREW PUNCTUATION GERSHAYIM

print("\n== Full keyboard: reverse, in Hebrew context (he->en) ==")
// A real Hebrew-layout sentence: letters set the direction, symbols ride along.
check("shekel back to &", "\u{05E9}\u{20AA}\u{05DC}", "a&k")   // ש₪ל -> a&k
check("paren back to (",  "\u{05E9})\u{05DC}", "a(k")          // ש)ל -> a(k
check("comma back to apostrophe", "\u{05E9},\u{05DC}", "a'k")  // ש,ל -> a'k

print("\n== Hebrew-PC layout (W key types a plain apostrophe) ==")
KeyboardConverter.layout = .pc
check("PC: w -> apostrophe", "w", "'")
check("PC: apostrophe key -> comma", "'", ",")
check("PC: comma -> tav", ",", "\u{05EA}")
check("PC: how are you", "how are you",
      "\u{05D9}\u{05DD}' \u{05E9}\u{05E8}\u{05E7} \u{05D8}\u{05DD}\u{05D5}")
check("PC: back to how are you",
      "\u{05D9}\u{05DD}' \u{05E9}\u{05E8}\u{05E7} \u{05D8}\u{05DD}\u{05D5}", "how are you")
check("PC: tav and comma back", "\u{05E9},\u{05EA}", "a',")  // ש,ת -> a',
check("PC: smart-quoted w back", "\u{05D9}\u{05DD}\u{2018}", "how")
check("PC: smart-quoted ' key -> comma", "a\u{2019}b", "\u{05E9},\u{05E0}")
check("PC: backtick -> backslash", "`", "\\")
check("PC: & unchanged", "&", "&")
check("PC: \" unchanged", "\"", "\"")
KeyboardConverter.layout = .apple

print("\n== Smart (word-by-word) conversion ==")
// A tiny fake dictionary stands in for the system spell checker.
let dict: Set<String> = ["bang", "want", "to", "אם", "today", "שלום", "מה", "נשמע", "hello", "how", "are", "you", "ים", "I", "love", "אני", "שבת", "the", "price", "בלחם"]
func smart(_ name: String, _ input: String, _ expected: String) {
    let got = KeyboardConverter.smartConvert(input) { w, _ in dict.contains(w) }
    if got == expected {
        passes += 1
        print("  ok   \(name): \(input.debugDescription) -> \(got.debugDescription)")
    } else {
        failures += 1
        print("  FAIL \(name): \(input.debugDescription) expected \(expected.debugDescription) got \(got.debugDescription)")
    }
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
