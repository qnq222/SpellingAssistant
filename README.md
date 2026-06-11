# Spelling Popup Assistant

Spelling Popup Assistant is a native macOS menu bar utility that watches for selected text, checks spelling locally, and shows a compact PopClip-style correction popup.

## Requirements

- macOS 13 Ventura or later
- Xcode
- Accessibility permission for system-wide selection reading and replacement
- Optional: Ollama for local AI correction

## Usage

1. Open `SpellingPopupAssistant.xcodeproj` in Xcode.
2. Build and run the `SpellingPopupAssistant` scheme.
3. Grant Accessibility access when prompted:
   `System Settings > Privacy & Security > Accessibility > Spelling Popup Assistant`.
4. Select misspelled text in any supported app.
5. Use the popup to replace, copy, or ignore the corrected text.

Apps that expose selected text through macOS Accessibility, such as Chrome, can show the popup automatically. For apps that do not expose selection reliably, such as Codex, choose `Check Selected Text Now` from the menu bar app.

The manual shortcut fallback is off by default. You can enable it in Settings with `Enable manual shortcut fallback`, then record your own shortcut under `Manual check shortcut` by pressing the exact key combination you want to use.

## Correction And Grammar Modes

The default engine is `NSSpellChecker`, which runs locally and offline. Optional Ollama support can be enabled in Settings with:

- Endpoint: `http://localhost:11434`
- Model: `qwen2.5:7b`

Turn on `Check grammar with local AI` in Settings to correct grammar as well as spelling. Grammar checking uses the configured local Ollama server. If Ollama is unavailable, the app logs the error and falls back to the local macOS spell checker.

## Privacy

The app does not collect text and does not send text to cloud services. Local spell checking is the default. Ollama and grammar mode send selected text only to the local Ollama server configured in Settings.

## Tests

Run the unit tests from Xcode or with:

```bash
xcodebuild test -scheme SpellingPopupAssistant -destination 'platform=macOS'
```
