# Embedded LanguageTool Architecture

Spelling Popup Assistant uses embedded LanguageTool as its default offline spelling and grammar engine. The user does not install Java, LanguageTool, or a background service.

## App Bundle Layout

Release builds copy the staged payload into:

```text
SpellingPopupAssistant.app
`-- Contents
    |-- MacOS
    `-- Resources
        |-- LanguageTool
        |   |-- languagetool-server.jar
        |   `-- *.jar
        |-- JavaRuntime
        |   `-- bin/java
        `-- Dictionaries
```

Runtime code looks up `JavaRuntime/bin/java` and `LanguageTool/languagetool-server.jar` from `Bundle.main.resourceURL`.

## Runtime Lifecycle

`EngineManager` owns the embedded engine lifecycle:

1. The user invokes correction for the current selection from the menu bar or keyboard shortcut.
2. `SelectionMonitor` validates app state, Accessibility permission, selection length, popup type settings, and duplicate-processing debounce.
3. `LanguageToolCorrectionEngine` calls `EngineManager`.
4. `EngineManager` starts `EmbeddedLanguageToolService` only if it is not already running.
5. The service starts the bundled Java runtime on a random localhost port and waits for `/v2/languages`.
6. Text is checked with `/v2/check` using `en-US`.
7. The response is converted into corrected text, spelling issues, grammar issues, total issue count, and issue details.
8. After 60 seconds of inactivity, `EngineManager` stops the LanguageTool process.

The app does not start Java, LanguageTool, or dictionaries on launch.

## Request Strategy

The `/v2/check` request uses:

- `language=en-US`
- `preferredVariants=en-US`
- `level=default`
- `enabledOnly=false`
- `disabledCategories=STYLE,COLLOQUIALISMS,REDUNDANCY`

Style-heavy categories are disabled to keep popup corrections focused and fast.

## Correction Strategy

`EmbeddedLanguageToolService`:

- Drops invalid matches and matches without replacement suggestions.
- Uses non-overlapping matches to avoid conflicting edits.
- Classifies issues as spelling or grammar based on LanguageTool issue type and category.
- Picks the first non-empty replacement that differs from the original text.
- Applies replacements from the end of the string toward the start so LanguageTool offsets remain valid.
- Exposes LanguageTool process RSS after analysis for resource visibility.

## Resource Strategy

- No continuous correction engine loop.
- No LanguageTool process at app launch.
- Random localhost port for each service start.
- Java launched with `-Xms32m`, `-Xmx160m`, and Serial GC.
- Idle shutdown after 60 seconds.
- Immediate shutdown on memory pressure.

## Packaging With jlink

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

The Xcode build phase copies those directories into `Contents/Resources` when present.

## Build Checklist

1. Run the packaging script before creating a release archive.
2. Build `SpellingPopupAssistant`.
3. Confirm the built app contains:

```bash
ls SpellingPopupAssistant.app/Contents/Resources/LanguageTool
ls SpellingPopupAssistant.app/Contents/Resources/JavaRuntime/bin/java
```

4. Run the app.
5. Trigger the first correction and confirm LanguageTool starts.
6. Wait at least 60 seconds and confirm the idle timeout stops the process.

## Optional Engine Modes

`LanguageTool + GECToR` still starts with this embedded LanguageTool pass, then runs local spelling/grammar supplements and the configured local GECToR helper.

`Cloud AI via Gemini` bypasses LanguageTool for the primary result, but falls back to the macOS spell checker when Gemini fails.
