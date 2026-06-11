import AppKit
import XCTest
@testable import SpellingPopupAssistant

final class KeyboardShortcutSettingTests: XCTestCase {
    func testManualShortcutFallbackDefaultsOff() {
        let defaults = UserDefaults(suiteName: "KeyboardShortcutSettingTests.\(UUID().uuidString)")!

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.isManualShortcutEnabled)
    }

    func testRecordsShortcutWithoutRequiredModifier() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )

        let shortcut = event.flatMap(KeyboardShortcutSetting.init(event:))

        XCTAssertEqual(shortcut?.keyCode, 0)
        XCTAssertEqual(shortcut?.title, "A")
    }

    func testIgnoresModifierOnlyKeys() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 55
        )

        XCTAssertNil(event.flatMap(KeyboardShortcutSetting.init(event:)))
    }

    func testMatchesCGEventFlags() {
        let shortcut = KeyboardShortcutSetting(
            keyCode: 8,
            modifiers: [.control, .option],
            keyEquivalent: "C"
        )
        let flags: CGEventFlags = [.maskControl, .maskAlternate]

        XCTAssertTrue(shortcut.matches(keyCode: 8, cgFlags: flags))
        XCTAssertFalse(shortcut.matches(keyCode: 8, cgFlags: .maskControl))
    }
}
