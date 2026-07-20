# Codex 皮肤管理器（macOS）

Unofficial macOS theme studio for the **official Codex Desktop** app.

Turn an image you like into a Codex theme: a dedicated home banner, a low-noise task background, and frosted content layers — while **keeping native sidebar, suggestion cards, project picker, task content, menus, and composer** fully interactive.

This project injects through **local loopback CDP**. It does **not** modify the official `.app`, `app.asar`, or code signature.

> Not affiliated with OpenAI. Codex is a trademark of its respective owners.

## Requirements

- macOS
- Official Codex Desktop installed and launched at least once (`~/.codex/config.toml` exists)
- No global Node.js install required (uses Codex’s signed bundled Node after validation)

## Quick start (from this repo)

```bash
# 1) Optional static checks (needs Codex.app present for bundled Node path)
./tests/run-tests.sh

# 2) Install to the stable path and create Desktop launchers
./scripts/install-dream-skin-macos.sh --no-launch

# 3) Open the graphical manager to create, import, or switch themes
open "$HOME/Applications/Codex 皮肤管理器.app"

# 4) Start / re-apply, verify, or restore via Desktop:
#    Codex Dream Skin.command
#    Codex Dream Skin - Customize.command
#    Codex Dream Skin - Verify.command
#    Codex Dream Skin - Restore.command

# 5) Close the main window to keep the native manager in the menu bar.
#    Use the “皮肤” menu to inspect status, switch themes, check updates,
#    or reopen the window.
```

Install location after step 2:

| Item | Path |
| --- | --- |
| Engine | `~/.codex/codex-dream-skin-studio` |
| State / logs / user images | `~/Library/Application Support/CodexDreamSkinStudio` |
| Theme backup | under Application Support (`theme-backup.json`) |

## Customer ZIP (optional packaging)

To build the “double-click install” folder layout for non-git users:

```bash
./scripts/build-client-release.sh "$HOME/Desktop/Codex 主题编辑器.zip"
```

That ZIP contains a visible installer plus a hidden `.codex-dream-skin-studio` engine. Do not ship only CSS/images.

## One-click DMG

Build a macOS disk image containing the graphical one-click installer:

```bash
./scripts/build-installer-dmg-macos.sh "$HOME/Desktop/Codex 皮肤管理器 1.7.2.dmg"
```

Open the DMG, launch `安装 Codex 皮肤管理器.app`, and click `一键安装`. It deploys the engine under `~/.codex`, installs the prebuilt manager under `~/Applications`, creates a Desktop entry, and opens the manager.

## Signed in-app updates

The manager checks the signed stable feed once per day and also exposes a manual
check in the toolbar and the `皮肤` menu. It verifies Ed25519 metadata, HTTPS,
declared size, and SHA-256 before mounting the DMG. The bundled installer then
runs in automatic-update mode, replaces the engine and manager, preserves user
themes and state, and reopens the new version. The separately signed theme
catalog can install compatible schema 2 themes without a full app release.

## How it works (security boundary)

1. Discover `com.openai.codex` and validate signature / Team ID / arch / bundled Node.
2. Start Codex via user `launchd` with CDP bound to `127.0.0.1` only.
3. Accept the debug port only when it belongs to Codex (or a legitimate child).
4. Inject only into expected `app://` renderer targets.
5. Keep a small injector alive across reloads and route changes.
6. Restore stops the injector only when PID, path, and start time match the recorded job.

CDP is powerful and unauthenticated on loopback. Prefer Restore when you are done theming.

## Create and import themes

The manager provides a native creation sheet with image selection, horizontal crop focus, metadata, appearance, and palette controls. It writes `2400x800` `background.png`, `1200x400` `preview.png`, and schema 2 `theme.json`.

The installer also deploys the bundled `codex-skin-theme-creator` Skill. The manager's Integration page shows whether it is current and can reinstall it. Themes created by the Skill enter the same user library and are detected while the manager is open.

The import action validates the three-file package before copying it into the theme library. See `../docs/theme-format.md` for exact fields and limits.

## Image guidelines

- PNG / JPEG / HEIC / TIFF / WebP (macOS readable)
- Source ≤ 50 MB; prepared file ≤ 16 MB
- Any macOS-readable aspect ratio is accepted; Studio center-crops it to a `2400x800` 3:1 `background.png`
- Studio also creates the required `1200x400` `preview.png`
- Keep the left side relatively calm for native home titles
- The same image is reused for home, task, plugin, and skill pages
- Image is banner + background only — never a full-window fake UI overlay

See `../docs/theme-format.md` for the schema 2 theme-pack contract.

CLI example:

```bash
~/.codex/codex-dream-skin-studio/scripts/customize-theme-macos.sh \
  --image "/path/to/image.png" \
  --name "My theme" \
  --accent "#7cff46" \
  --secondary "#36d7e8" \
  --highlight "#642a8c"
```

Reset to the bundled abstract demo:

```bash
~/.codex/codex-dream-skin-studio/scripts/customize-theme-macos.sh --reset-demo
```

## License

MIT — see `LICENSE`. Additional notices in `NOTICE.md` (trademarks, demo asset, runtime Node).

## Sponsors

Thanks to **[passion8.cc](https://passion8.cc/register?aff=TuPe)** for sponsoring this project.

<p align="center">
  <a href="https://passion8.cc/register?aff=TuPe">
    <img src="../docs/images/sponsor-passion8.png" alt="Passion8" height="96">
  </a>
</p>

<p align="center">
  <a href="https://passion8.cc/register?aff=TuPe"><strong>Passion8｜感谢 passion8.cc 赞助本项目</strong></a><br>
  AI API 中转站，支持 Codex / Claude Code / Grok 等工具接入。主题与 API 配置互相独立。
</p>

## What this is not

- Not an OpenAI product and not a fork of Codex source
- Not a way to patch or rebrand the official binary
- This folder is the macOS build; the Windows installer and theme manager live under `../windows/`
- Not an API proxy: theming does not change model providers or API keys

If you use a third-party API relay, configure it separately — keep theme install and API config as two explicit steps.
