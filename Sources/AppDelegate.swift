import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no Dock icon

        buildStatusItem()

        hotkey = HotkeyManager { [weak self] in
            self?.runConversion()
        }
        hotkey.register()

        // Prompt up front if Accessibility isn't granted yet.
        _ = TextFixer.ensureAccessibility(prompt: true)
    }

    // MARK: - Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "א/A"
            button.toolTip = "KeyboardFixer (⌘M)"
        }

        let menu = NSMenu()

        let convertItem = NSMenuItem(title: "Convert selected text",
                                     action: #selector(convertAction),
                                     keyEquivalent: "m")
        convertItem.keyEquivalentModifierMask = [.command]
        convertItem.target = self
        menu.addItem(convertItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at login",
                                    action: #selector(toggleLaunchAtLogin),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit KeyboardFixer",
                                  action: #selector(quitAction),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    private func runConversion() {
        TextFixer.fixSelectedText()
    }

    @objc private func convertAction() {
        runConversion()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else {
            let alert = NSAlert()
            alert.messageText = "Launch at login requires macOS 13 or later."
            alert.runModal()
            return
        }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                sender.state = .off
            } else {
                try service.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
