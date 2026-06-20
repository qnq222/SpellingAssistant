# Spelling Popup Assistant

Spelling Popup Assistant is a native macOS menu bar utility for checking selected text on demand. It reads the current selection with Accessibility APIs, corrects spelling and grammar through an offline embedded LanguageTool engine by default, and shows a compact PopClip-style popup with replacement actions.

## Features

- Menu bar utility with no Dock icon.
- System-wide selected text reading through macOS Accessibility.
- Manual correction from the menu bar with `Check Selected Text Now`.
- Configurable global keyboard shortcut, enabled by default as `Control + Option + C`.
- Offline spelling and grammar correction through embedded LanguageTool.
- Lazy LanguageTool startup, random localhost port selection, and automatic shutdown after 60 seconds of inactivity.
- Small Java runtime bundled with the app through `jlink`.
- Popup issue summary with spelling, grammar, and total issue counts.
- Correction details such as `recieved -> received`.
- Popup actions for `Replace`, `Copy`, and `Ignore`.
- Replacement by temporary clipboard paste, then clipboard restoration.
- Configurable maximum selected text length.
- Toggles for showing corrections on single words and longer selections.
- Configurable popup auto-hide timeout.
- Optional `LanguageTool + GECToR` mode for local sentence-level grammar improvements.
- Optional Gemini cloud AI mode for deeper proofreading when explicitly selected.
- macOS `NSSpellChecker` fallback when a selected engine fails.
- Accessibility permission window with shortcuts to System Settings.
- Memory pressure handling that immediately stops the embedded LanguageTool process.

## Requirements

- macOS 13 Ventura or later.
- Xcode with the macOS SDK.
- Accessibility permission for reading and replacing selected text.
- Embedded LanguageTool payload for offline release packaging.
- Optional local GECToR helper files for `LanguageTool + GECToR` mode.
- Optional Gemini API key for `Cloud AI via Gemini` mode.

## Usage

1. Open `SpellingPopupAssistant.xcodeproj` in Xcode.
2. Build and run the `SpellingPopupAssistant` scheme.
3. Grant Accessibility access when prompted:
   `System Settings > Privacy & Security > Accessibility > Spelling Popup Assistant`.
4. Select text in any supported app.
5. Press `Control + Option + C`, or choose `Check Selected Text Now` from the menu bar app.
6. Use the popup to replace, copy, or ignore the corrected text.

The app checks text only when you invoke the shortcut or menu item. It does not continuously send selected text to a correction engine.

## Correction Modes

### Embedded LanguageTool

This is the default mode. It runs offline inside the app bundle and checks English text with LanguageTool's local HTTP server:

```text
SpellingPopupAssistant.app/Contents/Resources/
|-- LanguageTool
|-- JavaRuntime
`-- Dictionaries
```

LanguageTool is lazy-loaded on the first correction request, reused while active, and stopped after 60 seconds of inactivity. See [docs/EmbeddedLanguageTool.md](docs/EmbeddedLanguageTool.md) for architecture and packaging details.

### LanguageTool + GECToR

This mode runs embedded LanguageTool first, applies several high-confidence local grammar rules, then asks a local GECToR helper for sentence-level improvements. The default helper endpoint is:

```text
POST http://127.0.0.1:8765/correct
Content-Type: application/json

{ "text": "He go to school yesterday." }
```

If the helper is unavailable, times out, returns invalid JSON, or proposes a risky negation-changing edit, the app keeps the LanguageTool/local result.

See [scripts/gector_helper/README.md](scripts/gector_helper/README.md) for setup, model download, and run instructions.

### Cloud AI via Gemini

Gemini support is optional and sends selected text to Google's Gemini API only when this mode is selected. Configure the API key and model in Settings. The default model value is `gemini-3.1-flash-lite`.

If Gemini is not configured or the request fails, the app logs the error and falls back to the macOS spell checker.

## Settings

The Settings window includes:

- Enable or disable correction popups.
- Choose the correction mode.
- Set the maximum selected text length from 50 to 5000 characters.
- Show or hide popups for single words.
- Show or hide popups for sentence/paragraph selections.
- Enable or disable popup auto-hide.
- Set auto-hide timeout from 2 to 30 seconds.
- Enable shortcut checking.
- Record a custom keyboard shortcut.
- Configure the local GECToR endpoint and timeout.
- Configure the Gemini API key and model.

## Packaging LanguageTool

Stage a LanguageTool distribution and a JDK locally, then run:

```bash
scripts/package_languagetool.sh /path/to/LanguageTool /path/to/jdk
```

The script writes:

```text
Vendor/EmbeddedLanguageTool/
|-- LanguageTool
|-- JavaRuntime
`-- Dictionaries
```

The Xcode build phase copies those directories into the app bundle when present. The payload directories are intentionally ignored by Git because they are large generated release artifacts.

## Privacy

The app does not collect text.

- Embedded LanguageTool is the default and runs fully offline inside the app bundle.
- The macOS spell checker fallback runs locally.
- `LanguageTool + GECToR` sends selected text only to the configured local helper endpoint.
- Gemini sends selected text to Google's API only when `Cloud AI via Gemini` is selected.

## Tests

Run unit tests from Xcode, or with:

```bash
xcodebuild test -scheme SpellingPopupAssistant -destination 'platform=macOS'
```

## Documentation

- [docs/Features.md](docs/Features.md) lists the user-facing feature set.
- [docs/EmbeddedLanguageTool.md](docs/EmbeddedLanguageTool.md) explains the offline engine architecture.
- [scripts/gector_helper/README.md](scripts/gector_helper/README.md) explains the optional local grammar helper.
- [spelling_popup_assistant_plan.md](spelling_popup_assistant_plan.md) tracks the product and architecture plan.
- [spelling_popup_assistant_codex_implementation.md](spelling_popup_assistant_codex_implementation.md) summarizes the implemented code structure.
