import Foundation
import AppKit
import Carbon

enum CorrectionMode: String, CaseIterable, Identifiable {
    case localSpellChecker
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localSpellChecker:
            return "Local macOS Spell Checker"
        case .ollama:
            return "Local AI via Ollama"
        }
    }
}

struct KeyboardShortcutSetting: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRawValue: UInt
    let keyEquivalent: String

    static let `default` = KeyboardShortcutSetting(
        keyCode: 8,
        modifiers: [.control, .option],
        keyEquivalent: "C"
    )

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyEquivalent: String) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
        self.keyEquivalent = keyEquivalent.uppercased()
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !event.isARepeat, !Self.isModifierOnlyKey(event.keyCode) else {
            return nil
        }

        let keyEquivalent = event.charactersIgnoringModifiers?.uppercased() ?? Self.displayName(for: event.keyCode)
        self.init(keyCode: event.keyCode, modifiers: modifiers, keyEquivalent: keyEquivalent)
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }

    var title: String {
        let parts = [
            modifiers.contains(.control) ? "Control" : nil,
            modifiers.contains(.option) ? "Option" : nil,
            modifiers.contains(.shift) ? "Shift" : nil,
            modifiers.contains(.command) ? "Command" : nil,
            keyEquivalent.isEmpty ? Self.displayName(for: keyCode) : keyEquivalent
        ].compactMap { $0 }

        return parts.joined(separator: " + ")
    }

    var carbonModifiers: UInt32 {
        var value = UInt32(0)
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }

    func matches(keyCode: UInt16, cgFlags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && Self.modifiers(from: cgFlags) == modifiers
    }

    private static func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    private static func modifiers(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    private static func displayName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default: return "Key \(keyCode)"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let correctionMode = "correctionMode"
        static let maxSelectedTextLength = "maxSelectedTextLength"
        static let showPopupForSingleWords = "showPopupForSingleWords"
        static let showPopupForSentences = "showPopupForSentences"
        static let autoHideTimeout = "autoHideTimeout"
        static let ollamaEndpoint = "ollamaEndpoint"
        static let ollamaModel = "ollamaModel"
        static let grammarCheckerEnabled = "grammarCheckerEnabled"
        static let isManualShortcutEnabled = "isManualShortcutEnabled"
        static let checkSelectionShortcut = "checkSelectionShortcut"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var correctionMode: CorrectionMode {
        didSet { defaults.set(correctionMode.rawValue, forKey: Keys.correctionMode) }
    }

    @Published var maxSelectedTextLength: Int {
        didSet { defaults.set(maxSelectedTextLength, forKey: Keys.maxSelectedTextLength) }
    }

    @Published var showPopupForSingleWords: Bool {
        didSet { defaults.set(showPopupForSingleWords, forKey: Keys.showPopupForSingleWords) }
    }

    @Published var showPopupForSentences: Bool {
        didSet { defaults.set(showPopupForSentences, forKey: Keys.showPopupForSentences) }
    }

    @Published var autoHideTimeout: Double {
        didSet { defaults.set(autoHideTimeout, forKey: Keys.autoHideTimeout) }
    }

    @Published var ollamaEndpoint: String {
        didSet { defaults.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published var grammarCheckerEnabled: Bool {
        didSet { defaults.set(grammarCheckerEnabled, forKey: Keys.grammarCheckerEnabled) }
    }

    @Published var isManualShortcutEnabled: Bool {
        didSet { defaults.set(isManualShortcutEnabled, forKey: Keys.isManualShortcutEnabled) }
    }

    @Published var checkSelectionShortcut: KeyboardShortcutSetting {
        didSet {
            if let data = try? JSONEncoder().encode(checkSelectionShortcut) {
                defaults.set(data, forKey: Keys.checkSelectionShortcut)
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.isEnabled) == nil {
            defaults.set(true, forKey: Keys.isEnabled)
        }
        if defaults.object(forKey: Keys.maxSelectedTextLength) == nil {
            defaults.set(1000, forKey: Keys.maxSelectedTextLength)
        }
        if defaults.object(forKey: Keys.showPopupForSingleWords) == nil {
            defaults.set(true, forKey: Keys.showPopupForSingleWords)
        }
        if defaults.object(forKey: Keys.showPopupForSentences) == nil {
            defaults.set(true, forKey: Keys.showPopupForSentences)
        }
        if defaults.object(forKey: Keys.autoHideTimeout) == nil {
            defaults.set(8.0, forKey: Keys.autoHideTimeout)
        }
        if defaults.object(forKey: Keys.ollamaEndpoint) == nil {
            defaults.set("http://localhost:11434", forKey: Keys.ollamaEndpoint)
        }
        if defaults.object(forKey: Keys.ollamaModel) == nil {
            defaults.set("qwen2.5:7b", forKey: Keys.ollamaModel)
        }
        if defaults.object(forKey: Keys.grammarCheckerEnabled) == nil {
            defaults.set(false, forKey: Keys.grammarCheckerEnabled)
        }
        if defaults.object(forKey: Keys.isManualShortcutEnabled) == nil {
            defaults.set(false, forKey: Keys.isManualShortcutEnabled)
        }
        if defaults.object(forKey: Keys.checkSelectionShortcut) == nil {
            if let data = try? JSONEncoder().encode(KeyboardShortcutSetting.default) {
                defaults.set(data, forKey: Keys.checkSelectionShortcut)
            }
        }

        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        correctionMode = CorrectionMode(rawValue: defaults.string(forKey: Keys.correctionMode) ?? "") ?? .localSpellChecker
        maxSelectedTextLength = defaults.integer(forKey: Keys.maxSelectedTextLength)
        showPopupForSingleWords = defaults.bool(forKey: Keys.showPopupForSingleWords)
        showPopupForSentences = defaults.bool(forKey: Keys.showPopupForSentences)
        autoHideTimeout = defaults.double(forKey: Keys.autoHideTimeout)
        ollamaEndpoint = defaults.string(forKey: Keys.ollamaEndpoint) ?? "http://localhost:11434"
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "qwen2.5:7b"
        grammarCheckerEnabled = defaults.bool(forKey: Keys.grammarCheckerEnabled)
        isManualShortcutEnabled = defaults.bool(forKey: Keys.isManualShortcutEnabled)
        if
            let data = defaults.data(forKey: Keys.checkSelectionShortcut),
            let shortcut = try? JSONDecoder().decode(KeyboardShortcutSetting.self, from: data)
        {
            checkSelectionShortcut = shortcut
        } else {
            checkSelectionShortcut = .default
        }
    }
}
