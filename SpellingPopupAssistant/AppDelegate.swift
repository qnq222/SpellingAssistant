import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let accessibilityManager = AccessibilityManager.shared
    private let gectorHelperProcessManager = GECToRHelperProcessManager.shared
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
    private lazy var memoryPressureObserver = MemoryPressureObserver {
        Task {
            await EngineManager.shared.shutdownNow()
        }
    }
    private var permissionWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var settingsCancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController.install()
        configureSelectionMonitor()
        configureGECToRHelperProcessManagement()
        hotKeyController.start()
        memoryPressureObserver.start()
        gectorHelperProcessManager.start(endpoint: settings.gectorHelperEndpoint)

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
        memoryPressureObserver.stop()
        settingsCancellables.removeAll()
        gectorHelperProcessManager.stop()
        EmbeddedLanguageToolService.shared.stop()
    }

    private func configureSelectionMonitor() {
        selectionMonitor.onCorrectionStarted = { [weak self] in
            self?.menuBarController.setCorrecting(true)
        }
        selectionMonitor.onCorrectionFinished = { [weak self] in
            self?.menuBarController.setCorrecting(false)
        }
        selectionMonitor.onCorrectionResult = { [weak self] result in
            self?.popupController.show(
                result: result,
                transientMessage: result.hasCorrections ? nil : "No corrections found."
            )
        }
        selectionMonitor.onCorrectionError = { message in
            Logger.correction.error("\(message, privacy: .public)")
        }
        selectionMonitor.onSelectionCleared = { [weak self] in
            self?.popupController.hide()
        }
    }

    private func configureGECToRHelperProcessManagement() {
        settings.$gectorHelperEndpoint
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] endpoint in
                guard let self else { return }
                self.gectorHelperProcessManager.stop()
                self.gectorHelperProcessManager.start(endpoint: endpoint)
            }
            .store(in: &settingsCancellables)
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
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
