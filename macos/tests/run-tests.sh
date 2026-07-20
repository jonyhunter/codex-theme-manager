#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPOSITORY_ROOT="$(cd "$ROOT/.." && pwd -P)"
NODE="${NODE:-/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node}"
[ -x "$NODE" ] || { printf 'Codex bundled Node.js was not found: %s\n' "$NODE" >&2; exit 1; }

while IFS= read -r file; do /bin/bash -n "$file"; done < <(
  /usr/bin/find "$ROOT" -type f \( -name '*.sh' -o -name '*.command' \) \
    ! -path '*/release/*' -print
)
while IFS= read -r file; do "$NODE" --check "$file" >/dev/null; done < <(
  /usr/bin/find "$ROOT/scripts" "$ROOT/assets" -type f \( -name '*.mjs' -o -name '*.js' \) -print
)
"$NODE" --check \
  "$REPOSITORY_ROOT/skill/codex-skin-theme-creator/scripts/create-theme.mjs" >/dev/null
"$NODE" --check "$REPOSITORY_ROOT/script/update-feed.mjs" >/dev/null
"$NODE" "$REPOSITORY_ROOT/script/update-feed.mjs" validate >/dev/null
[ -f "$REPOSITORY_ROOT/skill/codex-skin-theme-creator/SKILL.md" ]
[ -f "$REPOSITORY_ROOT/skill/codex-skin-theme-creator/agents/openai.yaml" ]

if /usr/bin/grep -R -n -E 'dream-skin-skin|DREAM_SKIN_SKIN|1\.0\.0-rc2' \
  "$ROOT/scripts" "$ROOT/assets" >/dev/null; then
  printf 'Legacy release-candidate identifiers remain in runtime files.\n' >&2
  exit 1
fi
if /usr/bin/grep -R -n -E '(writeFile|rename|copyFile|rm).*app\.asar' "$ROOT/scripts" >/dev/null; then
  printf 'A runtime script appears to mutate app.asar.\n' >&2
  exit 1
fi

"$NODE" "$ROOT/scripts/injector.mjs" --check-payload >/dev/null

TMP="$(/usr/bin/mktemp -d /tmp/codex-dream-skin-tests.XXXXXX)"
trap '/bin/rm -rf "$TMP"' EXIT
/bin/mkdir -p "$TMP/theme"
/bin/cp "$ROOT/assets/portal-hero.png" "$TMP/theme/background.png"
/bin/cp "$ROOT/assets/portal-hero.png" "$TMP/theme/preview.png"
"$NODE" "$ROOT/scripts/write-theme.mjs" custom --output-dir "$TMP/theme" \
  --image background.png --name '测试主题' --tagline '测试口号' --quote 'TEST' \
  --style 'custom-test' --appearance light \
  --accent '#11aa55' --secondary '#22bbcc' --highlight '#663399' >/dev/null
PAYLOAD_JSON="$("$NODE" "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$TMP/theme")"
"$NODE" -e '
  const value = JSON.parse(process.argv[1]);
  if (!value.pass || value.themeName !== "测试主题" || value.imageBytes < 1 ||
      value.themeStyle !== "custom-test" || value.avatarOverlay !== "show" ||
      value.appearance !== "light") process.exit(1);
' "$PAYLOAD_JSON"
"$NODE" "$ROOT/scripts/write-theme.mjs" reset-demo --output-dir "$TMP/theme" >/dev/null
[ ! -e "$TMP/theme" ]

THEME_IDS=(codex-default salary-cat-office miku-dream-skin nailong-sunshine cyrene-star-rail blue-archive-ensemble cartethyia-wuthering-waves furina-genshin firefly-star-rail saber-fate asuka-eva rem-rezero red-horizon black-gold-stage)
for theme_id in "${THEME_IDS[@]}"; do
  theme_dir="$ROOT/themes/$theme_id"
  [ -s "$theme_dir/background.png" ]
  [ -s "$theme_dir/preview.png" ]
  [ -s "$theme_dir/theme.json" ]
  background_width="$(/usr/bin/sips -g pixelWidth "$theme_dir/background.png" 2>/dev/null | /usr/bin/awk '/pixelWidth/{print $2}')"
  background_height="$(/usr/bin/sips -g pixelHeight "$theme_dir/background.png" 2>/dev/null | /usr/bin/awk '/pixelHeight/{print $2}')"
  preview_width="$(/usr/bin/sips -g pixelWidth "$theme_dir/preview.png" 2>/dev/null | /usr/bin/awk '/pixelWidth/{print $2}')"
  preview_height="$(/usr/bin/sips -g pixelHeight "$theme_dir/preview.png" 2>/dev/null | /usr/bin/awk '/pixelHeight/{print $2}')"
  [ "$background_width" -eq $((background_height * 3)) ]
  [ "$preview_width" -eq $((preview_height * 3)) ]
  PAYLOAD_JSON="$("$NODE" "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$theme_dir")"
  "$NODE" -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const [payloadText, manifestPath, expectedID] = process.argv.slice(1);
    const payload = JSON.parse(payloadText);
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    if (!payload.pass || payload.imageBytes < 1 || manifest.schemaVersion !== 2) process.exit(1);
    if (manifest.id !== expectedID || payload.themeStyle !== manifest.style) process.exit(1);
    if (!["auto", "light", "dark"].includes(manifest.appearance)) process.exit(1);
    if (manifest.avatarOverlay !== "show" || payload.avatarOverlay !== "show") process.exit(1);
    if (manifest.image !== "background.png" || manifest.preview !== "preview.png") process.exit(1);
    if ("taskImage" in manifest) process.exit(1);
    if (manifest.id === "miku-dream-skin" &&
        (manifest.appearance !== "auto" || !manifest.colorsLight || !manifest.colorsDark ||
         !payload.hasColorsLight || !payload.hasColorsDark)) process.exit(1);
  ' "$PAYLOAD_JSON" "$theme_dir/theme.json" "$theme_id"
done
[ -s "$ROOT/themes/black-gold-stage/identity-reference.png" ]

TEST_HOME="$TMP/home"
/bin/mkdir -p "$TEST_HOME"
HOME="$TEST_HOME" "$ROOT/scripts/install-builtin-themes-macos.sh" >/dev/null
for theme_id in "${THEME_IDS[@]}"; do
  /usr/bin/cmp -s \
    "$ROOT/themes/$theme_id/theme.json" \
    "$TEST_HOME/Library/Application Support/CodexDreamSkinStudio/themes/$theme_id/theme.json"
done

MENU_OUTPUT="$(HOME="$TEST_HOME" CODEX_DREAM_SKIN_ENGINE="$ROOT" "$ROOT/menubar/codex_dream_skin.10s.sh")"
default_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- Codex 默认原版' | /usr/bin/cut -d: -f1)"
salary_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 月薪喵打卡' | /usr/bin/cut -d: -f1)"
miku_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 初音未来' | /usr/bin/cut -d: -f1)"
nailong_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 奶龙晴空' | /usr/bin/cut -d: -f1)"
cyrene_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 昔涟 · 星海回响' | /usr/bin/cut -d: -f1)"
blue_archive_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 蔚蓝档案 · 青春合影' | /usr/bin/cut -d: -f1)"
cartethyia_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 卡提希娅 · 风栖海境' | /usr/bin/cut -d: -f1)"
furina_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 芙宁娜 · 水色剧场' | /usr/bin/cut -d: -f1)"
firefly_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 流萤 · 星海微光' | /usr/bin/cut -d: -f1)"
saber_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- Saber · 誓约胜利' | /usr/bin/cut -d: -f1)"
asuka_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 明日香 · 红色黄昏' | /usr/bin/cut -d: -f1)"
rem_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- 蕾姆 · 冰蓝夜庭' | /usr/bin/cut -d: -f1)"
people_ai_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- OpenAI 是人民的 AI' | /usr/bin/cut -d: -f1)"
black_gold_line="$(printf '%s\n' "$MENU_OUTPUT" | /usr/bin/grep -n -- '-- KUN 黑金舞台' | /usr/bin/cut -d: -f1)"
[ "$default_line" -lt "$salary_line" ]
[ "$salary_line" -lt "$miku_line" ]
[ "$miku_line" -lt "$nailong_line" ]
[ "$nailong_line" -lt "$cyrene_line" ]
[ "$cyrene_line" -lt "$blue_archive_line" ]
[ "$blue_archive_line" -lt "$cartethyia_line" ]
[ "$cartethyia_line" -lt "$furina_line" ]
[ "$furina_line" -lt "$firefly_line" ]
[ "$firefly_line" -lt "$saber_line" ]
[ "$saber_line" -lt "$asuka_line" ]
[ "$asuka_line" -lt "$rem_line" ]
[ "$rem_line" -lt "$people_ai_line" ]
[ "$people_ai_line" -lt "$black_gold_line" ]

/usr/bin/grep -q 'data-dream-theme-style' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'markers\.library' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'markers\.settings' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'dream-skin-settings-sidebar' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'dream-skin-settings-shell' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'data-dream-view="settings"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--color-background-panel' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'dream-skin-settings-sidebar' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'dream-skin-settings-shell.*rounded-2xl' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'red-horizon' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'red-horizon.*app-shell-main-content-top-fade' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'red-horizon.*data-sonner-toaster' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'black-gold-stage' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'salary-cat-office' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'nailong-sunshine' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'cyrene-star-rail' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'blue-archive-ensemble.*app-shell-main-content-top-fade' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'blue-archive-ensemble.*data-sonner-toaster' "$ROOT/assets/dream-skin.css"
for theme_style in cartethyia-wuthering-waves furina-genshin firefly-star-rail saber-fate asuka-eva rem-rezero; do
  /usr/bin/grep -q "$theme_style" "$ROOT/assets/dream-skin.css"
done
/usr/bin/grep -q 'Character scene collection' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q ') main.main-surface .app-shell-main-content-top-fade' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q ') \[data-sonner-toaster\] \[data-sonner-toast\]' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'var(--dream-skin-art) 72% center / cover no-repeat' "$ROOT/assets/dream-skin.css"
if /usr/bin/grep -q -- '--dream-skin-character-task-focus' "$ROOT/assets/dream-skin.css" ||
  /usr/bin/grep -q 'main\.main-surface:not(\.dream-skin-home-shell) \.thread-scroll-container' "$ROOT/assets/dream-skin.css"; then
  printf 'A character theme has a task-only focus or reading-wash override.\n' >&2
  exit 1
fi
/usr/bin/grep -q 'schema 2 themes must use background.png' "$ROOT/scripts/write-theme.mjs"
if /usr/bin/grep -R -n '"taskImage"' "$ROOT/themes" "$ROOT/assets" "$ROOT/scripts" >/dev/null; then
  printf 'The retired taskImage field remains in the schema 2 implementation.\n' >&2
  exit 1
fi
/usr/bin/grep -q 'vertical-scroll-fade-mask' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'app-shell-main-content-top-fade' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q '#codex-dream-skin-chrome:not(.dream-skin-home-shell) .dream-skin-status' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-shell="dark".*miku-stage' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'THEME.colorsDark' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'mode.*original' "$ROOT/themes/codex-default/theme.json"
/usr/bin/grep -q 'session: "active"' "$ROOT/scripts/common-macos.sh"
/usr/bin/grep -q 'process.exit(process.exitCode' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'MenuBarExtra' "$ROOT/studio/DreamSkinStudio.swift"
/usr/bin/grep -q 'Text("皮肤")' "$ROOT/studio/DreamSkinStudio.swift"
/usr/bin/grep -q 'UpdateToolbarButton' "$ROOT/studio/DreamSkinStudio.swift"
/usr/bin/grep -q 'fetchSignedJSON' "$ROOT/studio/UpdateService.swift"
/usr/bin/grep -q 'Curve25519.Signing.PublicKey' "$ROOT/studio/UpdateService.swift"
/usr/bin/grep -q -- '--automatic-update' "$ROOT/installer/DreamSkinInstaller.swift"
/usr/bin/grep -q 'CODEX_WAS_RUNNING' "$ROOT/scripts/install-dream-skin-macos.sh"
if /usr/bin/grep -q 'seed_bundled_presets\|preset-gothic-void-crusade' \
  "$ROOT/scripts/install-dream-skin-macos.sh"; then
  printf 'The macOS installer still references the retired preset seeding path.\n' >&2
  exit 1
fi
/usr/bin/grep -q 'Window("Codex 皮肤管理器", id: "manager")' "$ROOT/studio/DreamSkinStudio.swift"
/usr/bin/grep -q 'refreshMonitoredStateIfNeeded' "$ROOT/studio/DreamSkinStudio.swift"
/usr/bin/grep -q 'openWindow(id: "manager")' "$ROOT/studio/DreamSkinStudio.swift"
if /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  /usr/bin/xcrun swiftc -parse-as-library -typecheck \
    -framework SwiftUI -framework AppKit -framework ImageIO "$ROOT/studio"/*.swift
  /usr/bin/xcrun swiftc \
    -framework AppKit -framework ImageIO \
    "$ROOT/studio/ThemePackageService.swift" \
    "$ROOT/tests/ThemePackageServiceTests.swift" \
    -o "$TMP/theme-package-tests"
  "$TMP/theme-package-tests" \
    "$ROOT/themes/rem-rezero/background.png" \
    "$TMP/theme-package-service"
  /usr/bin/xcrun swiftc -parse-as-library -typecheck \
    -framework SwiftUI -framework AppKit "$ROOT/installer/DreamSkinInstaller.swift"
  /usr/bin/xcrun swiftc -parse-as-library -framework CryptoKit \
    "$ROOT/tests/UpdateSignatureTests.swift" \
    -o "$TMP/update-signature-tests"
  "$TMP/update-signature-tests" "$REPOSITORY_ROOT/updates"
  /usr/bin/xcrun swiftc -parse-as-library \
    "$ROOT/studio/UpdateMetadata.swift" \
    "$ROOT/tests/UpdateMetadataTests.swift" \
    -o "$TMP/update-metadata-tests"
  "$TMP/update-metadata-tests" "$REPOSITORY_ROOT/updates"
  "$ROOT/scripts/build-studio-app-macos.sh" "$TMP/Codex 皮肤管理器.app" >/dev/null
  [ -s "$TMP/Codex 皮肤管理器.app/Contents/Resources/DreamSkinAppIcon.icns" ]
  [ -x "$TMP/Codex 皮肤管理器.app/Contents/MacOS/CodexSkinManager" ]
  [ -x "$TMP/Codex 皮肤管理器.app/Contents/Resources/Tools/CodexThemeCreator" ]
  [ -f "$TMP/Codex 皮肤管理器.app/Contents/Resources/Skills/codex-skin-theme-creator/SKILL.md" ]
  CODEX_SKIN_THEME_CLI="$TMP/Codex 皮肤管理器.app/Contents/Resources/Tools/CodexThemeCreator" \
    "$NODE" "$REPOSITORY_ROOT/skill/codex-skin-theme-creator/scripts/create-theme.mjs" \
      --image "$ROOT/themes/rem-rezero/background.png" \
      --id skill-created-test \
      --name 'Skill 创建测试' \
      --appearance light \
      --focus 58 \
      --themes-root "$TMP/skill-themes" > "$TMP/skill-result.json"
  "$NODE" -e '
    const fs = require("fs");
    const result = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const manifest = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    if (result.status !== "installed" || result.themeId !== "skill-created-test") process.exit(1);
    if (manifest.schemaVersion !== 2 || manifest.avatarOverlay !== "show") process.exit(1);
  ' "$TMP/skill-result.json" "$TMP/skill-themes/skill-created-test/theme.json"
  [ "$(/usr/bin/plutil -extract CFBundleIconFile raw "$TMP/Codex 皮肤管理器.app/Contents/Info.plist")" = "DreamSkinAppIcon.icns" ]
  [ "$(/usr/bin/plutil -extract CFBundleName raw "$TMP/Codex 皮肤管理器.app/Contents/Info.plist")" = "Codex 皮肤管理器" ]
  [ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$TMP/Codex 皮肤管理器.app/Contents/Info.plist")" = "1.7.2" ]
fi

CONFIG="$TMP/config.toml"
BACKUP="$TMP/theme-backup.json"
/usr/bin/printf '%s\n' \
  'model = "gpt-5"' \
  '' \
  '[desktop]' \
  'appearanceTheme = "system"' \
  'appearanceDarkCodeThemeId = "vscode-dark"' \
  'keepMe = true' > "$CONFIG"
/bin/cp "$CONFIG" "$TMP/original.toml"
"$NODE" "$ROOT/scripts/theme-config.mjs" install "$CONFIG" "$BACKUP" >/dev/null
/usr/bin/grep -q 'appearanceTheme = "system"' "$CONFIG"
"$NODE" "$ROOT/scripts/theme-config.mjs" restore "$CONFIG" "$BACKUP" >/dev/null
/usr/bin/cmp -s "$CONFIG" "$TMP/original.toml"

/usr/bin/env -u HOME /bin/bash -c '. "$1/scripts/common-macos.sh"; [ -n "$HOME" ] && [ "$SKIN_VERSION" = "1.7.2" ]' _ "$ROOT"
"$ROOT/scripts/doctor-macos.sh" >/dev/null

printf 'PASS: syntax, payload, theme library, Studio build, config round-trip, HOME recovery, signature, and doctor checks.\n'
