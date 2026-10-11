# KeyboardFixer

A tiny native macOS menu-bar app that fixes text typed in the wrong keyboard
language — converts between **Hebrew** and **English** using the standard
Israeli QWERTY layout.

Hit **⌘.** anywhere, and the text in the focused field is rewritten in the
other layout. The clipboard you had before is restored automatically.

---

## Behavior

When you press **⌘.** (or pick *Convert selected text* from the menu):

1. If you already have a selection, it's used as-is.
   Otherwise the app sends **⌘A** to select the whole field.
2. The selection is copied via **⌘C**.
3. The text is converted word by word. Using the macOS spell checker (English
   and Hebrew), each word is kept if it's already a real word, or converted if
   its conversion is — so `שלום nv bang` becomes `שלום מה נשמע`. When nothing
   is clearly mixed (e.g. a single word), everything is converted.
   The mapping follows the Hebrew layout you have enabled (**Hebrew** or
   **Hebrew-PC** — they differ on the W key: `׳` vs `'`).
4. The result is pasted via **⌘V**.
5. The clipboard is restored to whatever it held before, so the converted
   text never lingers there.
6. The active keyboard switches to the language the text now ends in, so you
   can keep typing (toggle *Switch keyboard after converting* in the menu).

## Requirements

- macOS **12.0 or later** (Launch-at-login requires macOS 13+)
- Xcode command-line tools (`xcode-select --install`) — only `swiftc` is used,
  no Xcode project required.

## Build

```bash
./build.sh
open build/KeyboardFixer.app
```

The script compiles `Sources/*.swift` straight into an `.app` bundle at
`build/KeyboardFixer.app`. No external dependencies.

> If you're on an Intel Mac, edit `build.sh` and change
> `-target arm64-apple-macos12` to `-target x86_64-apple-macos12`
> (or drop the `-target` flag entirely to build for the host arch).

## Grant Accessibility permission

The app needs Accessibility access to read the focused text field and to
synthesize ⌘A / ⌘C / ⌘V keystrokes.

1. Launch `KeyboardFixer.app` once. You'll see a prompt — click
   **Open System Settings**.
2. Go to **System Settings → Privacy & Security → Accessibility**.
3. Toggle **KeyboardFixer** on. (If it's not listed yet, click **+** and
   pick `build/KeyboardFixer.app`.)
4. Quit and relaunch the app so the new permission takes effect.

You can re-trigger the prompt at any time by picking
*Convert selected text* from the menu when permission is missing.

## Menu

- **Convert selected text** — same as pressing ⌘..
- **Launch at login** — toggles the `SMAppService` login item (macOS 13+).
- **Quit KeyboardFixer**.

## Layout mapping

Every physical key is mapped to whatever the *other* layout produces at that
same position — not just the letters. The table is generated from the actual
macOS layouts (`tools/dump_layout.swift` via `UCKeyTranslate`), so it matches
exactly what you type.

Letters and base punctuation (Apple "Hebrew" layout over US QWERTY):

```
q→/  w→׳  e→ק  r→ר  t→א  y→ט  u→ו  i→ן  o→ם  p→פ  [→]  ]→[
a→ש  s→ד  d→ג  f→כ  g→ע  h→י  j→ח  k→ל  l→ך  ;→ף  '→,
z→ז  x→ס  c→ב  v→ה  b→נ  n→מ  m→צ  ,→ת  .→ץ  /→.  `→;  \→ֿ
```

Shifted keys that differ between the layouts:

```
(→)   )→(   {→}   }→{   <→>   >→<   &→₪ (shekel)   "→״ (gershayim)
```

Notes:
- The reverse (Hebrew → English) mapping is generated automatically, plus
  fix-ups for the geresh (U+05F3), gershayim (U+05F4), and the curly quotes
  some apps auto-substitute.
- Shift+letter on the Hebrew layout produces pointed (niqqud) forms such as
  `שׁ`/`לֹ`; these are intentionally **not** mapped — a capital letter typed by
  mistake is converted as its plain Hebrew letter.
- Digits, spaces, and any key identical in both layouts pass through unchanged.

## File layout

```
Sources/
  main.swift              # NSApplication entry point
  AppDelegate.swift       # Status item, menu, launch-at-login
  HotkeyManager.swift     # ⌘. global hotkey via RegisterEventHotKey
  TextFixer.swift         # Copy → convert → paste → restore clipboard
  KeyboardConverter.swift # Hebrew ↔ English mapping
Info.plist                # LSUIElement + NSAccessibilityUsageDescription
build.sh                  # swiftc → .app bundle
tools/
  dump_layout.swift       # one-off: regenerate the mapping from macOS layouts
```

## Notes

- The hotkey is registered through Carbon's `RegisterEventHotKey`, which is
  the simplest API for a global shortcut and avoids needing a CGEvent tap
  (which would require Input Monitoring on top of Accessibility).
- ⌘C/⌘V are posted via `CGEvent` with `.maskCommand`.
- Clipboard restore preserves every type on every item — text, RTF, images,
  files, etc.
