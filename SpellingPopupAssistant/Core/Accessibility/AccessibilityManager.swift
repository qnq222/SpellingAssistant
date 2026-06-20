import AppKit
import ApplicationServices

final class AccessibilityManager {
    static let shared = AccessibilityManager()

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject)

        guard focusedResult == .success, let focusedElement = focusedObject else {
            return nil
        }

        var selectedTextObject: AnyObject?
        let selectedTextResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextObject)

        if selectedTextResult == .success, let selectedText = selectedTextObject as? String {
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : selectedText
        }

        return selectedTextFromSelectedRange(focusedElement as! AXUIElement)
    }

    private func selectedTextFromSelectedRange(_ focusedElement: AXUIElement) -> String? {
        var selectedRangeObject: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeObject)
        guard
            rangeResult == .success,
            let selectedRangeObject,
            CFGetTypeID(selectedRangeObject) == AXValueGetTypeID()
        else {
            return nil
        }

        let selectedRangeValue = selectedRangeObject as! AXValue
        var selectedRange = CFRange()
        guard AXValueGetValue(selectedRangeValue, .cfRange, &selectedRange), selectedRange.length > 0 else {
            return nil
        }

        guard let rangeParameter = AXValueCreate(.cfRange, &selectedRange) else {
            return nil
        }

        var selectedTextObject: AnyObject?
        let stringResult = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeParameter,
            &selectedTextObject
        )

        guard stringResult == .success, let selectedText = selectedTextObject as? String else {
            return nil
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : selectedText
    }

    @MainActor
    func selectedTextFromClipboardFallback() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        } ?? []

        guard sendCopyShortcut() else {
            return nil
        }

        let copiedString = await waitForCopiedString(
            pasteboard: pasteboard,
            previousChangeCount: previousChangeCount
        )
        let copiedSelectionChangedPasteboard = pasteboard.changeCount != previousChangeCount

        if copiedSelectionChangedPasteboard {
            restorePasteboardItems(previousItems)
        }

        guard copiedSelectionChangedPasteboard, let copiedString else {
            return nil
        }

        let trimmed = copiedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return copiedString
    }

    @MainActor
    private func waitForCopiedString(pasteboard: NSPasteboard, previousChangeCount: Int) async -> String? {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(20))

            if pasteboard.changeCount != previousChangeCount {
                return pasteboard.string(forType: .string)
            }
        }

        return nil
    }

    private func restorePasteboardItems(_ savedItems: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let restoredItems = savedItems.map { savedItem in
            let item = NSPasteboardItem()
            for (type, data) in savedItem {
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }

    private func sendCopyShortcut() -> Bool {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
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
