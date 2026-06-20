import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private let settings: AppSettings
    private let accessibilityManager: AccessibilityManager
    private let onOpenSettings: () -> Void
    private let onCheckSelection: () -> Void
    private let onCheckAccessibility: () -> Void
    private var statusItem: NSStatusItem?
    private var settingsCancellable: AnyCancellable?
    private var isCorrecting = false

    init(
        settings: AppSettings,
        accessibilityManager: AccessibilityManager,
        onOpenSettings: @escaping () -> Void,
        onCheckSelection: @escaping () -> Void,
        onCheckAccessibility: @escaping () -> Void
    ) {
        self.settings = settings
        self.accessibilityManager = accessibilityManager
        self.onOpenSettings = onOpenSettings
        self.onCheckSelection = onCheckSelection
        self.onCheckAccessibility = onCheckAccessibility
    }

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItemAppearance()
        rebuildMenu()

        settingsCancellable = settings.objectWillChange
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
    }

    func setCorrecting(_ isCorrecting: Bool) {
        self.isCorrecting = isCorrecting
        updateStatusItemAppearance()
        rebuildMenu()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        if isCorrecting {
            statusItem?.length = NSStatusItem.variableLength
            button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Correcting selected text")
            button.title = " Correcting..."
            button.imagePosition = .imageLeft
        } else {
            statusItem?.length = NSStatusItem.squareLength
            button.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "Spelling Popup Assistant")
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Spelling Popup Assistant", action: nil, keyEquivalent: "")
        if isCorrecting {
            menu.addItem(withTitle: "Correcting selected text...", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: settings.isEnabled ? "Enabled: On" : "Enabled: Off", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let modeItem = NSMenuItem(title: "Correction Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in CorrectionMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectCorrectionMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.correctionMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let checkSelectionTitle = settings.isManualShortcutEnabled
            ? "Check Selected Text Now (\(settings.checkSelectionShortcut.title))"
            : "Check Selected Text Now"
        let checkSelectionItem = NSMenuItem(title: checkSelectionTitle, action: #selector(checkSelection), keyEquivalent: "")
        checkSelectionItem.target = self
        checkSelectionItem.isEnabled = !isCorrecting
        menu.addItem(checkSelectionItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionItem = NSMenuItem(title: accessibilityManager.isTrusted ? "Accessibility Permission: Granted" : "Check Accessibility Permission", action: #selector(checkAccessibility), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        rebuildMenu()
    }

    @objc private func selectCorrectionMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = CorrectionMode(rawValue: rawValue) else {
            return
        }
        settings.correctionMode = mode
        rebuildMenu()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func checkSelection() {
        onCheckSelection()
    }

    @objc private func checkAccessibility() {
        onCheckAccessibility()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
