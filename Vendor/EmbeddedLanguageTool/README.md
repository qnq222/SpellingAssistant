# Embedded LanguageTool Staging

This directory is the local staging area for the generated embedded LanguageTool payload.

Run:

```bash
scripts/package_languagetool.sh /path/to/LanguageTool /path/to/jdk
```

The generated payload layout is:

```text
Vendor/EmbeddedLanguageTool/
|-- LanguageTool
|   |-- languagetool-server.jar
|   `-- *.jar
|-- JavaRuntime
|   `-- bin/java
`-- Dictionaries
```

The Xcode build phase copies those directories into:

```text
SpellingPopupAssistant.app/Contents/Resources/
```

Only this README should be tracked. The generated `LanguageTool`, `JavaRuntime`, and `Dictionaries` directories are ignored by Git because they are large release artifacts that should be recreated locally or in release packaging.
