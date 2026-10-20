# KeyboardFixer

A tiny native macOS menu-bar app that fixes text typed in the wrong keyboard
language. Typed `akuo` when you meant `שלום`? Select it, press **⌘.**, and it
becomes `שלום`.

Works with Hebrew out of the box, and with any other layout that can't type
English: Russian, Arabic, Greek…

## Install

1. Download **`KeyboardFixer-<version>.dmg`** from the
   [Releases page](https://github.com/avig2424/KeyboardFixer/releases).
2. Open it and drag **KeyboardFixer** into **Applications**.
3. Open KeyboardFixer from Applications. The first time, macOS blocks it
   because it isn't from an identified developer:
   - Go to **System Settings → Privacy & Security**, scroll down, and click
     **Open Anyway** next to the KeyboardFixer message. Or, in Terminal:
     `xattr -dr com.apple.quarantine /Applications/KeyboardFixer.app`
4. The setup window walks you through turning on **Accessibility** access
   and lets you try the shortcut.

Requires macOS 12 or later, on an Apple Silicon Mac (M1 or newer).

## Privacy

- **Nothing leaves your Mac.** The app has no network code at all.
- Nothing is stored except your settings.
- **Accessibility** access is used only to copy the selected text and paste
  the fixed version. Your clipboard is restored right afterwards.
- **Password fields are never touched.**

## How it works

When you press the shortcut (or pick *Convert selected text* from the menu):

1. The selected text is copied. If nothing is selected, it selects the whole
   field or the current line (your choice in Settings).
2. The text is converted by physical key position, between your English
   layout and your second-language layout. Both mappings are read from the
   keyboard layouts on your Mac, so they match exactly what you type, including
   punctuation (e.g. the W key types `'` on Hebrew – PC and `׳` on Hebrew).
3. Mixed text is fixed word by word using the macOS spell checker. Only the
   words typed in the wrong layout change, so `שלום nv bang` becomes
   `שלום מה נשמע`. If nothing is clearly mixed (e.g. a single word),
   everything is converted.
4. The result is pasted, and your clipboard is restored.
5. The keyboard switches to the language you were typing in, so you can keep
   going.

## Settings

Open **Settings…** from the **א/A** menu-bar icon:

- **Shortcut**: click and press a new combination (it must include ⌘, ⌥ or ⌃).
- **Second language**: Automatic, or pick one of your enabled layouts.
- **When nothing is selected**: convert the whole field, or only the current
  line. The current-line option uses ⌘⇧←/→ and may not work in every app.
- **Fix mixed text word by word**, **Switch keyboard after converting**,
  **Launch at login** (macOS 13+).

## Build from source

Needs the Xcode command-line tools (`xcode-select --install`). There's no
Xcode project and no dependencies.

```bash
./build.sh        # → build/KeyboardFixer.app
./test.sh         # converter tests, using the real macOS layouts
./release.sh      # → build/KeyboardFixer-<version>.dmg
```

`swift tools/make_icon.swift` regenerates `Resources/AppIcon.icns`.

`build.sh` signs with a code-signing certificate named
**KeyboardFixer Signing** if your keychain has one. Every build then has the
same identity, so macOS keeps the Accessibility permission across rebuilds and
updates. Without it, builds are signed ad-hoc and Accessibility has to be
re-granted after each rebuild.

## Files

```
Sources/
  main.swift              # NSApplication entry point
  AppDelegate.swift       # Menu-bar icon, menus, windows
  HotkeyManager.swift     # Global shortcut via RegisterEventHotKey
  TextFixer.swift         # Copy → convert → paste → restore clipboard
  KeyboardConverter.swift # Conversion tables and word-by-word conversion
  InputSources.swift      # Reads and switches the Mac's keyboard layouts
  Settings.swift          # Preferences and the Shortcut type
  SettingsWindow.swift    # Settings window
  SetupWindow.swift       # First-run setup window
  ShortcutRecorder.swift  # "Click and press a shortcut" control
Tests/main.swift          # Converter tests
tools/make_icon.swift     # Draws the app icon
```
