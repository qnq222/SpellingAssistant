import AppKit

enum TextReplacementError: LocalizedError {
    case accessibilityPermissionMissing
    case pasteEventFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required to replace selected text."
        case .pasteEventFailed:
            return "The paste command could not be sent."
        }
    }
}

final class TextReplacementService {
    private let clipboardService: ClipboardService
    private let accessibilityManager: AccessibilityManager

    init(
        clipboardService: ClipboardService = .shared,
        accessibilityManager: AccessibilityManager = .shared
    ) {
        self.clipboardService = clipboardService
        self.accessibilityManager = accessibilityManager
    }

    func replaceSelection(with text: String) async throws {
        guard accessibilityManager.isTrusted else {
            throw TextReplacementError.accessibilityPermissionMissing
        }

        let snapshot = clipboardService.snapshot()
        clipboardService.copy(text)

        guard sendPasteShortcut() else {
            throw TextReplacementError.pasteEventFailed
        }

        try? await Task.sleep(for: .milliseconds(450))
        clipboardService.restore(snapshot)
    }

    private func sendPasteShortcut() -> Bool {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
