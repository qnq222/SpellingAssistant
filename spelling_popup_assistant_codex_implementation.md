# Codex Implementation Instructions — macOS PopClip-Style Spelling Correction App

## 1. Role

You are Codex acting as a senior macOS engineer.

Build a native macOS Xcode project named:

```text
SpellingPopupAssistant
```

The app should behave like a focused PopClip-style correction tool. When the user highlights a word, sentence, or paragraph, the app should show a floating popup with corrected spelling and the number of misspelled words.

The app must be implemented in Swift using SwiftUI and AppKit where required.

---

## 2. Development Constraints

Use:

- Xcode project
- Swift
- SwiftUI for views
- AppKit for menu bar, floating panel, and Accessibility integration
- `NSSpellChecker` for local spell checking
- Optional local Ollama integration for AI correction
- No Firebase
- No external paid SDKs
- No cloud service required for Version 1

The first working version must not depend on any paid API.

---

## 3. Required App Behavior

### 3.1 Startup

When launched:

1. App starts as a menu bar utility.
2. No dock icon is required.
3. App checks whether Accessibility permission is granted.
4. If permission is missing:
   - Show a permission window.
   - Provide a button to open macOS Accessibility settings.
5. If permission is granted:
   - Start selection monitoring.

### 3.2 Selection Monitoring

The app should monitor selected text system-wide.

Implement a `SelectionMonitor` class that:

- Polls the current selected text every 400 ms.
- Uses Accessibility APIs to get focused UI element.
- Reads `kAXSelectedTextAttribute`.
- Ignores empty text.
- Ignores text longer than the configured maximum length.
- Debounces repeated same selection.
- Sends new selected text to the correction engine.

Pseudo-logic:

```swift
if appIsEnabled && accessibilityPermissionGranted {
    let selectedText = accessibilityManager.getSelectedText()
    if selectedText != lastSelectedText && !selectedText.isEmpty {
        correct(selectedText)
        showPopup(result)
    }
}
```

### 3.3 Floating Popup

Implement `CorrectionPopupController`.

Requirements:

- Use `NSPanel`.
- Panel should float above other windows.
- Panel should not steal focus if possible.
- Panel should appear near mouse pointer as a reliable fallback.
- Panel should auto-hide after a configurable timeout, default 8 seconds.
- Panel should hide when user clicks Ignore.
- Panel should resize based on text content.

Popup content:

- Header: `Spelling Correction`
- Misspelled word count
- Corrected text
- Optional list of corrected words
- Buttons:
  - `Replace`
  - `Copy`
  - `Ignore`

### 3.4 Correction Logic

Create a protocol:

```swift
protocol CorrectionEngine {
    func correct(text: String) async throws -> CorrectionResult
}
```

Create models:

```swift
struct CorrectionResult: Equatable {
    let originalText: String
    let correctedText: String
    let misspelledWordCount: Int
    let corrections: [WordCorrection]
}

struct WordCorrection: Equatable, Identifiable {
    let id = UUID()
    let original: String
    let corrected: String
}
```

### 3.5 Local macOS Spell Checker Engine

Implement:

```swift
final class MacOSSpellCheckerEngine: CorrectionEngine
```

Use:

```swift
NSSpellChecker.shared
```

Algorithm:

1. Tokenize text into words while preserving punctuation and spacing.
2. For each word:
   - Check spelling using `checkSpelling(of:startingAt:)`.
   - If misspelled:
     - Get suggestions using `guesses(forWordRange:in:language:inSpellDocumentWithTag:)`.
     - Use the first suggestion as correction.
3. Reconstruct corrected text while preserving punctuation.
4. Count misspelled words.
5. Return `CorrectionResult`.

Important:

- Do not modify words that have no suggestions.
- Preserve capitalization:
  - `recieved` → `received`
  - `Recieved` → `Received`
  - `RECIEVED` → `RECEIVED`
- Ignore:
  - URLs
  - Email addresses
  - File paths
  - Code-like tokens
  - Numbers
  - Acronyms
  - Words shorter than 2 characters

### 3.6 Optional Ollama AI Engine

Implement:

```swift
final class OllamaCorrectionEngine: CorrectionEngine
```

Use local Ollama endpoint:

```text
http://localhost:11434/api/generate
```

Default model:

```text
qwen2.5:7b
```

Request prompt:

```text
Correct only spelling mistakes in the following text.
Do not rewrite style.
Do not change meaning.
Do not improve grammar unless required for spelling.
Return valid JSON only with this schema:
{
  "correctedText": "string",
  "misspelledWordCount": number,
  "corrections": [
    {
      "original": "string",
      "corrected": "string"
    }
  ]
}

Text:
"""
{{selected_text}}
"""
```

The app must parse the JSON safely.

If Ollama is not running:

- Show an error in the popup or settings.
- Fall back to `MacOSSpellCheckerEngine`.

Version 1 can include the class but does not need to make it the default.

---

## 4. Replace Selected Text

Implement `TextReplacementService`.

Preferred approach:

1. Save corrected text to clipboard.
2. Simulate Command + V using `CGEvent`.
3. Restore previous clipboard content if possible.

Reason:

- Direct Accessibility replacement is inconsistent across apps.
- Clipboard paste is more reliable.

Requirements:

- Before replacing, store current clipboard contents.
- Put corrected text into clipboard.
- Simulate paste.
- After a small delay, restore previous clipboard contents if possible.
- If paste fails, leave corrected text in clipboard and show a small message.

Accessibility permission is required for simulated keyboard events.

---

## 5. Permissions

Create `AccessibilityManager`.

Responsibilities:

- Check permission:

```swift
AXIsProcessTrusted()
```

- Request permission:

```swift
AXIsProcessTrustedWithOptions(...)
```

- Open System Settings Accessibility page.

Permission window text:

```text
Spelling Popup Assistant requires Accessibility permission to read selected text and replace it when requested.

Open:
System Settings > Privacy & Security > Accessibility
Then enable Spelling Popup Assistant.
```

---

## 6. Settings

Create a settings window.

Settings:

| Setting | Default |
|---|---|
| App enabled | true |
| Correction engine | Local macOS Spell Checker |
| Max selected text length | 1000 characters |
| Show popup for single words | true |
| Show popup for sentences | true |
| Auto-hide timeout | 8 seconds |
| Ollama endpoint | http://localhost:11434 |
| Ollama model | qwen2.5:7b |

Use `UserDefaults` for persistence.

---

## 7. Menu Bar

Use a menu bar item with a simple icon.

Menu:

```text
Spelling Popup Assistant
------------------------
Enabled: On/Off
Correction Mode >
    Local macOS Spell Checker
    Local AI via Ollama
Settings...
Check Accessibility Permission
Quit
```

---

## 8. UI Design Requirements

The popup should look professional and minimal.

Visual style:

- Rounded corners
- Subtle shadow
- Compact layout
- macOS-native typography
- Light and dark mode support
- No heavy animations
- No large windows

Popup layout:

```text
┌────────────────────────────────────┐
│ Spelling Correction                 │
│ Misspelled words: 3                 │
│                                    │
│ I received the message from the     │
│ administrator.                     │
│                                    │
│ recieved → received                │
│ mesage → message                   │
│ adminstrator → administrator       │
│                                    │
│ [Replace] [Copy] [Ignore]          │
└────────────────────────────────────┘
```

---

## 9. File Structure to Generate

Generate the project using this structure:

```text
SpellingPopupAssistant/
│
├── SpellingPopupAssistant.xcodeproj
│
├── SpellingPopupAssistant/
│   ├── SpellingPopupAssistantApp.swift
│   ├── AppDelegate.swift
│   │
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── CorrectionResult.swift
│   │   │   ├── WordCorrection.swift
│   │   │   └── AppSettings.swift
│   │   │
│   │   ├── Engines/
│   │   │   ├── CorrectionEngine.swift
│   │   │   ├── MacOSSpellCheckerEngine.swift
│   │   │   └── OllamaCorrectionEngine.swift
│   │   │
│   │   ├── Accessibility/
│   │   │   ├── AccessibilityManager.swift
│   │   │   ├── SelectionMonitor.swift
│   │   │   └── TextReplacementService.swift
│   │   │
│   │   ├── Popup/
│   │   │   ├── CorrectionPopupController.swift
│   │   │   └── PopupPositioningService.swift
│   │   │
│   │   └── Utilities/
│   │       ├── ClipboardService.swift
│   │       ├── Debouncer.swift
│   │       └── Logger.swift
│   │
│   ├── UI/
│   │   ├── Popup/
│   │   │   └── CorrectionPopupView.swift
│   │   │
│   │   ├── Settings/
│   │   │   └── SettingsView.swift
│   │   │
│   │   └── Permission/
│   │       └── AccessibilityPermissionView.swift
│   │
│   └── Assets.xcassets
│
└── SpellingPopupAssistantTests/
    ├── MacOSSpellCheckerEngineTests.swift
    └── CorrectionResultTests.swift
```

---

## 10. Testing Requirements

Create unit tests for:

- Single misspelled word correction
- Sentence correction
- No spelling mistakes
- Capitalization preservation
- Ignoring URLs
- Ignoring emails
- Ignoring numbers
- Counting misspelled words correctly

Example tests:

```text
recieved -> received
mesage -> message
adminstrator -> administrator
I recieved the mesage. -> I received the message.
```

---

## 11. Edge Cases

Handle these cases safely:

- No selected text
- Unsupported app
- Accessibility permission revoked
- Very long selected text
- Text with emojis
- Text with URLs
- Text with email addresses
- Text containing code
- Ollama unavailable
- Clipboard unavailable
- User selects the same text repeatedly

---

## 12. Build Milestones

### Milestone 1 — Basic App Shell

- Create macOS Xcode project
- Add menu bar item
- Hide dock icon
- Add settings window
- Add permission window

### Milestone 2 — Accessibility Selection Reader

- Add Accessibility permission check
- Read selected text from focused element
- Poll selection changes
- Log selected text in debug mode

### Milestone 3 — Local Spell Checker

- Implement `MacOSSpellCheckerEngine`
- Return corrected text and misspelled count
- Add unit tests

### Milestone 4 — Floating Popup

- Implement `NSPanel`
- Add SwiftUI popup view
- Show correction result near cursor
- Add Copy and Ignore actions

### Milestone 5 — Replace Function

- Implement clipboard paste replacement
- Restore clipboard after paste
- Add failure handling

### Milestone 6 — Ollama Integration

- Add local AI engine
- Add model and endpoint settings
- Add fallback to local spell checker

### Milestone 7 — Polish

- Improve popup styling
- Add dark mode support
- Add app-specific error handling
- Final testing in Safari, Chrome, Notes, Mail, Outlook, Teams, and VS Code

---

## 13. Important Implementation Notes

- Prioritize reliability over complex features.
- Do not build live typing correction in Version 1.
- Do not send text to any external cloud API.
- Default to local macOS spell checking.
- Keep AI local and optional.
- Use AppKit where SwiftUI cannot handle system-level behavior.
- Keep the architecture modular and testable.
- Write clean Swift code with clear comments.
- Avoid overengineering the first version.

---

## 14. Final Output Expected from Codex

Codex should produce:

1. A complete Xcode macOS project.
2. Swift source files following the requested structure.
3. Working menu bar app.
4. Accessibility permission flow.
5. System-wide selected text detection where supported.
6. PopClip-style floating correction popup.
7. Local spelling correction using `NSSpellChecker`.
8. Misspelled word count.
9. Copy and Replace buttons.
10. Unit tests for the correction engine.
11. README with setup and usage instructions.
