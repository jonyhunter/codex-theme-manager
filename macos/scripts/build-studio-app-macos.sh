#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

OUTPUT="${1:-$HOME/Desktop/Codex 皮肤管理器.app}"
SOURCE_ROOT="$PROJECT_ROOT/studio"
REPOSITORY_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
PLIST="$PROJECT_ROOT/studio/Info.plist"
ICON="$PROJECT_ROOT/assets/DreamSkinAppIcon.icns"
CLI_SOURCE="$PROJECT_ROOT/tools/ThemeCreatorCLI.swift"
SKILL_SOURCE="$REPOSITORY_ROOT/skill/codex-skin-theme-creator"
TEMPORARY="${OUTPUT}.building.$$"

[ -f "$SOURCE_ROOT/DreamSkinStudio.swift" ] || fail "Theme Studio source is missing: $SOURCE_ROOT"
[ -f "$PLIST" ] || fail "Theme Studio Info.plist is missing: $PLIST"
[ -s "$ICON" ] || fail "Theme Studio icon is missing: $ICON"
[ -f "$CLI_SOURCE" ] || fail "Theme creator CLI source is missing: $CLI_SOURCE"
[ -f "$SKILL_SOURCE/SKILL.md" ] || fail "Theme creator Skill is missing: $SKILL_SOURCE"
/usr/bin/xcrun --find swiftc >/dev/null 2>&1 || fail "Swift compiler is required to build Codex 皮肤管理器."

/bin/rm -rf "$TEMPORARY"
/bin/mkdir -p \
  "$TEMPORARY/Contents/MacOS" \
  "$TEMPORARY/Contents/Resources/Tools" \
  "$TEMPORARY/Contents/Resources/Skills"
/usr/bin/xcrun swiftc \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework ImageIO \
  -framework CryptoKit \
  "$SOURCE_ROOT"/*.swift \
  -o "$TEMPORARY/Contents/MacOS/CodexSkinManager"
/usr/bin/xcrun swiftc \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework ImageIO \
  "$SOURCE_ROOT/ThemeModels.swift" \
  "$SOURCE_ROOT/ThemePackageService.swift" \
  "$CLI_SOURCE" \
  -o "$TEMPORARY/Contents/Resources/Tools/CodexThemeCreator"
/bin/cp "$PLIST" "$TEMPORARY/Contents/Info.plist"
/bin/cp "$ICON" "$TEMPORARY/Contents/Resources/DreamSkinAppIcon.icns"
/usr/bin/ditto \
  "$SKILL_SOURCE" \
  "$TEMPORARY/Contents/Resources/Skills/codex-skin-theme-creator"
/bin/chmod 755 "$TEMPORARY/Contents/Resources/Tools/CodexThemeCreator"
/usr/bin/codesign --force --deep --sign - "$TEMPORARY" >/dev/null

/bin/rm -rf "$OUTPUT"
/bin/mv "$TEMPORARY" "$OUTPUT"
printf 'Built Codex 皮肤管理器 at %s.\n' "$OUTPUT"
