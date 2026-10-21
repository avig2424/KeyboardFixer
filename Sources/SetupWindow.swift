import AppKit

/// First-run window: explains the app, walks through the Accessibility
/// permission (updating live once it's granted), and offers a field to try
/// the shortcut in.
final class SetupWindowController: NSWindowController {

    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)
    private let tryLabel = NSTextField(wrappingLabelWithString: "")
    private let tryField = NSTextField(string: "akuo nv bang")
    private var timer: Timer?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to KeyboardFixer"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                               name: NSWindow.willCloseNotification, object: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        // Poll: macOS doesn't notify apps when Accessibility is granted.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func windowWillClose() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Layout

    private func buildContent() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "Fix text typed in the wrong language")
        title.font = .boldSystemFont(ofSize: 15)
        let intro = wrapping("""
            Typed “akuo” when you meant “שלום”? Select the text and press the \
            shortcut — KeyboardFixer rewrites it as if you’d typed it in the right \
            keyboard layout. Your text never leaves your Mac.
            """)

        let step1 = heading("1. Allow Accessibility access")
        let why = wrapping("""
            Needed to copy the selected text and paste the fixed version. In System \
            Settings, turn on KeyboardFixer.
            """)
        statusLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let statusRow = NSStackView(views: [statusIcon, statusLabel])
        statusRow.spacing = 6
        permissionButton.target = self
        permissionButton.action = #selector(openSettings)

        let step2 = heading("2. Try it")
        tryField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, title, intro,
                                        step1, why, statusRow, permissionButton,
                                        step2, tryLabel, tryField, done])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: intro)
        stack.setCustomSpacing(16, after: permissionButton)
        stack.setCustomSpacing(20, after: tryField)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [intro, why, tryLabel] { v.widthAnchor.constraint(equalToConstant: 412).isActive = true }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
        ])
        window?.contentView = content
    }

    private func heading(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return f
    }

    private func wrapping(_ text: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func refresh() {
        let granted = AXIsProcessTrusted()
        statusIcon.image = NSImage(systemSymbolName: granted ? "checkmark.circle.fill" : "xmark.circle.fill",
                                   accessibilityDescription: nil)
        statusIcon.contentTintColor = granted ? .systemGreen : .systemRed
        statusLabel.stringValue = granted ? "Accessibility access is on" : "Accessibility access is off"
        permissionButton.isHidden = granted
        tryLabel.stringValue = "Select the text below and press the shortcut "
            + "(\(Settings.shortcut.displayString)). You can change it in Settings."
        tryField.isEnabled = granted
    }

    // MARK: - Actions

    @objc private func openSettings() {
        // The prompt also adds KeyboardFixer to the list in System Settings.
        if !TextFixer.requestAccessibility() {
            TextFixer.openAccessibilitySettings()
        }
    }

    @objc private func finish() {
        Settings.hasCompletedSetup = true
        window?.close()
    }
}
