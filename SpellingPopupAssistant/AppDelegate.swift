import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let accessibilityManager = AccessibilityManager.shared
    private lazy var menuBarController = MenuBarController(
        settings: settings,
        accessibilityManager: accessibilityManager,
        onOpenSettings: { [weak self] in self?.openSettings() },
        onCheckSelection: { [weak self] in self?.checkCurrentSelectionNow() },
        onCheckAccessibility: { [weak self] in self?.checkAccessibilityPermission() }
    )
    private lazy var selectionMonitor = SelectionMonitor(settings: settings, accessibilityManager: accessibilityManager)
    private let popupController = CorrectionPopupController(settings: .shared)
    private lazy var hotKeyController = GlobalHotKeyController { [weak self] in
        self?.checkCurrentSelectionNow()
    }
    private var permissionWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController.install()
        configureSelectionMonitor()
        hotKeyController.start()

        if accessibilityManager.isTrusted {
            selectionMonitor.start()
        } else {
            showPermissionWindow()
            accessibilityManager.requestPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionMonitor.stop()
        hotKeyController.stop()
    }

    private func configureSelectionMonitor() {
        selectionMonitor.onCorrectionResult = { [weak self] result in
            guard result.hasCorrections else { return }
            self?.popupController.show(result: result)
        }
        selectionMonitor.onCorrectionError = { message in
            Logger.correction.error("\(message, privacy: .public)")
        }
        selectionMonitor.onSelectionCleared = { [weak self] in
            self?.popupController.hide()
        }
    }

    private func checkAccessibilityPermission() {
        if accessibilityManager.isTrusted {
            selectionMonitor.start()
        } else {
            showPermissionWindow()
            accessibilityManager.requestPermission()
        }
    }

    private func checkCurrentSelectionNow() {
        Task { @MainActor [weak self] in
            await self?.selectionMonitor.checkCurrentSelectionNow()
        }
    }

    private func openSettings() {
        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spelling Popup Assistant Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionWindow() {
        if let permissionWindowController {
            permissionWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Accessibility Permission Required"
        window.center()
        window.contentView = NSHostingView(
            rootView: AccessibilityPermissionView(
                onOpenSettings: { [weak self] in self?.accessibilityManager.openAccessibilitySettings() },
                onRecheck: { [weak self] in self?.checkAccessibilityPermission() }
            )
        )
        let controller = NSWindowController(window: window)
        permissionWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
