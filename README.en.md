# Codex Skin Manager

<p align="center">
  <a href="./README.md">中文</a> · <strong>English</strong>
</p>

<p align="center">
  A cross-platform theme manager for Codex Desktop.<br>
  Switch, create, import, restore, and generate themes through a bundled Codex Skill.
</p>

<p align="center">
  <a href="https://github.com/houyuhang915-sudo/Codex-Skin-Manager/releases">Downloads</a>
  ·
  <a href="./docs/theme-format.md">Theme format</a>
  ·
  <a href="./docs/platforms.md">Platforms</a>
</p>

> Current version: `1.5.0`. This is a community project and is not affiliated with OpenAI.

## Manager UI

<table>
  <tr>
    <th width="60%">Theme library and one-click switching</th>
    <th width="40%">Built-in theme creator</th>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/manager-library.png" alt="Codex Skin Manager theme library and one-click switching"></td>
    <td><img src="docs/images/showcase/manager-create-theme.png" alt="Codex Skin Manager theme creation dialog"></td>
  </tr>
</table>

## Theme Showcase

<table>
  <tr>
    <th width="50%">Home</th>
    <th width="50%">Chat</th>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/cartethyia-home.png" alt="Cartethyia theme home page"></td>
    <td><img src="docs/images/showcase/cartethyia-chat.png" alt="Cartethyia theme chat page"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Cartethyia · Sea Breeze</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/miku-home.png" alt="Hatsune Miku light theme home page"></td>
    <td><img src="docs/images/showcase/miku-chat.png" alt="Hatsune Miku light theme chat page"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Hatsune Miku · Light</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/cyrene-home.png" alt="Cyrene theme home page"></td>
    <td><img src="docs/images/showcase/cyrene-chat.png" alt="Cyrene theme chat page"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Cyrene · Star Sea</strong></td>
  </tr>
</table>

The screenshots come from real Codex pages. The capture utility hides conversation content, task names, project names, and private sidebar information.

## Features

- Native macOS and Windows theme managers
- 14 bundled appearances with the stock Codex theme pinned first
- One-click theme switching with synchronized manager state
- In-app theme creation from local images
- Horizontal crop focus, light/dark appearance, and palette controls
- Strict schema 2 theme-folder import
- Theme creation through the bundled `codex-skin-theme-creator` Skill
- Automatic library refresh when a theme is created
- Shared styling for home, chat, settings, plugins, skills, notifications, and composer
- Pet overlay preserved across all theme switches
- One-click restoration of the stock Codex appearance

## Download And Install

Download `v1.5.0` from [Releases](https://github.com/houyuhang915-sudo/Codex-Skin-Manager/releases).

### macOS

Download `Codex-Skin-Manager-1.5.0.dmg`, open it, then launch `安装 Codex 皮肤管理器.app` and click the install button.

Installed locations:

```text
App: ~/Applications/Codex 皮肤管理器.app
Engine: ~/.codex/codex-dream-skin-studio
Themes: ~/Library/Application Support/CodexDreamSkinStudio/themes
```

Requirements: macOS 14 or later and the official Codex desktop app.

### Windows

Run `Codex-Skin-Manager-Setup-1.5.0.exe`. Codex may remain open during setup. Launch `Codex 皮肤管理器` from the Start menu and use **One-click switch**.

Installed locations:

```text
Engine: %LOCALAPPDATA%\CodexDreamSkin\engine-1.5.0
Themes: %LOCALAPPDATA%\CodexDreamSkin\themes
State: %LOCALAPPDATA%\CodexDreamSkin
```

Requirements: Windows 10/11 and the Microsoft Store Codex app.

## Use A Theme

1. Open Codex Skin Manager.
2. Select a theme preview.
3. Click the one-click switch action.
4. Check the current theme, connection status, and result in the manager.
5. Select the pinned stock Codex theme to restore the official appearance.

Themes change the visual layer only. Conversations, settings, projects, and composer controls remain native Codex UI.

## Create A Theme

Open **Create Theme** in the manager:

1. Select a PNG, JPEG, WebP, or HEIC image.
2. Adjust horizontal focus.
3. Enter the name, ID, author, description, and category.
4. Choose light or dark appearance.
5. Set the accent, secondary, and highlight colors.
6. Create the theme.

The manager produces:

```text
my-theme/
├── theme.json
├── background.png   # 2400x800
└── preview.png      # 1200x400
```

The new theme appears in the library immediately.

## Codex Skill

The installers deploy `codex-skin-theme-creator` automatically. A standalone `codex-skin-theme-creator-1.5.0.zip` is also available in the Release.

Default locations:

```text
macOS: ${CODEX_HOME:-~/.codex}/skills/codex-skin-theme-creator
Windows: %CODEX_HOME%\skills\codex-skin-theme-creator
```

Example:

```text
Create a light Codex theme from this image and name it "Aqua Workspace".
```

The Skill can generate or process artwork, produce the schema 2 manifest, and atomically install the finished theme into the user library. See the [Skill workflow](./skill/codex-skin-theme-creator/SKILL.md).

## Import Contract

A theme folder contains exactly:

```text
theme-id/
├── theme.json
├── background.png
└── preview.png
```

Core requirements:

- `schemaVersion` is `2`
- IDs use lowercase letters, numbers, and hyphens
- Both images are real PNG files with an exact 3:1 ratio
- Recommended sizes are `2400x800` and `1200x400`
- `avatarOverlay` is `show`
- `appearance` is `auto`, `light`, or `dark`
- Symbolic links, escaping paths, and legacy `taskImage` fields are rejected

See [docs/theme-format.md](./docs/theme-format.md) for all fields and a complete manifest example.

## Bundled Themes

The library includes the stock Codex appearance, Salary Cat, Hatsune Miku, Nailong, Cyrene, Blue Archive Ensemble, Cartethyia, Furina, Firefly, Saber, Asuka, Rem, People's AI, and KUN Black Gold Stage.

## Runtime Model

```text
Codex Skin Manager
  ├─ manages bundled and user themes
  ├─ starts or connects to local Codex
  ├─ injects the selected theme through 127.0.0.1 CDP
  └─ verifies the applied state
                |
                v
Native Codex sidebar, chat, settings, and composer remain active
```

The project does not modify the official `.app`, `app.asar`, WindowsApps files, or official code signatures. CDP is restricted to the local loopback interface.

## Build From Source

```bash
git clone https://github.com/houyuhang915-sudo/Codex-Skin-Manager.git
cd Codex-Skin-Manager
```

macOS:

```bash
macos/tests/run-tests.sh
macos/scripts/build-studio-app-macos.sh \
  "$HOME/Desktop/Codex 皮肤管理器.app"
macos/scripts/build-installer-dmg-macos.sh \
  "$HOME/Desktop/Codex-Skin-Manager-1.5.0.dmg"
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File windows\tests\run-tests.ps1
powershell -ExecutionPolicy Bypass -STA -File windows\scripts\theme-manager.ps1
```

Installer:

```bash
brew install nsis
windows/scripts/build-installer-windows.sh
```

## Repository Layout

```text
macos/                         macOS manager, installer, runtime, and themes
windows/                       Windows manager, installer, runtime, and themes
skill/codex-skin-theme-creator Codex theme creator Skill
docs/images/showcase/          Sanitized README screenshots
docs/theme-format.md           Schema 2 theme format
docs/platforms.md              Platform paths and capability matrix
script/                        Build and documentation utilities
```

## Verification

The release passes macOS build and regression checks, Windows PowerShell 5.1 and PowerShell 7 tests, cross-platform Node.js renderer tests, GitHub Actions static checks, DMG verification, NSIS format inspection, and Skill validation.

Use `Codex-Skin-Manager-1.5.0-SHA256.txt` from the Release to verify downloaded files.

## License

Code is released under the [MIT License](./LICENSE). Character themes demonstrate the theme system; confirm the applicable image, character-name, and trademark conditions before redistribution or commercial use.

## Attribution

This project references the theme-injection approach from [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) and independently develops the cross-platform manager, theme library, installers, creation tools, and Codex Skill.
