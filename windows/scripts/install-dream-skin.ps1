[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$NoShortcuts
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$SkillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-skill.ps1')

$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$InstallLogPath = Join-Path $StateRoot 'install-error.log'
$operationLock = $null
try {
  $operationLock = Enter-DreamSkinOperationLock
  Assert-DreamSkinPort -Port $Port
  $null = Get-DreamSkinNodeRuntime
  $registeredInstalls = @(Get-DreamSkinRegisteredCodexInstalls)
  if ($registeredInstalls.Count -eq 0) {
    throw 'The official OpenAI.Codex Store package is not installed or its identity cannot be validated.'
  }
  $codexRunning = $false
  foreach ($registeredCodex in $registeredInstalls) {
    if (@(Get-DreamSkinCodexProcesses -Codex $registeredCodex).Count -gt 0) {
      $codexRunning = $true
    }
  }
  if ($codexRunning) {
    Write-Host '检测到 Codex 正在运行；安装将保持当前窗口开启，主题会在首次应用时生效。'
  }

  $ThemesRoot = Join-Path $StateRoot 'themes'
  $ThemeDir = Join-Path $StateRoot 'theme'
  $StatePath = Join-Path $StateRoot 'state.json'
  $existingState = Read-DreamSkinState -Path $StatePath
  $savedPathCandidate = Get-DreamSkinCodexStatePathCandidate -State $existingState
  $savedCodex = Resolve-DreamSkinCodexInstallFromState -State $existingState -RegisteredInstalls $registeredInstalls
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and
    @(Get-DreamSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0) {
    throw 'The saved Codex path is still running but no longer matches a registered Store package. Close it manually before installing.'
  }
  New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $ThemesRoot | Out-Null
  $BuiltInThemesRoot = Join-Path $SkillRoot 'themes'
  foreach ($source in @(Get-ChildItem -LiteralPath $BuiltInThemesRoot -Directory)) {
    $destination = Join-Path $ThemesRoot $source.Name
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $source.FullName '*') -Destination $destination -Recurse -Force
  }
  Install-DreamSkinThemeSkill -EngineRoot $SkillRoot | Out-Null
  if (-not (Test-Path -LiteralPath (Join-Path $ThemeDir 'theme.json'))) {
    New-Item -ItemType Directory -Force -Path $ThemeDir | Out-Null
    Copy-Item -Path (Join-Path $BuiltInThemesRoot 'salary-cat-office\*') -Destination $ThemeDir -Recurse -Force
  }
  $SelectionPath = Join-Path $StateRoot 'selection.json'
  if (-not (Test-Path -LiteralPath $SelectionPath)) {
    $activeManifest = Get-Content -LiteralPath (Join-Path $ThemeDir 'theme.json') -Raw -Encoding UTF8 |
      ConvertFrom-Json
    $selection = [ordered]@{
      schemaVersion = 1
      themeId = [string]$activeManifest.id
      selectedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-DreamSkinUtf8FileAtomically `
      -Path $SelectionPath `
      -Content (($selection | ConvertTo-Json -Depth 3) + "`r`n")
  }
  $ConfigPath = Join-Path $HOME '.codex\config.toml'
  $BackupPath = Join-Path $StateRoot 'config.before-dream-skin.toml'
  $configInstalled = $false
  for ($attempt = 1; $attempt -le 3 -and -not $configInstalled; $attempt++) {
    try {
      Install-DreamSkinBaseTheme -ConfigPath $ConfigPath -BackupPath $BackupPath
      $configInstalled = $true
    } catch {
      $isConcurrentWrite = $_.Exception.Message -like 'File changed during the operation*'
      if (-not $isConcurrentWrite -or $attempt -eq 3) { throw }
      Write-Warning "Codex 正在更新配置，准备重试（$attempt/3）。"
      Start-Sleep -Milliseconds 350
    }
  }

  if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $startLauncher = Join-Path $PSScriptRoot 'launch-dream-skin.vbs'
    $managerLauncher = Join-Path $PSScriptRoot 'launch-theme-manager.vbs'
    $restoreLauncher = Join-Path $PSScriptRoot 'launch-restore.vbs'
    $iconPath = Join-Path $SkillRoot 'assets\DreamSkinAppIcon.ico'
    $portArgument = if ($PortExplicit) { " -Port $Port" } else { '' }
    @(
      (Join-Path $desktop 'Codex Dream Skin.lnk'),
      (Join-Path $desktop 'Codex Dream Skin Themes.lnk'),
      (Join-Path $desktop 'Codex Dream Skin - Restore.lnk'),
      (Join-Path $startMenu 'Codex Dream Skin.lnk'),
      (Join-Path $startMenu 'Codex Dream Skin Themes.lnk')
    ) | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }

    foreach ($folder in @($desktop, $startMenu)) {
      $shortcut = $shell.CreateShortcut((Join-Path $folder 'Codex 皮肤启动器.lnk'))
      $shortcut.TargetPath = $wscript
      $shortcut.Arguments = "`"$startLauncher`"$portArgument"
      $shortcut.WorkingDirectory = $SkillRoot
      $shortcut.Description = '使用当前皮肤启动 Codex'
      if (Test-Path -LiteralPath $iconPath) { $shortcut.IconLocation = "$iconPath,0" }
      $shortcut.Save()
    }

    foreach ($folder in @($desktop, $startMenu)) {
      $manager = $shell.CreateShortcut((Join-Path $folder 'Codex 皮肤管理器.lnk'))
      $manager.TargetPath = $wscript
      $manager.Arguments = "`"$managerLauncher`""
      $manager.WorkingDirectory = $SkillRoot
      $manager.Description = '预览并切换 Codex 皮肤'
      if (Test-Path -LiteralPath $iconPath) { $manager.IconLocation = "$iconPath,0" }
      $manager.Save()
    }

    $restore = $shell.CreateShortcut((Join-Path $desktop 'Codex 皮肤管理器 - 恢复原版.lnk'))
    $restore.TargetPath = $wscript
    $restore.Arguments = "`"$restoreLauncher`"$portArgument"
    $restore.WorkingDirectory = $SkillRoot
    $restore.Description = 'Restore the official Codex appearance and close the CDP session'
    if (Test-Path -LiteralPath $iconPath) { $restore.IconLocation = "$iconPath,0" }
    $restore.Save()
  }

  if ($NoShortcuts) {
    Write-Host 'Codex 皮肤管理器基础主题已安装，可运行 start-dream-skin.ps1 启动。'
  } elseif ($codexRunning) {
    Write-Host 'Codex 皮肤管理器已安装；当前 Codex 保持运行，首次切换主题时按提示应用即可。'
  } else {
    Write-Host 'Codex 皮肤管理器已安装，启动快捷方式会在重启已打开的 Codex 前进行确认。'
  }
  Remove-Item -LiteralPath $InstallLogPath -Force -ErrorAction SilentlyContinue
} catch {
  $installError = $_
  try {
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    $details = @(
      "time: $([DateTime]::Now.ToString('o'))"
      "message: $($installError.Exception.Message)"
      ''
      $installError.Exception.ToString()
      ''
      $installError.ScriptStackTrace
    ) -join "`r`n"
    [IO.File]::WriteAllText(
      $InstallLogPath,
      $details,
      ([System.Text.UTF8Encoding]::new($false, $true))
    )
  } catch {}
  Write-Error "安装失败：$($installError.Exception.Message)`r`n详细日志：$InstallLogPath"
  exit 1
} finally {
  if ($null -ne $operationLock) { Exit-DreamSkinOperationLock -Mutex $operationLock }
}
