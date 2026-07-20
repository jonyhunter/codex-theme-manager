# Codex 皮肤管理器（Windows）

Windows 版与 macOS 版使用相同的 14 套 schema 2 单主图主题，通过本机回环 CDP 为 Microsoft Store 版 Codex 应用主题。

## 安装

Codex 可以保持运行，直接运行：

```text
Codex-Skin-Manager-Setup-1.7.2.exe
```

安装器部署到 `%LOCALAPPDATA%\CodexDreamSkin\engine-1.7.2`，内置 Node.js 运行时，并创建主题管理器和恢复快捷方式。
当前 Codex 窗口不会被安装器关闭，主题会在首次应用时生效。

## 主题管理器

- 浏览预览并一键切换主题
- 后台驻留系统托盘，关闭窗口不退出；托盘菜单显示实时状态并支持快速切换
- 启动后后台检查签名更新，也可从窗口、运行状态页或托盘手动检查
- 校验并静默安装新版 NSIS，随后从新的版本化引擎目录自动重启管理器
- 从独立在线目录安装官方主题，不需要下载完整软件安装包
- 查看当前主题横幅、Codex 连接状态和主题运行信息
- 在“主题接入”页查看导入规范，在“运行状态”页刷新引擎状态
- 不关闭 Codex 即可恢复原版外观，随后仍可直接切回其他主题
- 选择图片创建主题
- 调整横向裁切焦点
- 设置名称、ID、作者、描述、分类、浅色/暗色和主题色
- 导入严格 schema 2 三文件主题包
- 确认后替换同 ID 自定义主题
- 保护所有内置主题 ID
- 安装并维护 `codex-skin-theme-creator` Skill，通过对话创建后自动加入主题库

主题格式：

```text
my-theme/
├── theme.json
├── background.png
└── preview.png
```

完整规范见 [`../docs/theme-format.md`](../docs/theme-format.md)。

## 内置主题

Codex 默认原版、月薪喵打卡、初音未来、奶龙晴空、昔涟、蔚蓝档案、卡提希娅、芙宁娜、流萤、Saber、明日香、蕾姆、OpenAI 是人民的 AI、KUN 黑金舞台。

## 测试

在 Windows PowerShell 5.1 或 PowerShell 7 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

## 构建安装包

使用 NSIS：

```bash
brew install nsis
./scripts/build-installer-windows.sh
```

产物：

```text
release/Codex-Skin-Manager-Setup-1.7.2.exe
```

发布前需在真实 Windows 10/11 环境完成安装、创建、导入、切换、恢复和卸载测试。
