# Features

This document is the user-facing feature inventory for Spelling Popup Assistant.

## App Experience

- Runs as a macOS menu bar utility.
- Uses `NSApplication.ActivationPolicy.accessory` so it does not require a Dock icon.
- Provides menu items for enable/disable, correction mode selection, manual checking, Settings, Accessibility permission status, and Quit.
- Shows a temporary `Correcting...` menu bar state while a correction is running.

## Selection Checking

- Checks selected text on demand through the menu item or configured global shortcut.
- Reads selected text through macOS Accessibility.
- Falls back to a clipboard-based selected-text read path when direct Accessibility text extraction is unavailable.
- Requires Accessibility permission before reading or replacing text.
- Ignores empty selections.
- Ignores selections longer than the configured maximum length.
- Prevents rapid duplicate processing of the same selection and correction mode within 500 ms.
- Supports independent toggles for single-word selections and sentence/paragraph selections.

## Keyboard Shortcut

- Shortcut checking is enabled by default.
- The default shortcut is `Control + Option + C`.
- Users can record a custom shortcut in Settings.
- Escape cancels shortcut recording.
- Shortcut settings are persisted in `UserDefaults`.

## Popup

- Uses a floating non-activating `NSPanel`.
- Positions near the mouse pointer as a reliable cross-app fallback.
- Resizes within compact bounds for the correction content.
- Shows corrected text, spelling count, grammar count, total issue count, and issue details.
- Supports `Replace`, `Copy`, and `Ignore`.
- Auto-hides after the configured timeout when enabled.
- Auto-hides quickly after copy or replacement failure fallback.
- Shows `No corrections found.` when the selected engine returns no edits.

## Replacement

- Replaces the current selection by temporarily copying corrected text and sending Command-V.
- Restores the previous clipboard contents after a short delay when possible.
- Copies the corrected text if replacement fails, so the user still has the correction available.

## Correction Engines

- `Embedded LanguageTool` is the default offline engine.
- `LanguageTool + GECToR` uses LanguageTool first, then local grammar improvements.
- `Cloud AI via Gemini` is optional and requires an API key.
- `MacOSSpellCheckerEngine` is used as a fallback when the active engine fails.

## Embedded LanguageTool

- Bundles LanguageTool, a reduced Java runtime, and dictionaries into the app resources.
- Starts only when a correction is requested.
- Runs on a random localhost port.
- Checks `en-US` text through `/v2/check`.
- Disables style, colloquialism, and redundancy categories for faster popup corrections.
- Tracks spelling and grammar issues separately.
- Applies non-overlapping replacements in reverse order to preserve text offsets.
- Stops after 60 seconds of inactivity.
- Stops immediately on memory pressure.

## LanguageTool + GECToR

- Uses embedded LanguageTool as the base pass.
- Supplements spelling with the local macOS spell checker when needed.
- Applies high-confidence local grammar rules for common agreement, verb-form, and punctuation issues.
- Sends sentence-like text to a local GECToR helper endpoint.
- Merges GECToR issues into the popup details.
- Rejects GECToR suggestions that remove negation markers.
- Keeps the local LanguageTool result if the helper is unavailable, times out, or returns invalid data.
- The app starts the helper script on launch and stops it on quit.

## Gemini

- Sends text to Gemini only when the user selects `Cloud AI via Gemini`.
- Stores API key and model setting locally in `UserDefaults`.
- Requests JSON-only correction output.
- Falls back to the macOS spell checker on missing key, network failure, or parse failure.

## Privacy And Resource Behavior

- No text collection is implemented.
- Default correction is offline.
- Local helper mode sends text only to the configured local endpoint.
- Cloud mode is opt-in.
- LanguageTool is not launched at app startup.
- The embedded engine is shut down when idle or under memory pressure.
