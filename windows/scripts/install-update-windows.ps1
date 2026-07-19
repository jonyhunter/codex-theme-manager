[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][int]$ManagerPid
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$logPath = Join-Path $stateRoot 'update-install.log'
$utf8 = New-Object System.Text.UTF8Encoding($true)

function Write-UpdateLog {
  param([Parameter(Mandatory = $true)][string]$Message)
  [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
  [IO.File]::AppendAllText(
    $logPath,
    ('{0} {1}' -f (Get-Date).ToUniversalTime().ToString('o'), $Message) + [Environment]::NewLine,
    $utf8
  )
}

try {
  if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw '更新版本号格式无效。'
  }
  $installer = Get-Item -LiteralPath $InstallerPath -ErrorAction Stop
  if ($installer.PSIsContainer -or $installer.Extension -ine '.exe' -or $installer.Length -le 0) {
    throw '更新安装包无效。'
  }

  Write-UpdateLog "等待管理器进程退出：$ManagerPid"
  try { Wait-Process -Id $ManagerPid -Timeout 30 -ErrorAction Stop } catch {
    $running = Get-Process -Id $ManagerPid -ErrorAction SilentlyContinue
    if ($null -ne $running) { throw '管理器未在规定时间内退出。' }
  }

  Write-UpdateLog "开始静默安装：$Version"
  $installArguments = @{
    FilePath = $installer.FullName
    ArgumentList = '/S'
    Wait = $true
    PassThru = $true
    WindowStyle = 'Hidden'
  }
  $install = Start-Process @installArguments
  if ($install.ExitCode -ne 0) {
    throw "安装程序退出代码：$($install.ExitCode)"
  }

  $launcher = Join-Path $stateRoot "engine-$Version\scripts\launch-theme-manager.vbs"
  if (-not (Test-Path -LiteralPath $launcher)) {
    throw "新版管理器入口不存在：$launcher"
  }
  $statePath = Join-Path $stateRoot 'state.json'
  $startScript = Join-Path $stateRoot "engine-$Version\scripts\start-dream-skin.ps1"
  if ((Test-Path -LiteralPath $statePath) -and (Test-Path -LiteralPath $startScript)) {
    try {
      $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ([string]$state.session -ceq 'active' -and $state.port) {
        Write-UpdateLog "切换到新版注入器：$startScript"
        $refreshArguments = @{
          FilePath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
          ArgumentList = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            [char]34 + $startScript + [char]34,
            '-Port',
            [string][int]$state.port
          )
          Wait = $true
          PassThru = $true
          WindowStyle = 'Hidden'
        }
        $refresh = Start-Process @refreshArguments
        if ($refresh.ExitCode -ne 0) {
          Write-UpdateLog "新版注入器刷新退出代码：$($refresh.ExitCode)"
        }
      }
    } catch {
      Write-UpdateLog "新版注入器刷新未完成：$($_.Exception.Message)"
    }
  }
  Write-UpdateLog "更新完成，启动新版管理器：$launcher"
  $quotedLauncher = [char]34 + $launcher + [char]34
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList @($quotedLauncher) | Out-Null
} catch {
  Write-UpdateLog "更新失败：$($_.Exception.Message)"
  Add-Type -AssemblyName System.Windows.Forms
  $detail = $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + "日志：$logPath"
  [System.Windows.Forms.MessageBox]::Show(
    $detail,
    'Codex 皮肤管理器更新失败',
    'OK',
    'Error'
  ) | Out-Null
  exit 1
}
