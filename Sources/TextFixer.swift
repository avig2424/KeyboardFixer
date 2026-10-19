import AppKit
import Carbon.HIToolbox

/// Drives the select → copy → convert → paste → restore-clipboard flow.
enum TextFixer {

    private static let pasteboard = NSPasteboard.general

    /// Called when Accessibility permission is missing (shows the setup window).
    static var onMissingPermission: (() -> Void)?

    /// Run the conversion against the current selection, or — if nothing is
    /// selected — the whole field or the current line (see Settings).
    static func fixSelectedText() {
        guard AXIsProcessTrusted() else {
            onMissingPermission?()
            return
        }
        // Never touch password fields: don't copy, convert, or paste secrets.
        guard !focusedElementIsSecure() else {
            NSSound.beep()
            return
        }
        guard let pair = InputSources.currentPair() else { return }

        // 1. Snapshot the clipboard so we can restore it later.
        let savedItems = snapshotPasteboard()

        // 2. Copy whatever is selected. ⌘C is the authoritative test for a
        //    selection: with nothing selected, Copy is a no-op and the
        //    pasteboard stays empty. This is reliable in every app — including
        //    WebKit-based editors like Apple Mail, where the Accessibility
        //    "selected text" attribute is missing and an AX probe would wrongly
        //    report "no selection" and select the entire document.
        if !copySelection(timeout: 0.5) {
            // 3. Nothing was selected — select the field or line, then copy that.
            guard selectWhenNothingSelected() else {
                restorePasteboard(savedItems)
                return
            }
        }

        guard let copied = pasteboard.string(forType: .string), !copied.isEmpty else {
            restorePasteboard(savedItems)
            return
        }

        // 4. Convert, using the layouts the user actually has enabled.
        let converted = Settings.smartMode
            ? pair.smartConvert(copied) { isWord($0, $1, pair) }
            : pair.convert(copied)
        guard converted != copied else {
            restorePasteboard(savedItems)
            return
        }

        // 5. Place the converted text on the pasteboard and paste.
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        let prePasteCount = pasteboard.changeCount
        postKey(kVK_ANSI_V, .maskCommand)

        // 6. Wait for the paste to consume the clipboard, then restore the original.
        _ = waitForPasteboardChange(from: prePasteCount, timeout: 0.4)
        // A small extra delay so the receiving app finishes reading before we overwrite.
        usleep(80_000)
        restorePasteboard(savedItems)

        // 7. Keep typing in the language the text now ends in (with mixed
        //    text, the last word is where the cursor is).
        if Settings.switchKeyboard, let lastLetter = converted.last(where: { $0.isLetter }) {
            InputSources.select(other: pair.containsOther(String(lastLetter)))
        }
    }

    /// Select something to convert when the user had no selection, and copy
    /// it. Returns false if nothing could be copied.
    private static func selectWhenNothingSelected() -> Bool {
        switch Settings.noSelection {
        case .wholeField:
            postKey(kVK_ANSI_A, .maskCommand)
            usleep(40_000)
            return copySelection(timeout: 0.5)
        case .currentLine:
            // ⌘⇧← selects to the line's left edge: the start of an English
            // line. In a right-to-left (Hebrew) line that edge is the end, so
            // with the cursor at the end nothing gets selected — then ⌘⇧→.
            postKey(kVK_LeftArrow, [.maskCommand, .maskShift])
            usleep(40_000)
            if copySelection(timeout: 0.3) { return true }
            postKey(kVK_RightArrow, [.maskCommand, .maskShift])
            usleep(40_000)
            return copySelection(timeout: 0.3)
        }
    }

    /// Dictionary lookup for smart conversion, via the system spell checker.
    private static func isWord(_ word: String, _ language: LayoutPair.Language,
                               _ pair: LayoutPair) -> Bool {
        let code = language == .other ? pair.otherLanguage : "en"
        // Single Hebrew letters (ו, ה, ש...) are prefixes, not words, but the
        // spell checker accepts them.
        if code == "he" && word.count < 2 { return false }
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains(code) else { return false }
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: code,
                                         wrap: false, inSpellDocumentWithTag: 0,
                                         wordCount: nil)
        return miss.location == NSNotFound
    }

    /// True if the focused text field is a password field.
    private static func focusedElementIsSecure() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXSecureTextFieldSubrole as String)
    }

    // MARK: - Selection copy

    /// Clear the pasteboard, send ⌘C, and report whether non-empty text landed
    /// on it within `timeout`. A `false` result means nothing was selected.
    private static func copySelection(timeout: TimeInterval) -> Bool {
        pasteboard.clearContents()
        let before = pasteboard.changeCount
        postKey(kVK_ANSI_C, .maskCommand)
        guard waitForPasteboardChange(from: before, timeout: timeout) else { return false }
        guard let s = pasteboard.string(forType: .string), !s.isEmpty else { return false }
        return true
    }

    // MARK: - Accessibility

    /// Ask macOS to show its own permission prompt (adds the app to the list
    /// in System Settings). Returns whether permission is already granted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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

    private static func postKey(_ code: Int, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
