import AppKit
import Carbon.HIToolbox

/// A button that shows the current shortcut; click it, then press a new
/// key combination to record it. Esc cancels.
final class ShortcutRecorder: NSButton {

    var shortcut: Shortcut { didSet { refreshTitle() } }
    /// Called with the newly recorded shortcut.
    var onChange: ((Shortcut) -> Void)?
    /// Called when recording starts (true) or stops (false), so the global
    /// shortcut can be paused and doesn't fire while recording.
    var onRecordingChange: ((Bool) -> Void)?

    private var isRecording = false {
        didSet {
            refreshTitle()
            if isRecording != oldValue { onRecordingChange?(isRecording) }
        }
    }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    // ⌘-combinations arrive here, before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }
        let candidate = Shortcut(event: event)
        guard candidate.isValid else {
            // Plain keys would swallow normal typing.
            NSSound.beep()
            title = "Add ⌘, ⌥ or ⌃…"
            return
        }
        shortcut = candidate
        isRecording = false
        onChange?(candidate)
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : shortcut.displayString
    }
}
