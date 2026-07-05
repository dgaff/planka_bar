import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cardPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image()
        statusItem.button?.toolTip = "PlankaBar — quick cards for Planka"
        rebuildMenu()

        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.showCardPanel()
        }
        HotKeyManager.shared.registerFromSettings()

        // First run: if never configured, open Settings so the user can log in.
        if SettingsStore.shared.serverURL.isEmpty {
            showSettings()
        }
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()

        let settings = SettingsStore.shared
        let shortcut = KeyCombo.display(keyCode: UInt32(settings.hotkeyKeyCode),
                                        carbonModifiers: UInt32(settings.hotkeyModifiers))
        let createItem = NSMenuItem(title: "Create New Card    \(shortcut)",
                                    action: #selector(createNewCard), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit PlankaBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func createNewCard() {
        showCardPanel()
    }

    @objc private func openSettings() {
        showSettings()
    }

    // MARK: - Card panel

    func showCardPanel() {
        // Not configured yet? Route to Settings with an explanation.
        guard !SettingsStore.shared.serverURL.isEmpty, PlankaClient.shared.hasToken else {
            showSettings()
            Toast.show("Log in to Planka first", systemImage: "exclamationmark.triangle.fill")
            return
        }

        if let cardPanel {
            cardPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "New Planka Card"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.isMovableByWindowBackground = true

        let view = NewCardView { [weak self] created, cardName in
            self?.closeCardPanel()
            if created, let cardName {
                Toast.show("Added \"\(cardName)\"")
            }
        }
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        // Position slightly above center, like Spotlight.
        if let screen = NSScreen.main {
            var frame = panel.frame
            frame.origin.y = screen.visibleFrame.midY + screen.visibleFrame.height * 0.12
            panel.setFrame(frame, display: false)
        }

        cardPanel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(cardPanelClosed(_:)),
                                               name: NSWindow.willCloseNotification, object: panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func cardPanelClosed(_ note: Notification) {
        if let panel = note.object as? NSPanel, panel === cardPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            cardPanel = nil
        }
    }

    private func closeCardPanel() {
        cardPanel?.close() // triggers cardPanelClosed
    }

    // MARK: - Settings window

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "PlankaBar Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.setContentSize(window.contentView!.fittingSize)
        window.center()

        settingsWindow = window
        NotificationCenter.default.addObserver(self, selector: #selector(settingsClosed(_:)),
                                               name: NSWindow.willCloseNotification, object: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func settingsClosed(_ note: Notification) {
        if let window = note.object as? NSWindow, window === settingsWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            settingsWindow = nil
            rebuildMenu() // shortcut may have changed
        }
    }
}
