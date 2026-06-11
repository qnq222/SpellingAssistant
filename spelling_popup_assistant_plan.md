# PopClip-Style macOS Spelling Correction Assistant — Product & Architecture Plan

## 1. Project Goal

Build a native macOS application in Xcode that behaves similarly to PopClip, but focused only on spelling correction.

The app should:

- Detect when the user highlights/selects text in any macOS application.
- Show a small floating correction popup near the selected text.
- Check the selected word or sentence for misspelled words.
- Display corrected text.
- Show how many misspelled words were found.
- Allow the user to copy the corrected text.
- Optionally allow replacing the selected text with the corrected version.
- Work system-wide where macOS Accessibility permissions allow it.

This is not a full grammar assistant. The first version should focus only on spelling mistakes.

---

## 2. Target Platform

- Platform: macOS
- IDE: Xcode
- Language: Swift
- UI Framework: SwiftUI + AppKit where needed
- Minimum macOS version: macOS 13 Ventura or later
- App type: Menu bar utility application
- Distribution target: Local/private use first, not Mac App Store initially

---

## 3. User Experience

### 3.1 Main User Flow

1. User selects a word, sentence, or paragraph in any app.
2. App detects the selected text using macOS Accessibility APIs.
3. A compact floating panel appears near the selected text or mouse pointer.
4. Panel shows:
   - Original selected text preview
   - Corrected version
   - Misspelled word count
   - Buttons:
     - `Copy`
     - `Replace`
     - `Ignore`
5. User clicks:
   - `Copy`: corrected text is copied to clipboard.
   - `Replace`: selected text is replaced with corrected text.
   - `Ignore`: popup closes.

### 3.2 Example

Selected text:

```text
I recieved the mesage from the adminstrator.
```

Popup should show:

```text
Corrected:
I received the message from the administrator.

Misspelled words: 3
```

Actions:

```text
[Replace] [Copy] [Ignore]
```

---

## 4. Core Requirements

### 4.1 Selection Detection

The app must detect selected text system-wide.

Use macOS Accessibility APIs:

- `AXUIElementCreateSystemWide`
- `AXUIElementCopyAttributeValue`
- `kAXFocusedUIElementAttribute`
- `kAXSelectedTextAttribute`
- `kAXSelectedTextRangeAttribute`
- `AXObserver` where applicable

The app must request Accessibility permission from the user.

If permission is missing, show a clear setup screen explaining:

```text
To use system-wide spelling correction, enable Accessibility access:
System Settings > Privacy & Security > Accessibility > Enable this app.
```

### 4.2 Floating Popup

The floating popup should be:

- Small
- Clean
- Always on top
- Non-intrusive
- Similar in behavior to PopClip
- Positioned near:
  - Current mouse pointer, or
  - The selected text bounds if available from Accessibility API

Recommended implementation:

- Use `NSPanel`
- Set `isFloatingPanel = true`
- Use `.nonactivatingPanel`
- Use `.floating` window level
- Embed SwiftUI view using `NSHostingView`

### 4.3 Spell Checking

The app should support two spell-checking layers:

#### Layer 1 — Local macOS Spell Checker

Use:

```swift
NSSpellChecker.shared
```

This should be the default engine because it is:

- Free
- Offline
- Fast
- Private
- Built into macOS

It should detect misspelled words and suggest corrections.

#### Layer 2 — Optional AI Correction Engine

Use this only when enabled by the user.

The AI model should receive selected text and return:

- Corrected text
- Misspelled word count
- List of corrected words

The app should support a pluggable correction engine architecture so that AI providers can be swapped later.

---

## 5. Recommended Free AI Model

### Recommended Option: Ollama + Qwen2.5 7B

For a free local AI model, use Ollama.

Recommended model options:

1. `qwen2.5:7b`
2. `llama3.1:8b`
3. `mistral:7b`

Best practical recommendation:

```text
qwen2.5:7b
```

Reason:

- Good short-text correction quality
- Free
- Runs locally
- No API cost
- Better privacy than cloud APIs
- Suitable for selected text corrections

Install Ollama:

```bash
brew install ollama
```

Run model:

```bash
ollama pull qwen2.5:7b
ollama run qwen2.5:7b
```

The macOS app can call Ollama locally via:

```text
http://localhost:11434/api/generate
```

Important: AI should be optional. The app must work without Ollama using only `NSSpellChecker`.

---

## 6. Privacy Requirements

The app should be privacy-first.

- Do not collect user text.
- Do not send selected text to cloud services by default.
- Local spell checking should be the default.
- AI correction should use local Ollama by default.
- Add a settings toggle:
  - `Use Local macOS Spell Checker`
  - `Use Local AI with Ollama`
- Show a notice when AI mode is enabled:
  - Text will be sent only to the local Ollama server running on this Mac.

---

## 7. App Components

### 7.1 Menu Bar App

The app should run in the menu bar.

Menu items:

- Enable / Disable Correction Popup
- Correction Mode:
  - Local macOS Spell Checker
  - Local AI via Ollama
- Check Accessibility Permission
- Settings
- Quit

### 7.2 Accessibility Manager

Responsibilities:

- Request Accessibility permissions.
- Detect focused application.
- Read selected text.
- Optionally replace selected text.
- Handle unsupported apps gracefully.

### 7.3 Selection Monitor

Responsibilities:

- Detect when selection changes.
- Avoid showing popup too frequently.
- Debounce selection detection.
- Ignore empty selections.
- Ignore very long text unless user allows it.

Recommended behavior:

- Poll selected text every 300–500 ms when enabled.
- Cache last selected text.
- Show popup only when selected text changes.
- Hide popup when selection is cleared.

### 7.4 Correction Engine

Use protocol-based design:

```swift
protocol CorrectionEngine {
    func correct(text: String) async throws -> CorrectionResult
}
```

Correction result:

```swift
struct CorrectionResult {
    let originalText: String
    let correctedText: String
    let misspelledWordCount: Int
    let corrections: [WordCorrection]
}
```

Word correction:

```swift
struct WordCorrection {
    let original: String
    let corrected: String
}
```

Implement:

- `MacOSSpellCheckerEngine`
- `OllamaCorrectionEngine`

### 7.5 Popup Controller

Responsibilities:

- Show floating correction panel.
- Position panel.
- Update content.
- Handle Replace / Copy / Ignore actions.

### 7.6 Settings

Settings should persist using:

```swift
UserDefaults
```

Settings:

- App enabled
- Correction engine
- Maximum selected text length
- Show popup for single words
- Show popup for sentences
- Auto-hide timeout
- Ollama endpoint
- Ollama model name

---

## 8. Suggested Project Structure

```text
SpellingPopupAssistant/
│
├── SpellingPopupAssistantApp.swift
├── AppDelegate.swift
│
├── Core/
│   ├── Models/
│   │   ├── CorrectionResult.swift
│   │   ├── WordCorrection.swift
│   │   └── AppSettings.swift
│   │
│   ├── Engines/
│   │   ├── CorrectionEngine.swift
│   │   ├── MacOSSpellCheckerEngine.swift
│   │   └── OllamaCorrectionEngine.swift
│   │
│   ├── Accessibility/
│   │   ├── AccessibilityManager.swift
│   │   ├── SelectionMonitor.swift
│   │   └── TextReplacementService.swift
│   │
│   ├── Popup/
│   │   ├── CorrectionPopupController.swift
│   │   └── PopupPositioningService.swift
│   │
│   └── Utilities/
│       ├── ClipboardService.swift
│       ├── Debouncer.swift
│       └── Logger.swift
│
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarController.swift
│   │
│   ├── Popup/
│   │   └── CorrectionPopupView.swift
│   │
│   ├── Settings/
│   │   └── SettingsView.swift
│   │
│   └── Permission/
│       └── AccessibilityPermissionView.swift
│
├── Resources/
│   └── Assets.xcassets
│
└── Tests/
    ├── SpellCheckerEngineTests.swift
    ├── OllamaEngineTests.swift
    └── CorrectionResultTests.swift
```

---

## 9. Non-Goals for Version 1

Do not build these in the first version:

- Full grammar rewriting
- Live correction while typing
- Browser extension
- Microsoft Word add-in
- Team collaboration
- Cloud sync
- User account system
- Subscription/payment system
- Mac App Store distribution

---

## 10. Version Roadmap

### Version 1

- Menu bar app
- Accessibility permission screen
- Selected text detection
- Local spell checking
- Floating popup
- Copy corrected text
- Replace selected text where supported
- Misspelled word count

### Version 2

- Ollama local AI correction
- Settings screen
- Better popup positioning
- Correction list display
- Keyboard shortcuts

### Version 3

- Arabic support
- Custom dictionary
- App-specific enable/disable rules
- Auto-replace common mistakes
- Correction history stored locally

---

## 11. Success Criteria

The app is successful when:

- User highlights a misspelled word or sentence.
- Popup appears automatically.
- Corrected text is displayed.
- Number of misspelled words is shown.
- User can copy or replace the corrected text.
- App works in common apps:
  - Safari
  - Chrome
  - Notes
  - Mail
  - Outlook
  - Teams
  - VS Code text fields where Accessibility permits
- App does not crash in unsupported apps.
- App clearly explains when replacement is not supported.
