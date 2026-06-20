#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
  printf '%s\n' "Usage: scripts/package_languagetool.sh /path/to/languagetool /path/to/jdk [output-dir]"
  exit 64
fi

LANGUAGETOOL_SOURCE="$1"
JDK_HOME="$2"
OUTPUT_DIR="${3:-Vendor/EmbeddedLanguageTool}"
JLINK="$JDK_HOME/bin/jlink"
JDEPS="$JDK_HOME/bin/jdeps"

if [ ! -x "$JLINK" ]; then
  printf '%s\n' "jlink was not found at $JLINK"
  exit 66
fi

if [ ! -x "$JDEPS" ]; then
  printf '%s\n' "jdeps was not found at $JDEPS"
  exit 66
fi

if [ ! -f "$LANGUAGETOOL_SOURCE/languagetool-server.jar" ]; then
  printf '%s\n' "languagetool-server.jar was not found in $LANGUAGETOOL_SOURCE"
  exit 66
fi

rm -rf "$OUTPUT_DIR/LanguageTool" "$OUTPUT_DIR/JavaRuntime" "$OUTPUT_DIR/Dictionaries"
mkdir -p "$OUTPUT_DIR/LanguageTool" "$OUTPUT_DIR/Dictionaries"

cp "$LANGUAGETOOL_SOURCE/languagetool-server.jar" "$OUTPUT_DIR/LanguageTool/"
find "$LANGUAGETOOL_SOURCE" -maxdepth 1 -name '*.jar' -type f -exec cp '{}' "$OUTPUT_DIR/LanguageTool/" ';'

if [ -d "$LANGUAGETOOL_SOURCE/org" ]; then
  rsync -a --include '*/' --include '*en*' --include '*en-US*' --include 'hunspell/***' --exclude '*' "$LANGUAGETOOL_SOURCE/org" "$OUTPUT_DIR/Dictionaries/"
fi

MODULES="$("$JDEPS" --ignore-missing-deps --multi-release 17 --print-module-deps "$OUTPUT_DIR"/LanguageTool/*.jar 2>/dev/null || true)"
if [ -z "$MODULES" ]; then
  MODULES="java.base,java.desktop,java.logging,java.management,java.naming,java.net.http,java.scripting,java.xml,jdk.crypto.ec"
fi

"$JLINK" \
  --add-modules "$MODULES" \
  --strip-debug \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --output "$OUTPUT_DIR/JavaRuntime"

cat > "$OUTPUT_DIR/README.md" <<'README'
# Embedded LanguageTool Payload

This directory is copied into `SpellingPopupAssistant.app/Contents/Resources` by the Xcode build phase.

Expected runtime layout:

- `LanguageTool/languagetool-server.jar`
- `LanguageTool/*.jar`
- `JavaRuntime/bin/java`
- `Dictionaries/`
README

printf '%s\n' "Packaged embedded LanguageTool payload at $OUTPUT_DIR"
