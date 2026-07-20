# Codex 皮肤管理器

<p align="center">
  <img src="macos/assets/DreamSkinAppIcon.png" width="128" height="128" alt="Codex 皮肤管理器图标">
</p>

<p align="center">
  <strong>中文</strong> · <a href="./README.en.md">English</a>
</p>

<p align="center">
  面向 Codex 桌面端的跨平台主题管理工具。<br>
  支持主题切换、图片创建、主题导入、原版恢复，以及通过 Codex Skill 自动生成主题。
</p>

<p align="center">
  <a href="https://github.com/jonyhunter/codex-theme-manager/releases">下载安装包</a>
  ·
  <a href="./docs/theme-format.md">主题格式</a>
  ·
  <a href="./docs/platforms.md">平台说明</a>
</p>

> 当前版本：`1.7.2`。本项目为社区工具，与 OpenAI 无隶属关系。

## 软件界面

<table>
  <tr>
    <th width="60%">主题库与一键切换</th>
    <th width="40%">内置主题创建器</th>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/manager-library.png" alt="Codex 皮肤管理器主题库与一键切换界面"></td>
    <td><img src="docs/images/showcase/manager-create-theme.png" alt="Codex 皮肤管理器创建主题界面"></td>
  </tr>
</table>

## 主题展示

<table>
  <tr>
    <th width="50%">初始页</th>
    <th width="50%">对话页</th>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/cartethyia-home.png" alt="卡提希娅主题初始页"></td>
    <td><img src="docs/images/showcase/cartethyia-chat.png" alt="卡提希娅主题对话页"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>卡提希娅 · 风栖海境</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/miku-home.png" alt="初音未来跟随系统主题的浅色初始页效果"></td>
    <td><img src="docs/images/showcase/miku-chat.png" alt="初音未来跟随系统主题的浅色对话页效果"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>初音未来 · 跟随系统（浅色效果）</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/showcase/cyrene-home.png" alt="昔涟主题初始页"></td>
    <td><img src="docs/images/showcase/cyrene-chat.png" alt="昔涟主题对话页"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>昔涟 · 星海回响</strong></td>
  </tr>
</table>

展示图来自真实 Codex 页面。截图脚本会隐藏对话正文、任务名称、项目名称和侧栏隐私信息。

## 主要功能

- macOS 与 Windows 图形主题管理器
- macOS 菜单栏与 Windows 系统托盘后台常驻，可快速切换并查看实时状态
- 软件内自动检查、下载、校验并安装新版本
- 在线主题目录独立更新，新主题无需下载完整安装包
- 内置 14 套外观，Codex 默认原版固定置顶
- 一键切换主题并自动同步当前状态
- 选择本地图片创建新主题
- 调整横向焦点、浅色或暗色界面和主题配色
- 导入标准 schema 2 主题文件夹
- 通过 `codex-skin-theme-creator` Skill 对话创建主题
- 新主题自动加入管理器，无需重启软件
- 首页、对话、设置、插件、技能、通知和输入器统一适配
- 切换主题时保持 Codex 宠物层显示
- 一键停止主题引擎并恢复 Codex 原版外观

## 三分钟开始使用

1. 从 [Releases](https://github.com/jonyhunter/codex-theme-manager/releases) 下载当前平台的安装包。
2. 完成安装并启动“Codex 皮肤管理器”；首次启动会部署主题引擎、内置主题和创建主题 Skill。
3. 保持 Codex 打开，在主题库选择一张预览图，然后点击“一键切换”。
4. 等待管理器显示“已应用”，Codex 当前窗口会自动刷新主题。
5. 关闭管理器主窗口后，macOS 可从顶部“皮肤”菜单、Windows 可从系统托盘继续快速切换。

第一次切换时，如果 Codex 尚未启动，管理器会尝试启动它。连接状态表示管理器是否已经连上本机 Codex 的主题运行时，不影响主题库浏览、创建或导入。

## 下载与安装

前往 [Releases](https://github.com/jonyhunter/codex-theme-manager/releases) 下载 `v1.7.2`。

### macOS

下载：

```text
Codex-Skin-Manager-1.7.2.dmg
```

安装步骤：

1. 打开 DMG。
2. 双击“安装 Codex 皮肤管理器.app”。
3. 点击“一键安装”。
4. 安装完成后从“应用程序”或自动打开的管理器中选择主题。

管理器关闭主窗口后仍驻留在 macOS 顶部菜单栏，入口显示为“调色盘图标 + 皮肤”；可查看当前主题与连接状态、快速切换主题或重新打开完整窗口。

默认路径：

```text
应用：~/Applications/Codex 皮肤管理器.app
引擎：~/.codex/codex-dream-skin-studio
主题：~/Library/Application Support/CodexDreamSkinStudio/themes
```

系统要求：macOS 14 或更新版本、官方 Codex 桌面端。

### Windows

下载：

```text
Codex-Skin-Manager-Setup-1.7.2.exe
```

安装步骤：

1. 运行安装程序，Codex 可以保持打开。
2. 完成安装后，从开始菜单启动“Codex 皮肤管理器”。
3. 选择主题并点击“一键切换”。
4. 当前 Codex 窗口会直接应用主题；必要时管理器会提示重新打开窗口。

管理器关闭主窗口后会隐藏到 Windows 系统托盘。双击托盘图标可恢复窗口，右键菜单可查看实时状态、快速切换主题或退出管理器。

默认路径：

```text
引擎：%LOCALAPPDATA%\CodexDreamSkin\engine-1.7.2
主题：%LOCALAPPDATA%\CodexDreamSkin\themes
状态：%LOCALAPPDATA%\CodexDreamSkin
```

系统要求：Windows 10/11、Microsoft Store 版 Codex。

## 后台常驻与快速切换

安装后先启动一次“Codex 皮肤管理器”，常驻入口才会出现。

| 平台 | 常驻入口 | 主要操作 |
|---|---|---|
| macOS | 屏幕顶部右侧的“调色盘图标 + 皮肤” | 点击后可查看当前主题和 Codex 连接状态、快速切换、恢复原版、打开完整管理器或退出 |
| Windows | 任务栏右下角通知区域的管理器图标 | 双击恢复完整窗口；右键可查看状态、快速切换、恢复原版或退出 |

macOS 关闭红色窗口按钮只会关闭主窗口，管理器仍在后台运行。全屏应用隐藏菜单栏时，把鼠标移到屏幕顶部即可看到“皮肤”；需要完整退出时，在“皮肤”菜单中选择“退出皮肤管理器”。

Windows 关闭主窗口后会隐藏到系统托盘。图标未直接显示时，可点击任务栏通知区域的向上箭头展开隐藏图标。

菜单栏和托盘中的主题、连接状态会与完整管理器同步更新。

## 软件与在线主题更新

管理器启动约 6 秒后会在后台检查更新，成功检查后 24 小时内不重复请求。也可以通过以下入口手动检查：

- macOS：窗口工具栏的下载图标，或顶部“皮肤”菜单中的“检查更新…”
- Windows：窗口右上角、运行状态页，或系统托盘中的“检查更新”

更新分为两类：

| 类型 | 包含内容 | 安装方式 | 是否保留用户数据 |
|---|---|---|:---:|
| 软件更新 | 管理器、注入器、安装器、内置主题和 Skill | 下载完整 DMG 或 EXE，校验后自动安装 | 是 |
| 在线主题更新 | 新主题或已有主题的新图片、配色与清单 | 下载单个主题 ZIP，校验后原子写入主题库 | 是 |

### 软件更新流程

1. 下载并验证 Ed25519 签名更新清单。
2. 比较语义版本，并选择当前平台安装包。
3. 验证 HTTPS 地址、文件大小和 SHA-256。
4. macOS 自动挂载 DMG 并运行内置更新器；Windows 退出管理器后静默运行 NSIS。
5. 安装完成后自动打开新版管理器。

更新软件时 Codex 可以保持运行，用户主题、当前选择和状态数据不会被清空。下载、签名或校验失败时，当前版本保持原样，安装包不会执行。

在线主题使用独立签名目录。发现兼容的新主题后可直接在更新界面安装，管理器会继续使用现有 schema 2 校验和原子替换流程。新增背景与配色通常只需下载主题 ZIP；涉及注入器、布局模块或主题格式变化时才发布完整软件版本。

### 更新状态

| 状态 | 含义 |
|---|---|
| 已是最新版 | 软件版本与签名清单一致，当前没有可安装的软件版本 |
| 发现新版本 | 可以查看版本号和说明，并开始下载完整安装包 |
| 有在线主题 | 软件无需升级，可单独安装兼容的新主题或主题修订 |
| 检查中 / 下载中 / 安装中 | 后台任务正在执行，完成前不要重复点击 |
| 离线或检查失败 | 网络、GitHub 访问或清单验证失败；现有软件与主题仍可使用 |
| 校验失败 | 签名、大小或 SHA-256 与清单不一致，文件已被拒绝 |

### 更新安全模型

- 固定更新地址只读取本仓库 `main` 分支中的 `updates/stable.json` 与 `updates/themes.json`。
- 两份清单都使用 Ed25519 分离签名；公钥内置在管理器中，私钥只保存在维护者密钥存储和 GitHub Actions Secret。
- 所有下载地址必须使用 HTTPS，并同时匹配清单声明的字节数和 SHA-256。
- 在线主题还会执行 schema 2、PNG 文件头、图片尺寸、路径边界和符号链接检查。
- 更新清单只描述版本与文件，不向安装器传递任意命令行参数。

## 使用主题

1. 打开 Codex 皮肤管理器。
2. 在主题库中选择预览图。
3. 点击“一键切换”。
4. 管理器会显示当前主题、Codex 连接状态和切换结果。
5. 也可以直接从 macOS 菜单栏或 Windows 系统托盘切换。
6. 需要回到官方外观时，选择置顶的“Codex 默认原版”。

主题只改变界面外观。对话、项目选择器、设置、输入框和其他功能仍由 Codex 原生界面提供。

## 常见问题

### macOS 顶部没有“皮肤”入口

先从“应用程序”启动一次 Codex 皮肤管理器。关闭红色窗口按钮后应用仍会驻留；全屏状态下把鼠标移到屏幕顶部。仍未出现时，确认活动监视器中存在“Codex 皮肤管理器”，然后重新打开应用。

### Windows 托盘没有图标

先从开始菜单启动一次管理器，再点击任务栏通知区域的向上箭头。Windows 可能把新图标收入隐藏区域，可在系统的“任务栏角溢出”设置中将它设为始终显示。

### 显示“未连接”，但仍能浏览或选择主题

“未连接”只代表当前没有连上 Codex 的本机 CDP 会话。打开 Codex 后再次点击“一键切换”；管理器会重新发现应用、启动主题运行时并刷新状态。端口冲突时会自动选择可用的本机端口。

### Codex 已换肤，但管理器仍显示旧主题

等待几秒让状态文件和界面同步；也可切换到“运行状态”页或从菜单栏/托盘重新打开主窗口。若状态仍旧，重新选择当前主题并执行一次切换，不需要重新安装。

### 切换后局部颜色或背景没有刷新

先进入另一个页面再返回。Codex 更新界面结构后，可重新执行“一键切换”让注入器扫描新窗口；持续异常时选择“Codex 默认原版”，再重新应用目标主题。

### 更新检查失败

确认设备可以访问 `github.com`、`raw.githubusercontent.com` 和 Release 下载地址。系统时间错误也会影响 HTTPS。管理器不会在验证失败时覆盖当前版本，可以稍后从更新入口重试，或从 Releases 手动安装相同版本。

### 恢复 Codex 原版

选择主题库置顶的“Codex 默认原版”，或使用菜单栏/托盘中的“恢复原版”。该操作停止主题注入并恢复由管理器调整的外观配置，不删除对话、项目和用户主题。

## 创建主题

在管理器中打开“创建主题”：

1. 选择 PNG、JPEG、WebP 或 HEIC 图片。
2. 调整横向焦点，保证人物与主要场景处于合适位置。
3. 填写名称、主题 ID、作者、描述和分类。
4. 选择浅色或暗色界面。
5. 设置强调色、辅助色和点缀色。
6. 点击“创建主题”。

管理器会生成：

```text
my-theme/
├── theme.json
├── background.png   # 2400x800
└── preview.png      # 1200x400
```

生成完成后，主题会立即出现在主题库中。

## Codex Skill

安装包会自动安装 `codex-skin-theme-creator`。也可以从 Release 下载：

```text
codex-skin-theme-creator-1.7.2.zip
```

Skill 默认位置：

```text
macOS：${CODEX_HOME:-~/.codex}/skills/codex-skin-theme-creator
Windows：%CODEX_HOME%\skills\codex-skin-theme-creator
```

示例：

```text
用这张图片创建一套浅色 Codex 主题，名字叫“水色工作台”。
```

```text
创建一套暗色星海主题，人物放在右侧，左边保留清晰环境。
```

Skill 会生成或处理背景图，创建 schema 2 清单，并将主题原子写入管理器的用户主题库。详细流程见 [Skill 说明](./skill/codex-skin-theme-creator/SKILL.md)。

## 导入格式

管理器只接收包含以下三个标准文件的主题目录：

```text
theme-id/
├── theme.json
├── background.png
└── preview.png
```

核心要求：

- `schemaVersion` 固定为 `2`
- ID 只使用小写字母、数字和连字符
- 两张图片必须为真实 PNG 和精确 3:1
- `background.png` 建议使用 `2400x800`
- `preview.png` 建议使用 `1200x400`
- `avatarOverlay` 固定为 `show`
- `appearance` 使用 `auto`、`light` 或 `dark`
- 不接受符号链接、越界路径和旧版 `taskImage`

全部字段和 JSON 示例见 [主题格式文档](./docs/theme-format.md)。

## 内置主题

| 顺序 | 主题 |
|---:|---|
| 1 | Codex 默认原版 |
| 2 | 月薪喵打卡 |
| 3 | 初音未来 |
| 4 | 奶龙晴空 |
| 5 | 昔涟 · 星海回响 |
| 6 | 蔚蓝档案 · 青春合影 |
| 7 | 卡提希娅 · 风栖海境 |
| 8 | 芙宁娜 · 水色剧场 |
| 9 | 流萤 · 星海微光 |
| 10 | Saber · 誓约胜利 |
| 11 | 明日香 · 红色黄昏 |
| 12 | 蕾姆 · 冰蓝夜庭 |
| 13 | OpenAI 是人民的 AI |
| 14 | KUN 黑金舞台 |

## 工作方式

```text
Codex 皮肤管理器
  ├─ 管理内置主题和用户主题
  ├─ 启动或连接本机 Codex
  ├─ 通过 127.0.0.1 CDP 注入主题
  └─ 校验主题是否应用成功
                │
                ▼
Codex 原生侧栏、对话、设置和输入器继续工作
```

项目不修改官方 `.app`、`app.asar`、WindowsApps 文件或官方代码签名。CDP 只监听和连接本机回环地址。

## 从源码构建

```bash
git clone https://github.com/jonyhunter/codex-theme-manager.git
cd Codex-Skin-Manager
```

基础依赖：Git、Node.js 22 或更新版本。macOS 构建需要 macOS 14、Xcode Command Line Tools 和 Swift；Windows 实机测试需要 Windows PowerShell 5.1 或 PowerShell 7，生成 EXE 需要 NSIS。

macOS 测试与构建：

```bash
macos/tests/run-tests.sh
macos/scripts/build-studio-app-macos.sh \
  "$HOME/Desktop/Codex 皮肤管理器.app"
macos/scripts/build-installer-dmg-macos.sh \
  "$HOME/Desktop/Codex-Skin-Manager-1.7.2.dmg"
```

Windows 测试与管理器：

```powershell
powershell -ExecutionPolicy Bypass -File windows\tests\run-tests.ps1
powershell -ExecutionPolicy Bypass -STA -File windows\scripts\theme-manager.ps1
```

Windows 安装包：

```bash
brew install nsis
windows/scripts/build-installer-windows.sh
```

更新清单与跨平台 Node 测试：

```bash
node script/update-feed.mjs validate
node --test macos/tests/*.test.mjs windows/tests/*.test.mjs
```

## 维护者发布流程

### 首次配置签名 Secret

软件更新清单必须使用与 `updates/public-key.json` 配套的 Ed25519 私钥签名。私钥文件 `.update-private-key.jwk` 已被 `.gitignore` 排除，应另外备份到加密密钥库，并在仓库中配置一次：

```bash
gh secret set CODEX_UPDATE_PRIVATE_KEY_JWK \
  --repo OWNER/Codex-Skin-Manager \
  < .update-private-key.jwk
```

不要提交、截图或上传该私钥。私钥丢失后，需要发布一个内置新公钥的过渡版本，因此应至少保留一份独立加密备份。

### 发布完整软件版本

1. 更新 `macos/VERSION`、两个平台的管理器/注入器/安装器版本常量以及中英文 Changelog。
2. 更新 README 中的版本号和安装包名称。
3. 运行 macOS、Windows、Node、签名清单和打包测试。
4. 合并并推送 `main`，确认 CI 通过。
5. 创建与版本完全一致的标签并推送：

```bash
git tag -a v1.7.2 -m "Codex 皮肤管理器 v1.7.2"
git push origin main
git push origin v1.7.2
```

标签会触发 [Release 工作流](./.github/workflows/release.yml)，自动完成：

1. 在 macOS Runner 构建 DMG，在 Windows Runner 构建 NSIS EXE。
2. 打包 `codex-skin-theme-creator` Skill。
3. 生成三份安装文件的 SHA-256 清单。
4. 创建 GitHub Release 并上传安装包、Skill、校验文件与签名清单。
5. 使用 GitHub Secret 签名新版更新源，并将最终 `updates/` 内容提交回 `main`。

发布完成后，应核对 Release 至少包含 DMG、EXE、Skill ZIP 和 SHA-256 文件，并运行：

```bash
git pull --ff-only
node script/update-feed.mjs validate
```

### 单独发布在线主题

主题只调整图片、文字或配色，且不依赖新注入器时，可直接发布主题 ZIP：

```bash
node script/update-feed.mjs add-theme \
  --theme PATH/TO/THEME_ID \
  --theme-version 2 \
  --minimum-app 1.7.2 \
  --url https://github.com/OWNER/Codex-Skin-Manager/releases/download/TAG/THEME_ID-2.zip \
  --output release/THEME_ID-2.zip \
  --private-key .update-private-key.jwk
```

将 ZIP 上传到 URL 对应的 Release，提交更新后的 `updates/stable.json`、`updates/themes.json` 及两个 `.sig` 文件，再运行 `node script/update-feed.mjs validate`。管理器下一次检查时会只下载这个主题包。

## 项目结构

```text
macos/                         macOS 管理器、安装器、运行时和主题
windows/                       Windows 管理器、安装器、运行时和主题
skill/codex-skin-theme-creator Codex 主题创建 Skill
docs/images/showcase/          README 脱敏截图
docs/theme-format.md           schema 2 主题规范
docs/platforms.md              平台路径和能力对照
script/                        构建与文档维护工具
```

## 验证

当前发布通过：

- macOS 完整回归与 Swift 构建检查
- Windows PowerShell 5.1 与 PowerShell 7 回归
- 跨平台 Node.js 渲染器和注入器测试
- GitHub Actions 静态、编码和版本一致性检查
- macOS DMG 容器校验
- Windows NSIS 安装包格式检查
- Skill 结构校验

Release 中的 `Codex-Skin-Manager-1.7.2-SHA256.txt` 可用于核对下载文件。

## 许可

代码使用 [MIT License](./LICENSE)。内置角色主题用于展示主题系统；再分发或商业使用前，请自行确认对应图片、角色名称和商标的使用条件。

## 引用说明

本项目在 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的主题注入思路基础上进行了独立的跨平台管理器、主题库、安装器、创建工具与 Skill 二次开发。
