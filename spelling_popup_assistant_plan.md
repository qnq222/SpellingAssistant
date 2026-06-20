# Spelling Popup Assistant Product And Architecture Plan

## Goal

Build a native macOS menu bar utility that corrects selected text on demand and presents the result in a compact PopClip-style popup.

The app should:

- Work system-wide where macOS Accessibility allows selected text access.
- Keep the default correction path offline and private.
- Avoid continuous background correction.
- Provide fast manual invocation through a menu item and global shortcut.
- Let users replace, copy, or ignore corrected text.
- Support optional local and cloud engines for stronger grammar correction.

## Target Platform

- Platform: macOS 13 Ventura or later.
- IDE: Xcode.
- Language: Swift.
- UI: SwiftUI plus AppKit where needed.
- App type: menu bar utility.
- Distribution target: local/private use first.

## User Flow

1. User selects a word, sentence, or paragraph in any supported app.
2. User presses the configured shortcut or chooses `Check Selected Text Now`.
3. The app reads the selected text through Accessibility, with clipboard fallback if needed.
4. The active correction engine returns corrected text and issue details.
5. A floating popup appears near the mouse pointer.
6. User chooses `Replace`, `Copy`, or `Ignore`.

Example selected text:

```text
I recieved the mesage from the adminstrator.
```

Example corrected text:

```text
I received the message from the administrator.
```

## Implemented Feature Set

- Menu bar app with no required Dock icon.
- Accessibility permission detection and setup window.
- Manual correction from menu bar.
- Configurable global shortcut, defaulting to `Control + Option + C`.
- Configurable app enabled state.
- Configurable correction mode.
- Configurable selected text length limit.
- Configurable single-word and sentence/paragraph popup behavior.
- Configurable popup auto-hide and timeout.
- Floating non-activating correction popup.
- Popup issue counts for spelling, grammar, and total issues.
- Popup issue details.
- Replace/copy/ignore actions.
- Clipboard-preserving text replacement.
- Offline embedded LanguageTool default engine.
- Optional local `LanguageTool + GECToR` engine.
- Optional cloud Gemini engine.
- macOS spell checker fallback.
- Memory pressure shutdown for embedded LanguageTool.

## Correction Modes

### Embedded LanguageTool

The default engine bundles:

- LanguageTool server JARs.
- A reduced Java runtime created with `jlink`.
- English dictionaries/resources.

Runtime behavior:

- Starts on first correction request.
- Runs on a random localhost port.
- Checks `en-US`.
- Disables style-heavy categories for speed.
- Stops after 60 seconds of inactivity.
- Stops immediately on memory pressure.

### LanguageTool + GECToR

This mode layers local correction:

1. Embedded LanguageTool.
2. macOS spell checker supplement.
3. High-confidence local grammar rules.
4. Local GECToR helper HTTP request for sentence-like text.

The app starts the helper script on launch and stops it on quit. If the helper is unavailable or unsafe, the app keeps the local LanguageTool result.

### Gemini

This mode is opt-in. It sends selected text to Google's Gemini API only when selected and configured with an API key. Failures fall back to the local macOS spell checker.

## Privacy Requirements

- Do not collect user text.
- Do not send text to a cloud service by default.
- Keep embedded LanguageTool as the default offline mode.
- Send text to a local helper only when `LanguageTool + GECToR` is selected.
- Send text to Gemini only when `Cloud AI via Gemini` is selected.

## Core Components

### AppDelegate

- Sets accessory app policy.
- Installs menu bar UI.
- Wires correction callbacks.
- Starts hotkey handling.
- Starts memory pressure observation.
- Starts and stops helper processes.
- Manages Settings and permission windows.

### MenuBarController

- Owns the status item.
- Displays app enabled state.
- Displays correction mode menu.
- Exposes manual correction.
- Opens Settings and permission flows.
- Shows a correcting state while work is active.

### AccessibilityManager

- Checks and requests Accessibility permission.
- Opens macOS Accessibility settings.
- Reads selected text.
- Provides a clipboard fallback selection reader.

### SelectionMonitor

- Validates settings and permission.
- Reads selected text on manual invocation.
- Ignores empty, too-long, disabled, or disallowed selection types.
- Suppresses rapid duplicate requests.
- Chooses the active correction engine.
- Falls back to the macOS spell checker on engine failure.

### CorrectionPopupController

- Hosts the SwiftUI popup in an `NSPanel`.
- Positions near the mouse pointer.
- Schedules auto-hide.
- Handles replace, copy, and ignore actions.

### TextReplacementService

- Saves clipboard contents.
- Copies corrected text.
- Sends Command-V.
- Restores clipboard contents.

### EngineManager

- Starts embedded LanguageTool lazily.
- Reuses the process while active.
- Stops it after idle timeout or memory pressure.

## Packaging Plan

LanguageTool release payloads should be staged with:

```bash
scripts/package_languagetool.sh /path/to/LanguageTool /path/to/jdk
```

Generated payload directories are ignored by Git:

- `Vendor/EmbeddedLanguageTool/LanguageTool/`
- `Vendor/EmbeddedLanguageTool/JavaRuntime/`
- `Vendor/EmbeddedLanguageTool/Dictionaries/`

The checked-in project should keep scripts and documentation, not large generated runtimes or model files.

## Test Plan

Run:

```bash
xcodebuild test -scheme SpellingPopupAssistant -destination 'platform=macOS'
```

Important coverage areas:

- Correction result counts and flags.
- Keyboard shortcut recording/matching.
- LanguageTool response parsing.
- Engine manager lifecycle and idle shutdown.
- macOS spell checker fallback behavior.
- GECToR merge/fallback behavior.
