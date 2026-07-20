Unicode True
RequestExecutionLevel user

!include "MUI2.nsh"
!include "LogicLib.nsh"

!define PRODUCT_NAME "Codex 皮肤管理器"
!define PRODUCT_VERSION "1.7.1"
!define PRODUCT_PUBLISHER "Codex 皮肤管理器"
!define ENGINE_DIR "$LOCALAPPDATA\CodexDreamSkin\engine-${PRODUCT_VERSION}"

Name "${PRODUCT_NAME}"
OutFile "..\release\Codex-Skin-Manager-Setup-${PRODUCT_VERSION}.exe"
InstallDir "${ENGINE_DIR}"
Icon "..\assets\DreamSkinAppIcon.ico"
UninstallIcon "..\assets\DreamSkinAppIcon.ico"
BrandingText "${PRODUCT_NAME} ${PRODUCT_VERSION}"
SetCompressor /SOLID lzma
ManifestDPIAware true
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} Windows 安装程序"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "LegalCopyright" "Copyright 2026 Codex Skin Manager contributors"
ShowInstDetails show
ShowUninstDetails show

!define MUI_ABORTWARNING
!define MUI_ICON "..\assets\DreamSkinAppIcon.ico"
!define MUI_UNICON "..\assets\DreamSkinAppIcon.ico"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "打开主题管理器"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchThemeManager
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Section "Codex 皮肤管理器" SecMain
  ; Keep identical runtime binaries in place during an in-version repair install. Windows
  ; locks the bundled node.exe while the injector is active, but updated scripts have newer
  ; timestamps and are still replaced.
  SetOverwrite ifnewer
  SetOutPath "$INSTDIR"
  File /r /x "installer" /x "release" "..\*.*"
  SetOutPath "$INSTDIR\skill\codex-skin-theme-creator"
  File /r "..\..\skill\codex-skin-theme-creator\*.*"
  SetOverwrite on
  SetOutPath "$INSTDIR"

  DetailPrint "正在安装主题库和快捷方式..."
  nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\scripts\install-dream-skin.ps1"'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "安装脚本退出代码：$0$\r$\n详细原因已显示在安装窗口，并保存到：$\r$\n%LOCALAPPDATA%\CodexDreamSkin\install-error.log"
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "DisplayIcon" "$INSTDIR\assets\DreamSkinAppIcon.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin" "NoRepair" 1
SectionEnd

Function LaunchThemeManager
  Exec '"$SYSDIR\wscript.exe" "$INSTDIR\scripts\launch-theme-manager.vbs"'
FunctionEnd

Section "Uninstall"
  IfFileExists "$INSTDIR\scripts\restore-dream-skin.ps1" 0 +3
  nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\scripts\restore-dream-skin.ps1" -Uninstall -RestoreBaseTheme -ForceRestart'
  Pop $0

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexDreamSkin"
  RMDir /r "$LOCALAPPDATA\CodexDreamSkin"
SectionEnd
