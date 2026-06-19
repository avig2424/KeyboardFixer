import AppKit
import Carbon.HIToolbox

/// Drives the select → copy → convert → paste → restore-clipboard flow.
enum TextFixer {

    private static let pasteboard = NSPasteboard.general

    /// Run the conversion against the currently focused text field.
    static func fixSelectedText() {
        guard ensureAccessibility() else { return }

        // 1. Snapshot the clipboard so we can restore it later.
        let savedItems = snapshotPasteboard()

        // 2. If the focused field reports no selection, send ⌘A first.
        if !focusedFieldHasSelection() {
            postCmdKey(.a)
            usleep(40_000)
        }

        // 3. Clear the pasteboard, then ⌘C and wait for it to populate.
        pasteboard.clearContents()
        let preCopyCount = pasteboard.changeCount
        postCmdKey(.c)

        guard waitForPasteboardChange(from: preCopyCount, timeout: 0.5) else {
            restorePasteboard(savedItems)
            return
        }

        guard let copied = pasteboard.string(forType: .string), !copied.isEmpty else {
            restorePasteboard(savedItems)
            return
        }

        // 4. Convert.
        let converted = KeyboardConverter.convert(copied)
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
    }

    // MARK: - Selection probe via Accessibility

    private static func focusedFieldHasSelection() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return false }

        var selected: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected)
        guard status == .success, let text = selected as? String else { return false }
        return !text.isEmpty
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
