# Spelling Popup Assistant Implementation

This document summarizes the current Swift implementation of Spelling Popup Assistant.

## App Role

Spelling Popup Assistant is a native macOS menu bar app that checks selected text on demand. It uses SwiftUI for views and AppKit for menu bar, Accessibility, global shortcut, and floating popup behavior.

The app currently supports:

- Offline embedded LanguageTool correction.
- Optional local `LanguageTool + GECToR` grammar improvement.
- Optional cloud correction through Gemini.
- Fallback correction through `NSSpellChecker`.
- Popup actions for replace, copy, and ignore.

## Startup Flow

`AppDelegate` performs app setup:

1. Sets the app activation policy to `.accessory`.
2. Installs `MenuBarController`.
3. Configures `SelectionMonitor` callbacks.
4. Starts global hotkey monitoring.
5. Starts memory pressure observation.
6. Starts the local GECToR helper script.
7. Checks Accessibility permission.
8. Shows the permission window and opens the system prompt when permission is missing.

On termination, the app stops the selection monitor, hotkey controller, memory pressure observer, GECToR helper process, and embedded LanguageTool service.

## Menu Bar

`MenuBarController` owns the status item and menu.

Menu features:

- Shows the app name.
- Shows a temporary correcting state while a request is active.
- Toggles correction popups on or off.
- Selects correction mode.
- Runs `Check Selected Text Now`.
- Opens Settings.
- Checks Accessibility permission.
- Quits the app.

The menu bar icon switches to an hourglass and title while correction is running.

## Settings

`AppSettings` persists user preferences in `UserDefaults`.

Current settings:

- `isEnabled`
- `correctionMode`
- `maxSelectedTextLength`
- `showPopupForSingleWords`
- `showPopupForSentences`
- `isAutoHideEnabled`
- `autoHideTimeout`
- `gectorHelperEndpoint`
- `gectorRequestTimeout`
- `geminiAPIKey`
- `geminiModel`
- `isManualShortcutEnabled`
- `checkSelectionShortcut`

`SettingsView` provides controls for all of those settings, including a custom shortcut recorder.

## Selection Flow

`SelectionMonitor` checks selected text only when the user invokes the global shortcut or menu item.

Processing rules:

- App must be enabled.
- Accessibility permission must be trusted.
- Direct Accessibility selected text is preferred.
- Clipboard fallback is used when direct selected text is unavailable.
- Empty selections are ignored.
- Selections longer than the configured maximum are ignored.
- Single-word and sentence/paragraph settings decide whether a popup is allowed.
- Duplicate processing of the same text and mode is suppressed within 500 ms.

After validation, `SelectionMonitor` runs the active correction engine asynchronously and reports results to the popup controller.

## Correction Result Model

`CorrectionResult` contains:

- `originalText`
- `correctedText`
- `spellingIssueCount`
- `grammarIssueCount`
- `misspelledWordCount`
- `corrections`
- `issues`

`totalIssueCount` is computed from spelling and grammar counts. `hasCorrections` returns true when the text changed or any issue/correction is present.

`CorrectionIssue` distinguishes spelling and grammar details for the popup.

## Correction Engines

All correction engines conform to:

```swift
protocol CorrectionEngine {
    func correct(text: String) async throws -> CorrectionResult
}
```

### Embedded LanguageTool

`LanguageToolCorrectionEngine` delegates to `EngineManager`, which owns the lazy service lifecycle.

`EmbeddedLanguageToolService`:

- Locates bundled Java and LanguageTool resources.
- Starts `languagetool-server.jar` on a random localhost port.
- Waits for `/v2/languages`.
- Checks text with `/v2/check`.
- Disables style, colloquialism, and redundancy categories.
- Converts LanguageTool matches into corrected text and issue details.
- Tracks process resource usage.

### Engine Manager

`EngineManager`:

- Starts the embedded service on first use.
- Reuses it while active.
- Schedules shutdown after 60 seconds of inactivity.
- Exposes immediate shutdown for memory pressure handling.

### LanguageTool + GECToR

`LanguageToolGECToRCorrectionEngine`:

- Runs LanguageTool first.
- Supplements spelling with `MacOSSpellCheckerEngine` when useful.
- Applies high-confidence local grammar rules.
- Sends sentence-like corrected text to `GECToRHTTPClient`.
- Merges helper issues and corrections into the result.
- Rejects helper suggestions that remove negation markers.
- Returns the local result when the helper fails.

`GECToRHelperProcessManager` starts `scripts/gector_helper/run_roberta_helper.sh` on app launch, passes host and port from the configured endpoint, logs output, and stops the helper on quit.

### Gemini

`GeminiCorrectionEngine`:

- Requires a configured API key.
- Calls the Gemini `generateContent` endpoint with JSON response mode.
- Requests spelling, grammar, tense, agreement, article, punctuation, word-form, and clarity fixes.
- Parses the returned JSON into `CorrectionResult`.

If Gemini fails, `SelectionMonitor` falls back to `MacOSSpellCheckerEngine`.

### macOS Spell Checker

`MacOSSpellCheckerEngine` uses `NSSpellChecker` as a local fallback. It is used when the active engine throws.

## Popup

`CorrectionPopupController` creates a floating non-activating `NSPanel` backed by `CorrectionPopupView`.

Popup behavior:

- Floats above normal windows.
- Joins all spaces and full-screen auxiliary contexts.
- Positions near the mouse pointer.
- Fits content between compact minimum and maximum sizes.
- Auto-hides based on settings.
- Hides immediately when ignored.
- Hides after successful replacement.
- Copies corrected text and briefly auto-hides when copy is pressed.

## Text Replacement

`TextReplacementService` replaces selected text by:

1. Verifying Accessibility permission.
2. Taking a clipboard snapshot.
3. Copying corrected text.
4. Sending Command-V through `CGEvent`.
5. Waiting briefly.
6. Restoring the previous clipboard contents.

If paste fails, the popup controller leaves the corrected text copied for the user.

## Permissions

`AccessibilityManager` handles:

- Trust checks.
- Permission requests.
- Opening Accessibility settings.
- Direct selected text extraction.
- Clipboard fallback extraction.

`AccessibilityPermissionView` gives the user a visible recovery path when permission is missing.

## Resource Handling

`MemoryPressureObserver` stops the embedded LanguageTool engine immediately when macOS reports memory pressure.

The default LanguageTool engine also shuts itself down after idle timeout, so the Java process is not permanently resident.

## Tests

The test suite currently covers:

- Correction result behavior.
- macOS spell checker behavior.
- Embedded LanguageTool response parsing/service behavior.
- Engine manager lifecycle.
- Keyboard shortcut setting behavior.

Run tests with:

```bash
xcodebuild test -scheme SpellingPopupAssistant -destination 'platform=macOS'
```
