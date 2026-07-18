#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

PORT=9341
CREATE_LAUNCHERS="true"
LAUNCH_AFTER_INSTALL="true"
IN_PLACE="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --no-launchers) CREATE_LAUNCHERS="false"; shift ;;
    --no-launch) LAUNCH_AFTER_INSTALL="false"; shift ;;
    --in-place) IN_PLACE="true"; shift ;;
    *) fail "Unknown installer argument: $1" ;;
  esac
done
case "$PORT" in ''|*[!0-9]*) fail "Invalid port: $PORT" ;; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || fail "Port must be between 1024 and 65535."

deploy_project() {
  local temporary="$INSTALL_ROOT.installing.$$"
  local previous="$INSTALL_ROOT.previous.$$"
  local repository_skill="$(cd "$PROJECT_ROOT/.." && pwd -P)/skill/codex-skin-theme-creator"
  /bin/rm -rf "$temporary"
  /bin/mkdir -p "$temporary"
  /usr/bin/rsync -a \
    --exclude '.git/' \
    --exclude '.DS_Store' \
    --exclude 'release/' \
    --exclude 'runtime/' \
    "$PROJECT_ROOT/" "$temporary/"
  if [ ! -f "$temporary/skill/codex-skin-theme-creator/SKILL.md" ] &&
    [ -f "$repository_skill/SKILL.md" ]; then
    /bin/mkdir -p "$temporary/skill"
    /usr/bin/ditto "$repository_skill" "$temporary/skill/codex-skin-theme-creator"
  fi
  /bin/chmod 700 "$temporary"/*.command "$temporary"/scripts/*.sh 2>/dev/null || true
  if [ -e "$INSTALL_ROOT" ]; then /bin/mv "$INSTALL_ROOT" "$previous"; fi
  if ! /bin/mv "$temporary" "$INSTALL_ROOT"; then
    [ -e "$previous" ] && /bin/mv "$previous" "$INSTALL_ROOT"
    fail "Could not install the project at $INSTALL_ROOT"
  fi
  /bin/rm -rf "$previous"
}

if [ "$IN_PLACE" = "false" ] && [ "$PROJECT_ROOT" != "$INSTALL_ROOT" ]; then
  /bin/mkdir -p "$(dirname "$INSTALL_ROOT")"
  deploy_project
  install_args=(--in-place --port "$PORT")
  [ "$CREATE_LAUNCHERS" = "true" ] || install_args+=(--no-launchers)
  [ "$LAUNCH_AFTER_INSTALL" = "true" ] || install_args+=(--no-launch)
  exec "$INSTALL_ROOT/scripts/install-dream-skin-macos.sh" "${install_args[@]}"
fi

discover_codex_app
require_macos_runtime
ensure_state_root
codex_is_running && fail "Close Codex before installation so config.toml cannot be rewritten while the app is saving it."
seed_bundled_presets
if [ ! -f "$THEME_DIR/theme.json" ]; then
  "$SCRIPT_DIR/switch-theme-macos.sh" --id preset-gothic-void-crusade --no-apply >/dev/null
fi
[ -f "$CONFIG_PATH" ] || fail "Codex config not found: $CONFIG_PATH. Launch Codex once, close it, and rerun the installer."
"$SCRIPT_DIR/install-builtin-themes-macos.sh"
"$SCRIPT_DIR/install-theme-creator-skill-macos.sh"
if [ ! -f "$THEME_DIR/theme.json" ]; then
  "$SCRIPT_DIR/switch-theme-macos.sh" --id miku-dream-skin --no-apply
fi
"$NODE" "$INJECTOR" --check-payload --theme-dir "$THEME_DIR" >/dev/null
"$NODE" "$SCRIPT_DIR/theme-config.mjs" install "$CONFIG_PATH" "$THEME_BACKUP_PATH"

# A graphical upgrade intentionally avoids relaunching Codex. If a verified
# live session already exists, replace the old injector and hot-apply the newly
# installed payload so the running renderer matches this release immediately.
if [ "$LAUNCH_AFTER_INSTALL" = "false" ] && [ -f "$STATE_PATH" ]; then
  saved_injector_pid="$(state_field injectorPid 2>/dev/null || true)"
  saved_port="$(state_field port 2>/dev/null || true)"
  if [ -n "$saved_injector_pid" ] && [ "$saved_injector_pid" != "0" ] && [ -n "$saved_port" ]; then
    hot_reapply_theme "$saved_port" 8000 || true
  fi
fi

shell_quote() {
  "$NODE" -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"
}

write_launcher() {
  local target="$1"
  local command="$2"
  if [ -e "$target" ] && ! /usr/bin/grep -q '^# CodexDreamSkinStudio launcher$' "$target" 2>/dev/null; then
    fail "Refusing to overwrite an unrelated Desktop file: $target"
  fi
  /usr/bin/printf '%s\n' \
    '#!/bin/bash' \
    '# CodexDreamSkinStudio launcher' \
    'set -e' \
    "$command" > "$target"
  /bin/chmod 700 "$target"
}

if [ "$CREATE_LAUNCHERS" = "true" ]; then
  /bin/mkdir -p "$HOME/Desktop"
  start_script="$(shell_quote "$SCRIPT_DIR/start-dream-skin-macos.sh")"
  customize_script="$(shell_quote "$SCRIPT_DIR/customize-theme-macos.sh")"
  verify_script="$(shell_quote "$SCRIPT_DIR/verify-dream-skin-macos.sh")"
  restore_script="$(shell_quote "$SCRIPT_DIR/restore-dream-skin-macos.sh")"
  screenshot="$(shell_quote "$HOME/Desktop/Codex 皮肤管理器验证.png")"
  write_launcher "$HOME/Desktop/Codex 皮肤管理器.command" "exec $start_script --port $PORT --prompt-restart"
  write_launcher "$HOME/Desktop/Codex 皮肤管理器 - 自定义.command" "exec $customize_script"
  write_launcher "$HOME/Desktop/Codex 皮肤管理器 - 验证.command" "$verify_script --screenshot $screenshot && /usr/bin/open $screenshot"
  write_launcher "$HOME/Desktop/Codex 皮肤管理器 - 恢复.command" "exec $restore_script --restore-base-theme --restart-codex"
  if /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    /bin/rm -rf "$HOME/Desktop/Codex Dream Skin.app"
    "$SCRIPT_DIR/build-studio-app-macos.sh" "$HOME/Desktop/Codex 皮肤管理器.app"
  else
    printf 'Swift compiler not found; skipped the visual Theme Studio app.\n' >&2
  fi
fi

printf 'Codex 皮肤管理器 %s installed at %s for Codex %s using its signed Node.js %s.\n' \
  "$SKIN_VERSION" "$PROJECT_ROOT" "$CODEX_VERSION" "$NODE_VERSION"
printf 'Use the Desktop launchers to customize, start, verify, or restore the official appearance.\n'
printf 'Bundled presets are ready in your theme library — pick one from the menu bar (已保存的主题) or switch-theme.\n'

if [ "$LAUNCH_AFTER_INSTALL" = "true" ]; then
  "$SCRIPT_DIR/start-dream-skin-macos.sh" --port "$PORT" --prompt-restart
fi
