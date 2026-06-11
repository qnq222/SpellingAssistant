import AppKit
import Carbon
import Combine
import CoreGraphics

@MainActor
final class GlobalHotKeyController {
    private var localMonitor: Any?
    private let settings: AppSettings
    private let onCheckSelection: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var settingsCancellable: AnyCancellable?
    private var lastFireDate = Date.distantPast

    init(settings: AppSettings = .shared, onCheckSelection: @escaping () -> Void) {
        self.settings = settings
        self.onCheckSelection = onCheckSelection
    }

    func start() {
        stop()
        settingsCancellable = Publishers.CombineLatest(settings.$checkSelectionShortcut, settings.$isManualShortcutEnabled)
            .dropFirst()
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshShortcutListeners()
                }
            }

        refreshShortcutListeners()
    }

    func stop() {
        settingsCancellable?.cancel()
        settingsCancellable = nil
        uninstallShortcutListeners()
    }

    private func refreshShortcutListeners() {
        uninstallShortcutListeners()

        guard settings.isManualShortcutEnabled else { return }

        installCarbonHotKey()
        installEventTapFallback()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if self.isCheckSelectionHotKey(event) {
                Task { @MainActor [weak self] in
                    self?.fireCheckSelection()
                }
                return nil
            }

            return event
        }
    }

    private func uninstallShortcutListeners() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        unregisterCarbonHotKey()
        uninstallEventTapFallback()
    }

    private func isCheckSelectionHotKey(_ event: NSEvent) -> Bool {
        settings.checkSelectionShortcut.matches(event)
    }

    private func fireCheckSelection() {
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) > 0.25 else { return }
        lastFireDate = now
        onCheckSelection()
    }

    private func installCarbonHotKey() {
        unregisterCarbonHotKey()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    controller.fireCheckSelection()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        var hotKeyID = EventHotKeyID(signature: 0x53504148, id: 1)
        RegisterEventHotKey(
            UInt32(settings.checkSelectionShortcut.keyCode),
            settings.checkSelectionShortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func installEventTapFallback() {
        uninstallEventTapFallback()

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userData in
                guard type == .keyDown, let userData else {
                    return Unmanaged.passUnretained(event)
                }

                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                Task { @MainActor in
                    if controller.settings.checkSelectionShortcut.matches(keyCode: keyCode, cgFlags: flags) {
                        controller.fireCheckSelection()
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: userData
        ) else {
            Logger.app.error("Failed to install keyboard event tap fallback.")
            return
        }

        self.eventTap = eventTap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func uninstallEventTapFallback() {
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func unregisterCarbonHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
