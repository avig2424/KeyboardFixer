import AppKit
import ServiceManagement

/// The Settings window: shortcut, second language, and behaviour options.
/// Every change applies immediately.
final class SettingsWindowController: NSWindowController {

    /// Called when the user records a new shortcut.
    var onShortcutChange: ((Shortcut) -> Void)?
    /// Called when shortcut recording starts/stops.
    var onRecordingChange: ((Bool) -> Void)?

    private let recorder = ShortcutRecorder(shortcut: Settings.shortcut)
    private let languagePopup = NSPopUpButton()
    private let noSelectionPopup = NSPopUpButton()
    private let smartCheckbox = NSButton(checkboxWithTitle: "Fix mixed text word by word", target: nil, action: nil)
    private let switchCheckbox = NSButton(checkboxWithTitle: "Switch keyboard after converting", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private var layouts: [InputSources.Layout] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "KeyboardFixer Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Refresh from current state and bring the window to the front.
    func present() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContent() {
        recorder.onChange = { [weak self] shortcut in
            Settings.shortcut = shortcut
            self?.onShortcutChange?(shortcut)
        }
        recorder.onRecordingChange = { [weak self] recording in self?.onRecordingChange?(recording) }

        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        noSelectionPopup.addItems(withTitles: ["Convert the whole field", "Convert the current line"])
        noSelectionPopup.target = self
        noSelectionPopup.action = #selector(noSelectionChanged)

        for box in [smartCheckbox, switchCheckbox, loginCheckbox] {
            box.target = self
            box.action = #selector(checkboxChanged(_:))
        }

        let grid = NSGridView(views: [
            [label("Shortcut:"), recorder],
            [label("Second language:"), languagePopup],
            [label("When nothing is selected:"), noSelectionPopup],
            [NSGridCell.emptyContentView, smartCheckbox],
            [NSGridCell.emptyContentView, note("Only the words typed in the wrong language are changed; the rest stays as it is.")],
            [NSGridCell.emptyContentView, switchCheckbox],
            [NSGridCell.emptyContentView, loginCheckbox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10
        grid.rowSpacing = 12
        grid.row(at: 4).topPadding = -8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
        ])
        window?.contentView = content
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func note(_ text: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        f.textColor = .secondaryLabelColor
        f.preferredMaxLayoutWidth = 260
        return f
    }

    private func reload() {
        recorder.shortcut = Settings.shortcut

        layouts = InputSources.enabledOtherLayouts()
        languagePopup.removeAllItems()
        let auto = InputSources.automaticOtherLayoutName().map { "Automatic (\($0))" } ?? "Automatic"
        languagePopup.addItem(withTitle: auto)
        languagePopup.addItems(withTitles: layouts.map(\.name))
        if let chosen = Settings.otherLayoutID, let i = layouts.firstIndex(where: { $0.id == chosen }) {
            languagePopup.selectItem(at: i + 1)
        } else {
            languagePopup.selectItem(at: 0)
        }

        noSelectionPopup.selectItem(at: Settings.noSelection == .wholeField ? 0 : 1)
        smartCheckbox.state = Settings.smartMode ? .on : .off
        switchCheckbox.state = Settings.switchKeyboard ? .on : .off
        loginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        loginCheckbox.isEnabled = LaunchAtLogin.isAvailable
    }

    // MARK: - Actions

    @objc private func languageChanged() {
        let i = languagePopup.indexOfSelectedItem
        Settings.otherLayoutID = i > 0 ? layouts[i - 1].id : nil
    }

    @objc private func noSelectionChanged() {
        Settings.noSelection = noSelectionPopup.indexOfSelectedItem == 0 ? .wholeField : .currentLine
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case smartCheckbox: Settings.smartMode = on
        case switchCheckbox: Settings.switchKeyboard = on
        case loginCheckbox:
            if !LaunchAtLogin.set(on) { sender.state = on ? .off : .on }
        default: break
        }
    }
}

/// Launch-at-login via SMAppService (macOS 13+).
enum LaunchAtLogin {
    static var isAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    /// Returns false (after showing the error) if it couldn't be changed.
    static func set(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}
