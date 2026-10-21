import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var convertItem: NSMenuItem!
    private var hotkey: HotkeyManager!
    /// Sparkle: checks GitHub for new versions once a day and offers to install.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController(updater: updaterController.updater)
        controller.onShortcutChange = { [weak self] shortcut in self?.apply(shortcut) }
        controller.onRecordingChange = { [weak self] recording in
            // Pause the global shortcut so pressing it records instead of converting.
            if recording { self?.hotkey.unregister() } else { self?.apply(Settings.shortcut) }
        }
        return controller
    }()
    private lazy var setupWindow = SetupWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no Dock icon
        Settings.registerDefaults()
        NSApp.mainMenu = buildMainMenu()

        buildStatusItem()

        hotkey = HotkeyManager { [weak self] in
            self?.runConversion()
        }
        apply(Settings.shortcut)

        TextFixer.onMissingPermission = { [weak self] in self?.showSetup() }
        if !Settings.hasCompletedSetup || !AXIsProcessTrusted() {
            showSetup()
        }
    }

    private func apply(_ shortcut: Shortcut) {
        if !hotkey.register(shortcut) {
            let alert = NSAlert()
            alert.messageText = "Couldn’t use \(shortcut.displayString) as the shortcut."
            alert.informativeText = "Another app may be using it. Pick a different one in Settings."
            alert.runModal()
        }
        statusItem.button?.toolTip = "KeyboardFixer (\(shortcut.displayString))"
        convertItem.keyEquivalent = shortcut.keyEquivalent ?? ""
        convertItem.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    // MARK: - Menus

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "א/A"

        let menu = NSMenu()
        convertItem = item("Convert selected text", #selector(convertAction))
        menu.addItem(convertItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Setup Guide…", #selector(showSetupAction)))
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = updaterController
        menu.addItem(updates)
        menu.addItem(item("About KeyboardFixer", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit KeyboardFixer", #selector(quitAction), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Menu-bar-only apps have no visible main menu, but text fields in our
    /// windows still need its Edit shortcuts (⌘C, ⌘V, ⌘A…) to work.
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    // MARK: - Actions

    private func runConversion() {
        TextFixer.fixSelectedText()
    }

    @objc private func convertAction() {
        runConversion()
    }

    @objc private func showSettings() {
        settingsWindow.present()
    }

    @objc private func showSetupAction() {
        showSetup()
    }

    private func showSetup() {
        setupWindow.present()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Fixes text typed in the wrong keyboard language.\nYour text never leaves your Mac.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
