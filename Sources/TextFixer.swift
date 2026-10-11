import AppKit
import Carbon.HIToolbox

/// Drives the select → copy → convert → paste → restore-clipboard flow.
enum TextFixer {

    private static let pasteboard = NSPasteboard.general

    /// UserDefaults key: switch the active keyboard to the converted
    /// language after pasting.
    static let switchKeyboardKey = "switchKeyboardAfterConvert"

    /// Run the conversion against the current selection, or the whole field
    /// if nothing is selected.
    static func fixSelectedText() {
        guard ensureAccessibility() else { return }

        // 1. Snapshot the clipboard so we can restore it later.
        let savedItems = snapshotPasteboard()

        // 2. Copy whatever is selected. ⌘C is the authoritative test for a
        //    selection: with nothing selected, Copy is a no-op and the
        //    pasteboard stays empty. This is reliable in every app — including
        //    WebKit-based editors like Apple Mail, where the Accessibility
        //    "selected text" attribute is missing and an AX probe would wrongly
        //    report "no selection" and select the entire document.
        if !copySelection(timeout: 0.5) {
            // 3. Nothing was selected — select the whole field, then copy that.
            postCmdKey(.a)
            usleep(40_000)
            guard copySelection(timeout: 0.5) else {
                restorePasteboard(savedItems)
                return
            }
        }

        guard let copied = pasteboard.string(forType: .string), !copied.isEmpty else {
            restorePasteboard(savedItems)
            return
        }

        // 4. Convert, using the Hebrew layout the user actually has enabled.
        KeyboardConverter.layout = InputSources.hebrewLayout()
        let converted = KeyboardConverter.smartConvert(copied, isWord: isWord)
        guard converted != copied else {
            restorePasteboard(savedItems)
            return
        }

        // 5. Place the converted text on the pasteboard and paste.
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        let prePasteCount = pasteboard.changeCount
        postCmdKey(.v)

        // 6. Wait for the paste to consume the clipboard, then restore the original.
        _ = waitForPasteboardChange(from: prePasteCount, timeout: 0.4)
        // A small extra delay so the receiving app finishes reading before we overwrite.
        usleep(80_000)
        restorePasteboard(savedItems)

        // 7. Keep typing in the language the text now ends in (with mixed
        //    text, the last word is where the cursor is).
        if UserDefaults.standard.bool(forKey: switchKeyboardKey),
           let lastLetter = converted.last(where: { $0.isLetter }) {
            InputSources.select(hebrew: KeyboardConverter.containsHebrew(String(lastLetter)))
        }
    }

    /// Dictionary lookup for smart conversion, via the system spell checker.
    private static func isWord(_ word: String, _ language: KeyboardConverter.Language) -> Bool {
        let checker = NSSpellChecker.shared
        let code = language == .hebrew ? "he" : "en"
        guard checker.availableLanguages.contains(code) else { return false }
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: code,
                                         wrap: false, inSpellDocumentWithTag: 0,
                                         wordCount: nil)
        return miss.location == NSNotFound
    }

    // MARK: - Selection copy

    /// Clear the pasteboard, send ⌘C, and report whether non-empty text landed
    /// on it within `timeout`. A `false` result means nothing was selected.
    private static func copySelection(timeout: TimeInterval) -> Bool {
        pasteboard.clearContents()
        let before = pasteboard.changeCount
        postCmdKey(.c)
        guard waitForPasteboardChange(from: before, timeout: timeout) else { return false }
        guard let s = pasteboard.string(forType: .string), !s.isEmpty else { return false }
        return true
    }

    // MARK: - Accessibility

    @discardableResult
    static func ensureAccessibility(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: CFDictionary = [key: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            DispatchQueue.main.async { showAccessibilityAlert() }
        }
        return trusted
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = """
            KeyboardFixer needs Accessibility access to read selected text and \
            send keystrokes. Open System Settings → Privacy & Security → \
            Accessibility, then enable KeyboardFixer.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Pasteboard helpers

    private struct PBItem {
        let strings: [(NSPasteboard.PasteboardType, String)]
        let datas:   [(NSPasteboard.PasteboardType, Data)]
    }

    private static func snapshotPasteboard() -> [PBItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var strings: [(NSPasteboard.PasteboardType, String)] = []
            var datas: [(NSPasteboard.PasteboardType, Data)] = []
            for t in item.types {
                if let s = item.string(forType: t) {
                    strings.append((t, s))
                } else if let d = item.data(forType: t) {
                    datas.append((t, d))
                }
            }
            return PBItem(strings: strings, datas: datas)
        }
    }

    private static func restorePasteboard(_ snapshot: [PBItem]) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { snap in
            let item = NSPasteboardItem()
            for (t, s) in snap.strings { item.setString(s, forType: t) }
            for (t, d) in snap.datas   { item.setData(d, forType: t) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func waitForPasteboardChange(from oldCount: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != oldCount { return true }
            usleep(10_000)
        }
        return false
    }

    // MARK: - Keystroke synthesis

    private enum CmdKey {
        case a, c, v
        var code: CGKeyCode {
            switch self {
            case .a: return CGKeyCode(kVK_ANSI_A)
            case .c: return CGKeyCode(kVK_ANSI_C)
            case .v: return CGKeyCode(kVK_ANSI_V)
            }
        }
    }

    private static func postCmdKey(_ key: CmdKey) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key.code, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: key.code, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
