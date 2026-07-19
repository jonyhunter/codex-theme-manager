[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$instanceCreated = $false
$instanceMutex = [System.Threading.Mutex]::new(
  $true,
  'Local\CodexSkinManager',
  [ref]$instanceCreated
)
if (-not $instanceCreated) {
  for ($attempt = 0; $attempt -lt 10; $attempt++) {
    try {
      $existingShowEvent = [System.Threading.EventWaitHandle]::OpenExisting(
        'Local\CodexSkinManager.Show'
      )
      try { [void]$existingShowEvent.Set() } finally { $existingShowEvent.Dispose() }
      break
    } catch {
      Start-Sleep -Milliseconds 50
    }
  }
  $instanceMutex.Dispose()
  exit 0
}
$showEventCreated = $false
$showEvent = [System.Threading.EventWaitHandle]::new(
  $false,
  [System.Threading.EventResetMode]::AutoReset,
  'Local\CodexSkinManager.Show',
  [ref]$showEventCreated
)

$EngineRoot = Split-Path -Parent $PSScriptRoot
$ThemeRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\themes'
$SwitchScript = Join-Path $PSScriptRoot 'switch-theme.ps1'
$FontName = 'Microsoft YaHei UI'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-package.ps1')
. (Join-Path $PSScriptRoot 'theme-skill.ps1')

function Get-OptionalThemeText {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $property = $Manifest.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function New-ThemeManagerButton {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][System.Drawing.Point]$Location,
    [System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(110, 36)),
    [switch]$Primary
  )

  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Location = $Location
  $button.Size = $Size
  $button.FlatStyle = 'Flat'
  $button.Font = New-Object System.Drawing.Font($FontName, 9, [System.Drawing.FontStyle]::Bold)
  if ($Primary) {
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = [System.Drawing.Color]::FromArgb(226, 82, 66)
    $button.ForeColor = [System.Drawing.Color]::White
  } else {
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(211, 219, 216)
    $button.BackColor = [System.Drawing.Color]::White
    $button.ForeColor = [System.Drawing.Color]::FromArgb(54, 68, 75)
  }
  return $button
}

function Set-ThemeColorButton {
  param(
    [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$Button,
    [Parameter(Mandatory = $true)][string]$Hex
  )

  $Button.Tag = $Hex.ToUpperInvariant()
  $Button.BackColor = [System.Drawing.ColorTranslator]::FromHtml($Button.Tag)
  $brightness = ($Button.BackColor.R * 299 + $Button.BackColor.G * 587 + $Button.BackColor.B * 114) / 1000
  $Button.ForeColor = if ($brightness -gt 145) {
    [System.Drawing.Color]::FromArgb(32, 42, 48)
  } else {
    [System.Drawing.Color]::White
  }
  $Button.Text = $Button.Tag
}

function Show-ThemeCreator {
  param([Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Owner)

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = '创建主题'
  $dialog.StartPosition = 'CenterParent'
  $dialog.ClientSize = New-Object System.Drawing.Size(820, 720)
  $dialog.FormBorderStyle = 'FixedDialog'
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.BackColor = [System.Drawing.Color]::FromArgb(247, 250, 249)
  $dialog.Font = New-Object System.Drawing.Font($FontName, 9)

  $heading = New-Object System.Windows.Forms.Label
  $heading.Text = '创建主题'
  $heading.AutoSize = $true
  $heading.Location = New-Object System.Drawing.Point(30, 17)
  $heading.Font = New-Object System.Drawing.Font($FontName, 18, [System.Drawing.FontStyle]::Bold)
  $heading.ForeColor = [System.Drawing.Color]::FromArgb(36, 52, 62)
  $dialog.Controls.Add($heading)

  $subtitle = New-Object System.Windows.Forms.Label
  $subtitle.Text = '生成标准 schema 2 主题包'
  $subtitle.AutoSize = $true
  $subtitle.Location = New-Object System.Drawing.Point(32, 49)
  $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(102, 118, 128)
  $dialog.Controls.Add($subtitle)

  $preview = New-Object System.Windows.Forms.PictureBox
  $preview.Location = New-Object System.Drawing.Point(30, 78)
  $preview.Size = New-Object System.Drawing.Size(760, 253)
  $preview.BorderStyle = 'FixedSingle'
  $preview.BackColor = [System.Drawing.Color]::White
  $preview.SizeMode = 'Zoom'
  $dialog.Controls.Add($preview)

  $imagePath = New-Object System.Windows.Forms.TextBox
  $imagePath.Location = New-Object System.Drawing.Point(30, 343)
  $imagePath.Size = New-Object System.Drawing.Size(626, 28)
  $imagePath.ReadOnly = $true
  $dialog.Controls.Add($imagePath)

  $browse = New-ThemeManagerButton -Text '选择图片' `
    -Location (New-Object System.Drawing.Point(668, 340)) `
    -Size (New-Object System.Drawing.Size(122, 32))
  $dialog.Controls.Add($browse)

  $labels = @(
    @{ Text = '主题名称'; X = 30; Y = 390 },
    @{ Text = '主题 ID'; X = 410; Y = 390 },
    @{ Text = '作者'; X = 30; Y = 450 },
    @{ Text = '主题描述'; X = 410; Y = 450 },
    @{ Text = '分类'; X = 30; Y = 510 },
    @{ Text = '界面模式'; X = 210; Y = 510 },
    @{ Text = '图片焦点'; X = 410; Y = 510 },
    @{ Text = '主题色'; X = 30; Y = 578 }
  )
  foreach ($definition in $labels) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $definition.Text
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point($definition.X, $definition.Y)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(102, 118, 128)
    $dialog.Controls.Add($label)
  }

  $nameBox = New-Object System.Windows.Forms.TextBox
  $nameBox.Location = New-Object System.Drawing.Point(30, 411)
  $nameBox.Size = New-Object System.Drawing.Size(350, 28)
  $dialog.Controls.Add($nameBox)

  $idBox = New-Object System.Windows.Forms.TextBox
  $idBox.Location = New-Object System.Drawing.Point(410, 411)
  $idBox.Size = New-Object System.Drawing.Size(380, 28)
  $idBox.Text = 'custom-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  $dialog.Controls.Add($idBox)

  $authorBox = New-Object System.Windows.Forms.TextBox
  $authorBox.Location = New-Object System.Drawing.Point(30, 471)
  $authorBox.Size = New-Object System.Drawing.Size(350, 28)
  $dialog.Controls.Add($authorBox)

  $descriptionBox = New-Object System.Windows.Forms.TextBox
  $descriptionBox.Location = New-Object System.Drawing.Point(410, 471)
  $descriptionBox.Size = New-Object System.Drawing.Size(380, 28)
  $dialog.Controls.Add($descriptionBox)

  $categoryBox = New-Object System.Windows.Forms.ComboBox
  $categoryBox.Location = New-Object System.Drawing.Point(30, 531)
  $categoryBox.Size = New-Object System.Drawing.Size(160, 28)
  $categoryBox.DropDownStyle = 'DropDownList'
  [void]$categoryBox.Items.AddRange(@('自定义', '动漫', '角色', '清新', '暗色', '极简'))
  $categoryBox.SelectedIndex = 0
  $dialog.Controls.Add($categoryBox)

  $appearanceBox = New-Object System.Windows.Forms.ComboBox
  $appearanceBox.Location = New-Object System.Drawing.Point(210, 531)
  $appearanceBox.Size = New-Object System.Drawing.Size(160, 28)
  $appearanceBox.DropDownStyle = 'DropDownList'
  [void]$appearanceBox.Items.AddRange(@('暗色', '浅色'))
  $appearanceBox.SelectedIndex = 0
  $dialog.Controls.Add($appearanceBox)

  $focus = New-Object System.Windows.Forms.TrackBar
  $focus.Location = New-Object System.Drawing.Point(410, 527)
  $focus.Size = New-Object System.Drawing.Size(380, 42)
  $focus.Minimum = 0
  $focus.Maximum = 100
  $focus.TickFrequency = 10
  $focus.Value = 50
  $dialog.Controls.Add($focus)

  $accentButton = New-ThemeManagerButton -Text '#4F9FE8' `
    -Location (New-Object System.Drawing.Point(30, 601)) `
    -Size (New-Object System.Drawing.Size(124, 32))
  Set-ThemeColorButton -Button $accentButton -Hex '#4F9FE8'
  $dialog.Controls.Add($accentButton)

  $secondaryButton = New-ThemeManagerButton -Text '#70C7B3' `
    -Location (New-Object System.Drawing.Point(166, 601)) `
    -Size (New-Object System.Drawing.Size(124, 32))
  Set-ThemeColorButton -Button $secondaryButton -Hex '#70C7B3'
  $dialog.Controls.Add($secondaryButton)

  $highlightButton = New-ThemeManagerButton -Text '#E8995C' `
    -Location (New-Object System.Drawing.Point(302, 601)) `
    -Size (New-Object System.Drawing.Size(124, 32))
  Set-ThemeColorButton -Button $highlightButton -Hex '#E8995C'
  $dialog.Controls.Add($highlightButton)

  $cancel = New-ThemeManagerButton -Text '取消' `
    -Location (New-Object System.Drawing.Point(562, 664)) `
    -Size (New-Object System.Drawing.Size(104, 36))
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancel)

  $create = New-ThemeManagerButton -Text '创建主题' `
    -Location (New-Object System.Drawing.Point(678, 664)) `
    -Size (New-Object System.Drawing.Size(112, 36)) `
    -Primary
  $dialog.Controls.Add($create)
  $dialog.CancelButton = $cancel
  $result = [pscustomobject]@{ Created = $false }

  $browse.add_Click({
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = '选择主题背景'
    $picker.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.webp;*.bmp|所有文件|*.*'
    if ($picker.ShowDialog($dialog) -eq [System.Windows.Forms.DialogResult]::OK) {
      $imagePath.Text = $picker.FileName
      if ($null -ne $preview.Image) {
        $preview.Image.Dispose()
        $preview.Image = $null
      }
      $source = [System.Drawing.Image]::FromFile($picker.FileName)
      try { $preview.Image = New-Object System.Drawing.Bitmap($source) } finally { $source.Dispose() }
    }
    $picker.Dispose()
  })

  foreach ($button in @($accentButton, $secondaryButton, $highlightButton)) {
    $button.add_Click({
      $colorDialog = New-Object System.Windows.Forms.ColorDialog
      $colorDialog.Color = $this.BackColor
      if ($colorDialog.ShowDialog($dialog) -eq [System.Windows.Forms.DialogResult]::OK) {
        $hex = '#{0:X2}{1:X2}{2:X2}' -f $colorDialog.Color.R, $colorDialog.Color.G, $colorDialog.Color.B
        Set-ThemeColorButton -Button $this -Hex $hex
      }
      $colorDialog.Dispose()
    })
  }

  $create.add_Click({
    try {
      $themeId = $idBox.Text.Trim()
      if ($DreamSkinBuiltInThemeIds -ccontains $themeId) {
        throw '内置主题 ID 受保护，请使用新的主题 ID。'
      }
      $destination = Join-Path $ThemeRoot $themeId
      $replace = Test-Path -LiteralPath $destination
      if ($replace) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
          '相同 ID 的主题已经存在，继续会替换原主题包。',
          '替换现有主题？',
          'YesNo',
          'Warning'
        )
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }
      }
      $appearance = if ($appearanceBox.SelectedIndex -eq 0) { 'dark' } else { 'light' }
      New-DreamSkinThemePackage `
        -SourceImage $imagePath.Text `
        -ThemeRoot $ThemeRoot `
        -ThemeId $themeId `
        -Name $nameBox.Text `
        -Author $authorBox.Text `
        -Description $descriptionBox.Text `
        -Category ([string]$categoryBox.SelectedItem) `
        -Appearance $appearance `
        -Accent ([string]$accentButton.Tag) `
        -Secondary ([string]$secondaryButton.Tag) `
        -Highlight ([string]$highlightButton.Tag) `
        -HorizontalFocus $focus.Value `
        -Replace:$replace
      $result.Created = $true
      $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
      $dialog.Close()
    } catch {
      [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        '创建主题失败',
        'OK',
        'Error'
      ) | Out-Null
    }
  })

  [void]$dialog.ShowDialog($Owner)
  if ($null -ne $preview.Image) { $preview.Image.Dispose() }
  $dialog.Dispose()
  return $result.Created
}

$CanvasColor = [System.Drawing.Color]::FromArgb(244, 247, 246)
$SidebarColor = [System.Drawing.Color]::FromArgb(19, 22, 24)
$SidebarSelectedColor = [System.Drawing.Color]::FromArgb(41, 46, 49)
$SurfaceColor = [System.Drawing.Color]::White
$LineColor = [System.Drawing.Color]::FromArgb(218, 223, 221)
$InkColor = [System.Drawing.Color]::FromArgb(28, 35, 38)
$MutedColor = [System.Drawing.Color]::FromArgb(103, 116, 121)
$AccentColor = [System.Drawing.Color]::FromArgb(219, 79, 63)
$SignalColor = [System.Drawing.Color]::FromArgb(29, 137, 108)
$SignalSoftColor = [System.Drawing.Color]::FromArgb(229, 247, 240)
$GoldColor = [System.Drawing.Color]::FromArgb(183, 128, 42)

$themeOrder = $DreamSkinBuiltInThemeIds
$ActiveThemePath = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\theme\theme.json'
$StatePath = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\state.json'
$SelectionPath = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\selection.json'
$ManagerVersion = '1.7.0'
$UpdateFeedURL = if ($env:CODEX_SKIN_UPDATE_FEED_URL) {
  $env:CODEX_SKIN_UPDATE_FEED_URL
} else {
  'https://raw.githubusercontent.com/houyuhang915-sudo/Codex-Skin-Manager/main/updates/stable.json'
}
$UpdateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\updates'
$UpdateClient = Join-Path $PSScriptRoot 'update-client.mjs'
$UpdateCheckResultPath = Join-Path $UpdateRoot 'check-result.json'
$UpdateCheckStatePath = Join-Path $UpdateRoot 'check-state.json'
$script:themes = @()
$script:themeImages = @()
$script:applyButtons = @()
$script:activeBannerImage = $null
$script:activeThemeId = $null
$script:viewMode = 'all'
$script:switchProcess = $null
$script:switchThemeId = $null
$script:runtimeSnapshot = $null
$script:themeLibraryFingerprint = ''
$script:trayIcon = $null
$script:trayMenu = $null
$script:trayStatusItem = $null
$script:trayCurrentThemeItem = $null
$script:trayThemesMenu = $null
$script:trayRestoreItem = $null
$script:trayUpdateItem = $null
$script:trayMenuFingerprint = ''
$script:explicitExit = $false
$script:hasShownTrayHint = $false
$script:updateProcess = $null
$script:updateOperation = $null
$script:updateInfo = $null
$script:updateManualCheck = $false

function New-ManagerButton {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [int]$Width = 108,
    [switch]$Primary,
    [switch]$Dark
  )

  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Size = New-Object System.Drawing.Size($Width, 36)
  $button.FlatStyle = 'Flat'
  $button.Cursor = [System.Windows.Forms.Cursors]::Hand
  $button.Font = New-Object System.Drawing.Font($FontName, 9, [System.Drawing.FontStyle]::Bold)
  if ($Primary) {
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $AccentColor
    $button.ForeColor = [System.Drawing.Color]::White
  } elseif ($Dark) {
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(75, 82, 86)
    $button.BackColor = $SidebarColor
    $button.ForeColor = [System.Drawing.Color]::FromArgb(234, 238, 237)
  } else {
    $button.FlatAppearance.BorderColor = $LineColor
    $button.BackColor = $SurfaceColor
    $button.ForeColor = $InkColor
  }
  return $button
}

function New-SidebarButton {
  param([Parameter(Mandatory = $true)][string]$Text, [int]$Top)

  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.TextAlign = 'MiddleLeft'
  $button.Location = New-Object System.Drawing.Point(16, $Top)
  $button.Size = New-Object System.Drawing.Size(196, 42)
  $button.Padding = New-Object System.Windows.Forms.Padding(15, 0, 0, 0)
  $button.FlatStyle = 'Flat'
  $button.FlatAppearance.BorderSize = 0
  $button.BackColor = $SidebarColor
  $button.ForeColor = [System.Drawing.Color]::FromArgb(222, 227, 225)
  $button.Cursor = [System.Windows.Forms.Cursors]::Hand
  $button.Font = New-Object System.Drawing.Font($FontName, 9.5, [System.Drawing.FontStyle]::Regular)
  return $button
}

function Get-ThemePreviewImage {
  param([Parameter(Mandatory = $true)][string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $stream = New-Object System.IO.MemoryStream(, $bytes)
  try {
    $source = [System.Drawing.Image]::FromStream($stream)
    try { return New-Object System.Drawing.Bitmap($source) } finally { $source.Dispose() }
  } finally {
    $stream.Dispose()
  }
}

function Get-ActiveThemeId {
  if (Test-Path -LiteralPath $SelectionPath) {
    try {
      $selection = Get-Content -LiteralPath $SelectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $selectedId = [string]$selection.themeId
      if ($selectedId -cmatch '^[a-z0-9-]{1,80}$') { return $selectedId }
    } catch {}
  }
  if (Test-Path -LiteralPath $StatePath) {
    try {
      $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($state.session -ceq 'paused' -or $state.selectedThemeId -ceq 'codex-default') {
        return 'codex-default'
      }
    } catch {}
  }
  if (-not (Test-Path -LiteralPath $ActiveThemePath)) { return $null }
  try {
    $manifest = Get-Content -LiteralPath $ActiveThemePath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string]$manifest.id
  } catch {
    return $null
  }
}

function Write-ManagerThemeSelection {
  param([Parameter(Mandatory = $true)][string]$ThemeId)
  $selection = [ordered]@{
    schemaVersion = 1
    themeId = $ThemeId
    selectedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  Write-DreamSkinUtf8FileAtomically `
    -Path $SelectionPath `
    -Content (($selection | ConvertTo-Json -Depth 3) + "`r`n")
}

function Get-ThemeAppearanceLabel {
  param([Parameter(Mandatory = $true)]$Manifest)

  if ((Get-OptionalThemeText -Manifest $Manifest -Name 'mode') -ceq 'original') { return '原版' }
  switch (Get-OptionalThemeText -Manifest $Manifest -Name 'appearance') {
    'light' { return '浅色' }
    'dark' { return '深色' }
    default { return '跟随系统' }
  }
}

function Get-ManagerRuntimeSnapshot {
  if (-not (Test-Path -LiteralPath $StatePath)) {
    return [pscustomobject]@{ Label = '未启动'; Connected = $false }
  }
  try {
    $state = Read-DreamSkinState -Path $StatePath
    if ($state.session -ceq 'paused') {
      return [pscustomobject]@{ Label = '原版模式'; Connected = $false }
    }
    if (Test-DreamSkinRecordedInjector -State $state) {
      return [pscustomobject]@{ Label = 'Codex 已连接'; Connected = $true }
    }

    $port = if ($state.port) { [int]$state.port } else { 9335 }
    $codex = Get-DreamSkinCodexInstallFromState -State $state
    if ($null -eq $codex) {
      try { $codex = Get-DreamSkinCodexInstall } catch {}
    }
    if ($null -ne $codex) {
      $identity = Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $codex
      $browserMatches = $null -ne $identity -and
        (-not $state.browserId -or "$($state.browserId)" -ceq $identity.BrowserId)
      if ($browserMatches) {
        return [pscustomobject]@{ Label = 'Codex 已连接'; Connected = $true }
      }
    }

  } catch {}
  return [pscustomobject]@{ Label = '等待连接'; Connected = $false }
}

function Get-RuntimeLabel {
  if ($null -eq $script:runtimeSnapshot) {
    $script:runtimeSnapshot = Get-ManagerRuntimeSnapshot
  }
  return [string]$script:runtimeSnapshot.Label
}

function Show-ManagerWindow {
  if ($null -eq $form -or $form.IsDisposed) { return }
  $form.ShowInTaskbar = $true
  if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
  }
  $form.Show()
  $form.Activate()
  $form.BringToFront()
}

function ConvertTo-ManagerProcessArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value.Contains([char]34) -or $Value.Contains([char]13) -or
      $Value.Contains([char]10) -or $Value.EndsWith('\')) {
    throw '更新进程参数包含不受支持的字符。'
  }
  if ($Value -notmatch '\s') { return $Value }
  return [char]34 + $Value + [char]34
}

function Start-HiddenManagerProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FileName
  $startInfo.Arguments = @($Arguments | ForEach-Object {
    ConvertTo-ManagerProcessArgument -Value ([string]$_)
  }) -join ' '
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw '更新后台进程未能启动。' }
  return $process
}

function Update-ManagerUpdateControls {
  $busy = $null -ne $script:updateProcess
  $available = $null -ne $script:updateInfo -and [bool]$script:updateInfo.updateAvailable
  $themeCount = if ($null -eq $script:updateInfo) { 0 } else { @($script:updateInfo.themes).Count }
  $label = if ($busy) {
    if ($script:updateOperation -ceq 'check') { '检查中...' } else { '更新中...' }
  } elseif ($available) {
    '更新 {0}' -f $script:updateInfo.version
  } elseif ($themeCount -gt 0) {
    '新主题 {0}' -f $themeCount
  } else {
    '检查更新'
  }

  if ($null -ne $checkUpdateHeaderButton) {
    $checkUpdateHeaderButton.Text = $label
    $checkUpdateHeaderButton.Enabled = -not $busy
    $checkUpdateHeaderButton.BackColor = if ($available -or $themeCount -gt 0) {
      $AccentColor
    } else {
      $SurfaceColor
    }
    $checkUpdateHeaderButton.ForeColor = if ($available -or $themeCount -gt 0) {
      [System.Drawing.Color]::White
    } else {
      $InkColor
    }
  }
  if ($null -ne $runtimeUpdateButton) {
    $runtimeUpdateButton.Text = $label
    $runtimeUpdateButton.Enabled = -not $busy
  }
  if ($null -ne $script:trayUpdateItem) {
    $script:trayUpdateItem.Text = $label
    $script:trayUpdateItem.Enabled = -not $busy
  }
}

function Start-ManagerUpdateCheck {
  param([bool]$Manual)
  if ($null -ne $script:updateProcess) { return }
  try {
    $node = (Get-DreamSkinNodeRuntime).Path
    if (-not (Test-Path -LiteralPath $UpdateClient)) {
      throw "更新客户端不存在：$UpdateClient"
    }
    $script:updateManualCheck = $Manual
    $script:updateOperation = 'check'
    $script:updateProcess = Start-HiddenManagerProcess -FileName $node -Arguments @(
      $UpdateClient,
      'check',
      '--feed',
      $UpdateFeedURL,
      '--current',
      $ManagerVersion
    )
    $statusLabel.Text = '正在验证软件和在线主题更新…'
    Update-ManagerUpdateControls
    $updateTimer.Start()
  } catch {
    $script:updateProcess = $null
    $script:updateOperation = $null
    $statusLabel.Text = '检查更新失败'
    if ($Manual) {
      [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        '检查更新失败',
        'OK',
        'Error'
      ) | Out-Null
    }
    Update-ManagerUpdateControls
  }
}

function Test-ManagerAutomaticUpdateCheckDue {
  if (-not (Test-Path -LiteralPath $UpdateCheckStatePath)) { return $true }
  try {
    $state = Get-Content -LiteralPath $UpdateCheckStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lastCheck = [DateTime]::Parse(
      [string]$state.checkedAt,
      [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::RoundtripKind
    )
    return (Get-Date).ToUniversalTime().Subtract($lastCheck.ToUniversalTime()).TotalHours -ge 24
  } catch {
    return $true
  }
}

function Start-ManagerUpdateDownload {
  if ($null -eq $script:updateInfo -or -not [bool]$script:updateInfo.updateAvailable -or
      $null -ne $script:updateProcess) {
    return
  }
  try {
    [IO.Directory]::CreateDirectory($UpdateRoot) | Out-Null
    $version = [string]$script:updateInfo.version
    if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
      throw '更新版本号格式无效。'
    }
    $installerPath = Join-Path $UpdateRoot "Codex-Skin-Manager-Setup-$version.exe"
    $node = (Get-DreamSkinNodeRuntime).Path
    $script:updateOperation = 'download'
    $script:updateProcess = Start-HiddenManagerProcess -FileName $node -Arguments @(
      $UpdateClient,
      'download',
      '--url',
      [string]$script:updateInfo.platform.url,
      '--output',
      $installerPath,
      '--sha256',
      [string]$script:updateInfo.platform.sha256,
      '--size',
      [string]$script:updateInfo.platform.size
    )
    $statusLabel.Text = "正在下载 Codex 皮肤管理器 $version…"
    Update-ManagerUpdateControls
    $updateTimer.Start()
  } catch {
    $script:updateProcess = $null
    $script:updateOperation = $null
    [System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      '更新下载失败',
      'OK',
      'Error'
    ) | Out-Null
    Update-ManagerUpdateControls
  }
}

function Start-OnlineThemeSync {
  if ($null -eq $script:updateInfo -or @($script:updateInfo.themes).Count -eq 0 -or
      $null -ne $script:updateProcess) {
    return
  }
  try {
    $syncScript = Join-Path $PSScriptRoot 'sync-online-themes.ps1'
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $script:updateOperation = 'themes'
    $script:updateProcess = Start-HiddenManagerProcess -FileName $powershell -Arguments @(
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      $syncScript,
      '-CheckResultPath',
      $UpdateCheckResultPath,
      '-ThemeRoot',
      $ThemeRoot
    )
    $statusLabel.Text = '正在下载并安装在线主题…'
    Update-ManagerUpdateControls
    $updateTimer.Start()
  } catch {
    $script:updateProcess = $null
    $script:updateOperation = $null
    [System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      '在线主题安装失败',
      'OK',
      'Error'
    ) | Out-Null
    Update-ManagerUpdateControls
  }
}

function Start-VerifiedManagerUpdateInstall {
  param([Parameter(Mandatory = $true)][string]$InstallerPath)
  $helper = Join-Path $PSScriptRoot 'install-update-windows.ps1'
  $version = [string]$script:updateInfo.version
  $escapedHelper = $helper.Replace("'", "''")
  $escapedInstaller = $InstallerPath.Replace("'", "''")
  $escapedVersion = $version.Replace("'", "''")
  $command = "& '$escapedHelper' -InstallerPath '$escapedInstaller' -Version '$escapedVersion' -ManagerPid $PID"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  Start-Process -FilePath $powershell -ArgumentList @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-EncodedCommand',
    $encoded
  ) -WindowStyle Hidden | Out-Null
  $script:explicitExit = $true
  $form.Close()
}

function Show-ManagerUpdateAction {
  if ($null -eq $script:updateInfo) {
    Start-ManagerUpdateCheck -Manual $true
    return
  }
  if ([bool]$script:updateInfo.updateAvailable) {
    $message = "发现 Codex 皮肤管理器 $($script:updateInfo.version)。" +
      [Environment]::NewLine + [Environment]::NewLine +
      '安装包会先完成签名、大小和 SHA-256 校验；Codex 与用户主题会保持不变。'
    $choice = [System.Windows.Forms.MessageBox]::Show(
      $message,
      '软件更新',
      'YesNo',
      'Information'
    )
    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
      Start-ManagerUpdateDownload
    }
    return
  }
  $themeCount = @($script:updateInfo.themes).Count
  if ($themeCount -gt 0) {
    $choice = [System.Windows.Forms.MessageBox]::Show(
      "发现 $themeCount 套官方在线主题，是否立即安装？",
      '在线主题更新',
      'YesNo',
      'Information'
    )
    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
      Start-OnlineThemeSync
    }
    return
  }
  [System.Windows.Forms.MessageBox]::Show(
    "当前版本 $ManagerVersion 已是最新版本。",
    '检查更新',
    'OK',
    'Information'
  ) | Out-Null
}

function Update-TrayState {
  if ($null -eq $script:trayIcon) { return }

  $runtimeLabelText = Get-RuntimeLabel
  $activeTheme = $script:themes |
    Where-Object Id -ceq $script:activeThemeId |
    Select-Object -First 1
  $activeThemeName = if ($null -eq $activeTheme) {
    '尚未选择'
  } else {
    [string]$activeTheme.Manifest.name
  }
  $script:trayStatusItem.Text = '实时状态：{0}' -f $runtimeLabelText
  $script:trayCurrentThemeItem.Text = '当前主题：{0}' -f $activeThemeName

  $tooltip = 'Codex 皮肤 · {0} · {1}' -f $activeThemeName, $runtimeLabelText
  if ($tooltip.Length -gt 63) { $tooltip = $tooltip.Substring(0, 63) }
  $script:trayIcon.Text = $tooltip

  $menuFingerprint = @(
    [string]$script:activeThemeId
    ($script:themes | ForEach-Object { '{0}:{1}' -f $_.Id, $_.Manifest.name }) -join '|'
  ) -join '||'
  if ($menuFingerprint -cne $script:trayMenuFingerprint) {
    foreach ($item in @($script:trayThemesMenu.DropDownItems)) { $item.Dispose() }
    $script:trayThemesMenu.DropDownItems.Clear()
    foreach ($theme in $script:themes) {
      $themeItem = New-Object System.Windows.Forms.ToolStripMenuItem
      $themeItem.Text = [string]$theme.Manifest.name
      $themeItem.Tag = [string]$theme.Id
      $themeItem.Checked = [string]$theme.Id -ceq [string]$script:activeThemeId
      $themeItem.Enabled = $null -eq $script:switchProcess -and -not $themeItem.Checked
      $themeItem.add_Click({
        param($sender, $eventArgs)
        Start-ThemeSwitch -ThemeId ([string]$sender.Tag)
      })
      [void]$script:trayThemesMenu.DropDownItems.Add($themeItem)
    }
    $script:trayMenuFingerprint = $menuFingerprint
  }

  $script:trayThemesMenu.Enabled = $script:themes.Count -gt 0 -and $null -eq $script:switchProcess
  $script:trayRestoreItem.Enabled = $script:activeThemeId -cne 'codex-default' -and
    $null -eq $script:switchProcess
  Update-ManagerUpdateControls
}

function Update-NavigationState {
  $allThemesButton.BackColor = if ($script:viewMode -ceq 'all') { $SidebarSelectedColor } else { $SidebarColor }
  $installedButton.BackColor = if ($script:viewMode -ceq 'installed') { $SidebarSelectedColor } else { $SidebarColor }
  $integrationButton.BackColor = if ($script:viewMode -ceq 'integration') { $SidebarSelectedColor } else { $SidebarColor }
  $runtimeButton.BackColor = if ($script:viewMode -ceq 'runtime') { $SidebarSelectedColor } else { $SidebarColor }
}

function Update-ActiveThemeBar {
  $activeTheme = $script:themes | Where-Object Id -ceq $script:activeThemeId | Select-Object -First 1
  if ($null -eq $activeTheme) {
    $activeThemeTitle.Text = '等待选择主题'
    $activeThemeDescription.Text = '从皮肤库选择一套主题开始使用。'
    $activeThemeMeta.Text = '{0} 套主题可用' -f $script:themes.Count
    $activeThemeRuntime.Text = Get-RuntimeLabel
    $restoreOriginalButton.Enabled = $false
    $activeThemePreview.Image = $null
    if ($null -ne $script:activeBannerImage) {
      $script:activeBannerImage.Dispose()
      $script:activeBannerImage = $null
    }
    return
  }

  $activeThemeTitle.Text = [string]$activeTheme.Manifest.name
  $description = Get-OptionalThemeText -Manifest $activeTheme.Manifest -Name 'description'
  if ([string]::IsNullOrWhiteSpace($description)) { $description = '完整 Codex 皮肤主题' }
  $activeThemeDescription.Text = $description
  $activeThemeMeta.Text = 'LIVE THEME  ·  {0} 套已安装' -f (
    @($script:themes | Where-Object {
      (Get-OptionalThemeText -Manifest $_.Manifest -Name 'mode') -cne 'original'
    }).Count
  )
  $activeThemeRuntime.Text = Get-RuntimeLabel
  $activeThemeRuntime.ForeColor = if ($activeThemeRuntime.Text -ceq 'Codex 已连接') {
    $SignalColor
  } elseif ($activeThemeRuntime.Text -ceq '原版模式') {
    $MutedColor
  } else {
    $GoldColor
  }
  $restoreOriginalButton.Enabled = $activeTheme.Id -cne 'codex-default' -and $null -eq $script:switchProcess

  if ($null -ne $script:activeBannerImage) {
    $activeThemePreview.Image = $null
    $script:activeBannerImage.Dispose()
    $script:activeBannerImage = $null
  }
  if (Test-Path -LiteralPath $activeTheme.Background) {
    try {
      $script:activeBannerImage = Get-ThemePreviewImage -Path $activeTheme.Background
      $activeThemePreview.Image = $script:activeBannerImage
    } catch {}
  }
}

function Update-HeaderState {
  $activeTheme = $script:themes | Where-Object Id -ceq $script:activeThemeId | Select-Object -First 1
  $activeName = if ($null -eq $activeTheme) { '尚未选择主题' } else { [string]$activeTheme.Manifest.name }
  switch ($script:viewMode) {
    'installed' {
      $pageEyebrow.Text = 'INSTALLED THEMES'
      $pageTitle.Text = '已安装主题'
      $pageSubtitle.Text = '查看、切换并维护本机主题。当前：{0}' -f $activeName
    }
    'integration' {
      $pageEyebrow.Text = 'THEME INTEGRATION'
      $pageTitle.Text = '主题接入'
      $pageSubtitle.Text = '创建或导入标准 schema 2 主题包。'
    }
    'runtime' {
      $pageEyebrow.Text = 'RUNTIME STATUS'
      $pageTitle.Text = '运行状态'
      $pageSubtitle.Text = '检查 Codex 连接、注入器与当前皮肤。'
    }
    default {
      $pageEyebrow.Text = 'SKIN MANAGER'
      $pageTitle.Text = '主题工作台'
      $pageSubtitle.Text = '浏览真实效果，选择下一套 Codex 工作氛围。'
    }
  }
  $runtimeLabel.Text = Get-RuntimeLabel
  $runtimeLabel.ForeColor = if ($runtimeLabel.Text -ceq 'Codex 已连接') {
    $SignalColor
  } elseif ($runtimeLabel.Text -ceq '原版模式') {
    $MutedColor
  } else {
    $GoldColor
  }
  $runtimeConnectionValue.Text = $runtimeLabel.Text
  $runtimeThemeValue.Text = $activeName
  $runtimeCountValue.Text = '{0} 套' -f $script:themes.Count
  Update-ActiveThemeBar
}

function Set-ApplyButtonsEnabled {
  param([bool]$Enabled)
  foreach ($button in $script:applyButtons) {
    $isActive = [string]$button.Tag -ceq [string]$script:activeThemeId
    $isSwitchingThis = -not $Enabled -and [string]$button.Tag -ceq [string]$script:switchThemeId
    # Disabled WinForms buttons ignore custom foreground colors.
    $button.Enabled = -not $isActive
    if ($isActive) {
      $button.Text = '当前使用'
      $button.BackColor = $SignalSoftColor
      $button.ForeColor = $SignalColor
      $button.FlatAppearance.BorderSize = 1
      $button.FlatAppearance.BorderColor = $SignalColor
    } elseif ($isSwitchingThis) {
      $button.Text = '切换中...'
      $button.BackColor = $AccentColor
      $button.ForeColor = [System.Drawing.Color]::White
      $button.FlatAppearance.BorderSize = 0
    } elseif (-not $Enabled) {
      $button.Text = '请稍候'
      $button.BackColor = [System.Drawing.Color]::FromArgb(235, 239, 238)
      $button.ForeColor = [System.Drawing.Color]::FromArgb(73, 84, 89)
      $button.FlatAppearance.BorderSize = 1
      $button.FlatAppearance.BorderColor = $LineColor
    } else {
      $button.Text = '一键切换'
      $button.BackColor = $InkColor
      $button.ForeColor = [System.Drawing.Color]::White
      $button.FlatAppearance.BorderSize = 0
    }
  }
  if ($null -ne $restoreOriginalButton) {
    $restoreOriginalButton.Enabled = $Enabled -and $script:activeThemeId -cne 'codex-default'
    $runtimeRestoreButton.Enabled = $restoreOriginalButton.Enabled
  }
}

function New-ThemeCard {
  param([Parameter(Mandatory = $true)]$Theme)

  $isActive = [string]$Theme.Id -ceq [string]$script:activeThemeId
  $card = New-Object System.Windows.Forms.Panel
  $card.Size = New-Object System.Drawing.Size(278, 270)
  $card.Margin = New-Object System.Windows.Forms.Padding(8)
  $card.BackColor = $SurfaceColor
  $card.Tag = $Theme.Id
  $card.add_Paint({
    param($sender, $eventArgs)
    $active = [string]$sender.Tag -ceq [string]$script:activeThemeId
    $penColor = if ($active) { $SignalColor } else { $LineColor }
    $penWidth = if ($active) { 2 } else { 1 }
    $pen = New-Object System.Drawing.Pen($penColor, $penWidth)
    try {
      $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    } finally {
      $pen.Dispose()
    }
  })

  $preview = New-Object System.Windows.Forms.PictureBox
  $preview.Location = New-Object System.Drawing.Point(8, 8)
  $preview.Size = New-Object System.Drawing.Size(262, 87)
  $preview.SizeMode = 'Zoom'
  $preview.BackColor = $SidebarColor
  try {
    $preview.Image = Get-ThemePreviewImage -Path $Theme.Preview
    $script:themeImages += $preview.Image
  } catch {}
  $card.Controls.Add($preview)

  $badge = New-Object System.Windows.Forms.Label
  $badge.AutoSize = $false
  $badge.Size = New-Object System.Drawing.Size(48, 22)
  $badge.Location = New-Object System.Drawing.Point(14, 14)
  $badge.TextAlign = 'MiddleCenter'
  $badge.Text = if ($Theme.IsBuiltIn) { '内置' } else { '自定义' }
  $badge.BackColor = if ($Theme.IsBuiltIn) { $GoldColor } else { $AccentColor }
  $badge.ForeColor = [System.Drawing.Color]::White
  $badge.Font = New-Object System.Drawing.Font($FontName, 8, [System.Drawing.FontStyle]::Bold)
  $badge.Parent = $preview
  $badge.BringToFront()

  if ($isActive) {
    $activeBadge = New-Object System.Windows.Forms.Label
    $activeBadge.AutoSize = $false
    $activeBadge.Size = New-Object System.Drawing.Size(58, 22)
    $activeBadge.Location = New-Object System.Drawing.Point(197, 14)
    $activeBadge.TextAlign = 'MiddleCenter'
    $activeBadge.Text = '当前'
    $activeBadge.BackColor = $SignalColor
    $activeBadge.ForeColor = [System.Drawing.Color]::White
    $activeBadge.Font = New-Object System.Drawing.Font($FontName, 8, [System.Drawing.FontStyle]::Bold)
    $activeBadge.Parent = $preview
    $activeBadge.BringToFront()
  }

  $name = New-Object System.Windows.Forms.Label
  $name.Location = New-Object System.Drawing.Point(12, 105)
  $name.Size = New-Object System.Drawing.Size(252, 25)
  $name.Text = [string]$Theme.Manifest.name
  $name.Font = New-Object System.Drawing.Font($FontName, 11, [System.Drawing.FontStyle]::Bold)
  $name.ForeColor = $InkColor
  $name.AutoEllipsis = $true
  $card.Controls.Add($name)

  $author = New-Object System.Windows.Forms.Label
  $author.Location = New-Object System.Drawing.Point(12, 131)
  $author.Size = New-Object System.Drawing.Size(252, 18)
  $authorText = Get-OptionalThemeText -Manifest $Theme.Manifest -Name 'author'
  if ([string]::IsNullOrWhiteSpace($authorText)) {
    $authorText = if ($Theme.IsBuiltIn) { 'Codex 皮肤管理器' } else { '本地创作者' }
  }
  $author.Text = 'by ' + $authorText
  $author.Font = New-Object System.Drawing.Font($FontName, 8)
  $author.ForeColor = $MutedColor
  $author.AutoEllipsis = $true
  $card.Controls.Add($author)

  $description = New-Object System.Windows.Forms.Label
  $description.Location = New-Object System.Drawing.Point(12, 153)
  $description.Size = New-Object System.Drawing.Size(252, 38)
  $description.Text = Get-OptionalThemeText -Manifest $Theme.Manifest -Name 'description'
  $description.Font = New-Object System.Drawing.Font($FontName, 8.5)
  $description.ForeColor = $MutedColor
  $description.AutoEllipsis = $true
  $card.Controls.Add($description)

  $meta = New-Object System.Windows.Forms.Label
  $meta.Location = New-Object System.Drawing.Point(12, 196)
  $meta.Size = New-Object System.Drawing.Size(252, 20)
  $category = Get-OptionalThemeText -Manifest $Theme.Manifest -Name 'category'
  if ([string]::IsNullOrWhiteSpace($category)) { $category = '主题' }
  $meta.Text = '{0}  ·  {1}' -f $category, (Get-ThemeAppearanceLabel -Manifest $Theme.Manifest)
  $meta.Font = New-Object System.Drawing.Font($FontName, 8.2)
  $meta.ForeColor = $MutedColor
  $card.Controls.Add($meta)

  $applyButton = New-ManagerButton -Text $(if ($isActive) { '当前使用' } else { '一键切换' }) -Width 252
  $applyButton.Location = New-Object System.Drawing.Point(12, 224)
  $applyButton.Height = 34
  $applyButton.Tag = $Theme.Id
  if ($isActive) {
    $applyButton.Enabled = $false
    $applyButton.BackColor = $SignalSoftColor
    $applyButton.ForeColor = $SignalColor
    $applyButton.FlatAppearance.BorderColor = $SignalColor
  } else {
    $applyButton.BackColor = $InkColor
    $applyButton.ForeColor = [System.Drawing.Color]::White
    $applyButton.FlatAppearance.BorderSize = 0
  }
  $applyButton.add_Click({
    param($sender, $eventArgs)
    Start-ThemeSwitch -ThemeId ([string]$sender.Tag)
  })
  $script:applyButtons += $applyButton
  $card.Controls.Add($applyButton)
  return $card
}

function New-ThemeActionCard {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('create', 'import')][string]$Action
  )

  $isCreate = $Action -ceq 'create'
  $card = New-Object System.Windows.Forms.Panel
  $card.Size = New-Object System.Drawing.Size(278, 270)
  $card.Margin = New-Object System.Windows.Forms.Padding(8)
  $card.BackColor = $SurfaceColor
  $card.add_Paint({
    param($sender, $eventArgs)
    $pen = New-Object System.Drawing.Pen($LineColor, 1)
    try {
      $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    } finally {
      $pen.Dispose()
    }
  })

  $iconSurface = New-Object System.Windows.Forms.Panel
  $iconSurface.Location = New-Object System.Drawing.Point(8, 8)
  $iconSurface.Size = New-Object System.Drawing.Size(262, 87)
  $iconSurface.BackColor = if ($isCreate) {
    [System.Drawing.Color]::FromArgb(253, 239, 236)
  } else {
    [System.Drawing.Color]::FromArgb(231, 242, 239)
  }
  $card.Controls.Add($iconSurface)

  $icon = New-Object System.Windows.Forms.Label
  $icon.Dock = 'Fill'
  $icon.TextAlign = 'MiddleCenter'
  $icon.Text = if ($isCreate) { [string][char]0xE710 } else { [string][char]0xE8B7 }
  $icon.Font = New-Object System.Drawing.Font('Segoe MDL2 Assets', 26)
  $icon.ForeColor = if ($isCreate) { $AccentColor } else { $SignalColor }
  $iconSurface.Controls.Add($icon)

  $title = New-Object System.Windows.Forms.Label
  $title.Location = New-Object System.Drawing.Point(12, 108)
  $title.Size = New-Object System.Drawing.Size(252, 28)
  $title.Text = if ($isCreate) { '创建自定义主题' } else { '导入本地主题' }
  $title.Font = New-Object System.Drawing.Font($FontName, 11, [System.Drawing.FontStyle]::Bold)
  $title.ForeColor = $InkColor
  $card.Controls.Add($title)

  $description = New-Object System.Windows.Forms.Label
  $description.Location = New-Object System.Drawing.Point(12, 142)
  $description.Size = New-Object System.Drawing.Size(252, 48)
  $description.Text = if ($isCreate) {
    '选择背景、配色和外观模式，生成标准主题包。'
  } else {
    '载入符合 schema 2 格式的完整主题文件夹。'
  }
  $description.Font = New-Object System.Drawing.Font($FontName, 8.5)
  $description.ForeColor = $MutedColor
  $card.Controls.Add($description)

  $meta = New-Object System.Windows.Forms.Label
  $meta.Location = New-Object System.Drawing.Point(12, 196)
  $meta.Size = New-Object System.Drawing.Size(252, 20)
  $meta.Text = '主题工具  ·  本机'
  $meta.Font = New-Object System.Drawing.Font($FontName, 8.2)
  $meta.ForeColor = $MutedColor
  $card.Controls.Add($meta)

  $actionButton = New-ManagerButton `
    -Text $(if ($isCreate) { '开始创建' } else { '选择文件夹' }) `
    -Width 252 `
    -Primary:$isCreate
  $actionButton.Location = New-Object System.Drawing.Point(12, 224)
  $actionButton.Height = 34
  if (-not $isCreate) {
    $actionButton.BackColor = $SignalColor
    $actionButton.ForeColor = [System.Drawing.Color]::White
    $actionButton.FlatAppearance.BorderSize = 0
  }
  if ($isCreate) {
    $actionButton.add_Click({
      if (Show-ThemeCreator -Owner $form) {
        Reload-ThemeLibrary
        $statusLabel.Text = '主题创建完成'
      }
    })
  } else {
    $actionButton.add_Click({ Import-ThemeFromFolder })
  }
  $card.Controls.Add($actionButton)
  return $card
}

function Update-ThemeCards {
  $themeFlow.SuspendLayout()
  try {
    foreach ($control in @($themeFlow.Controls)) {
      if ($control -ne $emptyLabel) { $control.Dispose() }
    }
    $themeFlow.Controls.Clear()
    foreach ($image in $script:themeImages) { if ($null -ne $image) { $image.Dispose() } }
    $script:themeImages = @()
    $script:applyButtons = @()
    $needle = $searchBox.Text.Trim()
    $visible = @($script:themes | Where-Object {
      $theme = $_
      $matchesMode = $script:viewMode -ceq 'all' -or
        (Get-OptionalThemeText -Manifest $theme.Manifest -Name 'mode') -cne 'original'
      $haystack = @(
        [string]$theme.Manifest.name
        (Get-OptionalThemeText -Manifest $theme.Manifest -Name 'description')
        (Get-OptionalThemeText -Manifest $theme.Manifest -Name 'category')
        (Get-OptionalThemeText -Manifest $theme.Manifest -Name 'author')
      ) -join ' '
      $matchesMode -and ([string]::IsNullOrWhiteSpace($needle) -or
        $haystack.IndexOf($needle, [System.StringComparison]::CurrentCultureIgnoreCase) -ge 0)
    })
    foreach ($theme in $visible) {
      [void]$themeFlow.Controls.Add((New-ThemeCard -Theme $theme))
    }
    if ([string]::IsNullOrWhiteSpace($needle)) {
      if ($script:viewMode -ceq 'all') {
        [void]$themeFlow.Controls.Add((New-ThemeActionCard -Action 'create'))
      } elseif ($script:viewMode -ceq 'installed') {
        [void]$themeFlow.Controls.Add((New-ThemeActionCard -Action 'create'))
        [void]$themeFlow.Controls.Add((New-ThemeActionCard -Action 'import'))
      }
    }
    $emptyLabel.Visible = $visible.Count -eq 0
    if ($visible.Count -eq 0) { [void]$themeFlow.Controls.Add($emptyLabel) }
    $libraryTitle.Text = if ($script:viewMode -ceq 'installed') { '已安装' } else { '皮肤库' }
    $libraryCount.Text = '{0} 个外观可用' -f $visible.Count
    $statusLabel.Text = if ($visible.Count -eq 0) {
      '没有符合条件的主题'
    } else {
      '显示 {0} 套主题' -f $visible.Count
    }
  } finally {
    $themeFlow.ResumeLayout()
  }
}

function Get-ThemeLibraryFingerprint {
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($directory in @(Get-ChildItem -LiteralPath $ThemeRoot -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name)) {
    $parts.Add($directory.Name)
    foreach ($fileName in @('theme.json', 'background.png', 'preview.png')) {
      $file = Get-Item -LiteralPath (Join-Path $directory.FullName $fileName) `
        -ErrorAction SilentlyContinue
      if ($null -eq $file) {
        $parts.Add("$fileName`:missing")
      } else {
        $parts.Add("$fileName`:$($file.Length)`:$($file.LastWriteTimeUtc.Ticks)")
      }
    }
  }
  $marker = Get-Item -LiteralPath (Join-Path (Split-Path -Parent $ThemeRoot) 'theme-library.changed') `
    -ErrorAction SilentlyContinue
  if ($null -ne $marker) {
    $parts.Add("marker`:$($marker.Length)`:$($marker.LastWriteTimeUtc.Ticks)")
  }
  return $parts -join '|'
}

function Reload-ThemeLibrary {
  New-Item -ItemType Directory -Force -Path $ThemeRoot | Out-Null
  $script:themes = @()
  foreach ($directory in @(Get-ChildItem -LiteralPath $ThemeRoot -Directory -ErrorAction SilentlyContinue)) {
    $manifestPath = Join-Path $directory.FullName 'theme.json'
    $previewPath = Join-Path $directory.FullName 'preview.png'
    if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $previewPath)) {
      continue
    }
    try {
      $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($manifest.schemaVersion -ne 2 -or [string]$manifest.id -cne $directory.Name) { continue }
      $script:themes += [pscustomobject]@{
        Id = $directory.Name
        Manifest = $manifest
        Preview = $previewPath
        Background = Join-Path $directory.FullName 'background.png'
        IsBuiltIn = $DreamSkinBuiltInThemeIds -ccontains $directory.Name
      }
    } catch {}
  }
  $script:themes = @($script:themes | Sort-Object @{
    Expression = {
      $index = [Array]::IndexOf($themeOrder, [string]$_.Id)
      if ($index -lt 0) { $themeOrder.Count } else { $index }
    }
  }, @{ Expression = { [string]$_.Manifest.name } })
  $script:activeThemeId = Get-ActiveThemeId
  $script:runtimeSnapshot = Get-ManagerRuntimeSnapshot
  $script:themeLibraryFingerprint = Get-ThemeLibraryFingerprint
  Update-HeaderState
  Update-NavigationState
  Update-ThemeCards
  Update-TrayState
}

function Get-ThemeSwitchFailureMessage {
  param([string]$ErrorText, [string]$OutputText, [int]$ExitCode)

  $message = if (-not [string]::IsNullOrWhiteSpace($ErrorText)) {
    $ErrorText.Trim()
  } elseif (-not [string]::IsNullOrWhiteSpace($OutputText)) {
    $OutputText.Trim()
  } else {
    '主题切换脚本退出代码：{0}' -f $ExitCode
  }
  if ($message.Contains('#< CLIXML')) {
    try {
      $serialized = $message.Substring($message.IndexOf('#< CLIXML') + 9).Trim()
      $items = @([System.Management.Automation.PSSerializer]::Deserialize($serialized))
      $decoded = @($items | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join "`r`n"
      if (-not [string]::IsNullOrWhiteSpace($decoded)) { $message = $decoded }
    } catch {
      $message = '主题选择已保存，但实时应用没有完成。请刷新状态后重试。'
    }
  }
  if ($message.Length -gt 1200) {
    $message = $message.Substring($message.Length - 1200)
  }
  return $message
}

function Start-ThemeSwitch {
  param([Parameter(Mandatory = $true)][string]$ThemeId)
  if ($null -ne $script:switchProcess) { return }

  try {
    $escapedScript = $SwitchScript.Replace("'", "''")
    $escapedThemeId = $ThemeId.Replace("'", "''")
    $command = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding(`$false)
try {
  & '$escapedScript' -ThemeId '$escapedThemeId'
  exit 0
} catch {
  [Console]::Error.WriteLine(`$_.Exception.Message)
  exit 1
}
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershell
    $startInfo.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand {0}' -f $encoded
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw '主题切换进程未能启动。' }
    $script:switchProcess = $process
    $script:switchThemeId = $ThemeId
    $selectedTheme = $script:themes | Where-Object Id -ceq $ThemeId | Select-Object -First 1
    $statusLabel.Text = '正在应用：{0}' -f $selectedTheme.Manifest.name
    Set-ApplyButtonsEnabled -Enabled $false
    Update-TrayState
    $switchTimer.Start()
  } catch {
    $script:switchProcess = $null
    $script:switchThemeId = $null
    Set-ApplyButtonsEnabled -Enabled $true
    [System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      '主题切换失败',
      'OK',
      'Error'
    ) | Out-Null
  }
}

function Import-ThemeFromFolder {
  $picker = New-Object System.Windows.Forms.FolderBrowserDialog
  $picker.Description = '选择包含 theme.json、background.png 和 preview.png 的主题文件夹'
  try {
    if ($picker.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $package = Assert-DreamSkinThemePackage -Path $picker.SelectedPath
    $themeId = [string]$package.Manifest.id
    if ($DreamSkinBuiltInThemeIds -ccontains $themeId) {
      throw '内置主题 ID 受保护，请更换 theme.json 中的 id。'
    }
    $destination = Join-Path $ThemeRoot $themeId
    $replace = Test-Path -LiteralPath $destination
    if ($replace) {
      $choice = [System.Windows.Forms.MessageBox]::Show(
        '相同 ID 的主题已经存在，继续会替换原主题包。',
        '替换现有主题？',
        'YesNo',
        'Warning'
      )
      if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    Install-DreamSkinThemePackage -Package $package -ThemeRoot $ThemeRoot -Replace:$replace
    Reload-ThemeLibrary
    $statusLabel.Text = '已导入：{0}' -f $package.Manifest.name
  } catch {
    [System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      '导入主题失败',
      'OK',
      'Error'
    ) | Out-Null
  } finally {
    $picker.Dispose()
  }
}

function New-RuntimeMetricPanel {
  param(
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Caption,
    [Parameter(Mandatory = $true)][System.Drawing.Color]$Tone
  )

  $panel = New-Object System.Windows.Forms.Panel
  $panel.Size = New-Object System.Drawing.Size(286, 118)
  $panel.Margin = New-Object System.Windows.Forms.Padding(8)
  $panel.BackColor = $SurfaceColor
  $panel.add_Paint({
    param($sender, $eventArgs)
    $pen = New-Object System.Drawing.Pen($LineColor, 1)
    try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) } finally {
      $pen.Dispose()
    }
  })

  $marker = New-Object System.Windows.Forms.Panel
  $marker.Location = New-Object System.Drawing.Point(18, 20)
  $marker.Size = New-Object System.Drawing.Size(8, 46)
  $marker.BackColor = $Tone
  $panel.Controls.Add($marker)

  $titleLabel = New-Object System.Windows.Forms.Label
  $titleLabel.Location = New-Object System.Drawing.Point(40, 18)
  $titleLabel.Size = New-Object System.Drawing.Size(220, 20)
  $titleLabel.Text = $Title
  $titleLabel.ForeColor = $MutedColor
  $panel.Controls.Add($titleLabel)

  $valueLabel = New-Object System.Windows.Forms.Label
  $valueLabel.Location = New-Object System.Drawing.Point(40, 44)
  $valueLabel.Size = New-Object System.Drawing.Size(220, 31)
  $valueLabel.Text = $Caption
  $valueLabel.Font = New-Object System.Drawing.Font($FontName, 14, [System.Drawing.FontStyle]::Bold)
  $valueLabel.ForeColor = $InkColor
  $valueLabel.AutoEllipsis = $true
  $panel.Controls.Add($valueLabel)

  $detailLabel = New-Object System.Windows.Forms.Label
  $detailLabel.Location = New-Object System.Drawing.Point(40, 82)
  $detailLabel.Size = New-Object System.Drawing.Size(220, 18)
  $detailLabel.Text = '本机状态'
  $detailLabel.Font = New-Object System.Drawing.Font($FontName, 8)
  $detailLabel.ForeColor = $MutedColor
  $panel.Controls.Add($detailLabel)
  $panel.Tag = $valueLabel
  return $panel
}

function Update-ThemeSkillState {
  $current = $false
  try {
    $current = Test-DreamSkinThemeSkillCurrent -EngineRoot $EngineRoot
  } catch {}
  $skillStatusLabel.Text = if ($current) { '已安装' } else { '需要安装' }
  $skillStatusLabel.ForeColor = if ($current) { $SignalColor } else { $GoldColor }
  $skillStatusLabel.BackColor = if ($current) {
    $SignalSoftColor
  } else {
    [System.Drawing.Color]::FromArgb(251, 242, 223)
  }
  $skillInstallButton.Text = if ($current) { '重新安装' } else { '安装 Skill' }
}

function Set-ManagerView {
  param([Parameter(Mandatory = $true)][ValidateSet('all', 'installed', 'integration', 'runtime')][string]$Mode)
  $script:viewMode = $Mode
  $showLibrary = $Mode -in @('all', 'installed')
  $activeThemePanel.Visible = $showLibrary
  $libraryToolbar.Visible = $showLibrary
  $themeFlow.Visible = $showLibrary
  $integrationPanel.Visible = $Mode -ceq 'integration'
  $runtimePanel.Visible = $Mode -ceq 'runtime'
  Update-NavigationState
  Update-HeaderState
  if ($showLibrary) { Update-ThemeCards }
  if ($Mode -ceq 'integration') {
    Update-ThemeSkillState
    $statusLabel.Text = '主题包格式：theme.json + background.png + preview.png'
  } elseif ($Mode -ceq 'runtime') {
    $statusLabel.Text = '运行状态已刷新'
  }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex 皮肤管理器'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(1280, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1100, 700)
$form.BackColor = $CanvasColor
$form.Font = New-Object System.Drawing.Font($FontName, 9)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Icon = if (Test-Path (Join-Path $EngineRoot 'assets\DreamSkinAppIcon.ico')) {
  New-Object System.Drawing.Icon((Join-Path $EngineRoot 'assets\DreamSkinAppIcon.ico'))
} else { $null }

$script:trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:trayMenu.ShowImageMargin = $false
$script:trayStatusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:trayStatusItem.Enabled = $false
$script:trayCurrentThemeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:trayCurrentThemeItem.Enabled = $false
$script:trayThemesMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$script:trayThemesMenu.Text = '快速切换主题'
$trayOpenManagerItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayOpenManagerItem.Text = '打开管理器'
$trayOpenCodexItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayOpenCodexItem.Text = '打开 Codex'
$script:trayRestoreItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:trayRestoreItem.Text = '恢复 Codex 原版'
$script:trayUpdateItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:trayUpdateItem.Text = '检查更新'
$trayExitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayExitItem.Text = '退出皮肤管理器'
[void]$script:trayMenu.Items.Add($script:trayStatusItem)
[void]$script:trayMenu.Items.Add($script:trayCurrentThemeItem)
[void]$script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:trayMenu.Items.Add($script:trayThemesMenu)
[void]$script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:trayMenu.Items.Add($trayOpenManagerItem)
[void]$script:trayMenu.Items.Add($trayOpenCodexItem)
[void]$script:trayMenu.Items.Add($script:trayRestoreItem)
[void]$script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:trayMenu.Items.Add($script:trayUpdateItem)
[void]$script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:trayMenu.Items.Add($trayExitItem)

$script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
$script:trayIcon.Icon = if ($null -ne $form.Icon) {
  $form.Icon
} else {
  [System.Drawing.SystemIcons]::Application
}
$script:trayIcon.Text = 'Codex 皮肤管理器'
$script:trayIcon.ContextMenuStrip = $script:trayMenu
$script:trayIcon.Visible = $true
$script:trayIcon.add_DoubleClick({ Show-ManagerWindow })
$trayOpenManagerItem.add_Click({ Show-ManagerWindow })

$main = New-Object System.Windows.Forms.Panel
$main.Dock = 'Fill'
$main.BackColor = $CanvasColor
$form.Controls.Add($main)

$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = 'Left'
$sidebar.Width = 236
$sidebar.BackColor = $SidebarColor
$form.Controls.Add($sidebar)

$contentLayout = New-Object System.Windows.Forms.TableLayoutPanel
$contentLayout.Dock = 'Fill'
$contentLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$contentLayout.Padding = New-Object System.Windows.Forms.Padding(0)
$contentLayout.ColumnCount = 1
$contentLayout.RowCount = 5
$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle(
  [System.Windows.Forms.SizeType]::Percent,
  100
))) | Out-Null
$contentLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
  [System.Windows.Forms.SizeType]::Absolute,
  112
))) | Out-Null
$contentLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
  [System.Windows.Forms.SizeType]::Absolute,
  160
))) | Out-Null
$contentLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
  [System.Windows.Forms.SizeType]::Absolute,
  58
))) | Out-Null
$contentLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
  [System.Windows.Forms.SizeType]::Percent,
  100
))) | Out-Null
$contentLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
  [System.Windows.Forms.SizeType]::Absolute,
  50
))) | Out-Null
$main.Controls.Add($contentLayout)

$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Object System.Drawing.Point(20, 22)
$logo.Size = New-Object System.Drawing.Size(42, 42)
$logo.SizeMode = 'Zoom'
$iconPng = Join-Path $EngineRoot 'assets\DreamSkinAppIcon.png'
if (Test-Path -LiteralPath $iconPng) {
  try { $logo.Image = Get-ThemePreviewImage -Path $iconPng } catch {}
}
$sidebar.Controls.Add($logo)

$brand = New-Object System.Windows.Forms.Label
$brand.Location = New-Object System.Drawing.Point(72, 22)
$brand.Size = New-Object System.Drawing.Size(152, 25)
$brand.Text = 'Codex 皮肤'
$brand.Font = New-Object System.Drawing.Font($FontName, 13, [System.Drawing.FontStyle]::Bold)
$brand.ForeColor = [System.Drawing.Color]::White
$sidebar.Controls.Add($brand)

$brandSubtitle = New-Object System.Windows.Forms.Label
$brandSubtitle.Location = New-Object System.Drawing.Point(73, 48)
$brandSubtitle.Size = New-Object System.Drawing.Size(140, 18)
$brandSubtitle.Text = '主题一键切换工具'
$brandSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(155, 165, 164)
$sidebar.Controls.Add($brandSubtitle)

$navTitle = New-Object System.Windows.Forms.Label
$navTitle.Location = New-Object System.Drawing.Point(24, 92)
$navTitle.Size = New-Object System.Drawing.Size(170, 20)
$navTitle.Text = '主题'
$navTitle.ForeColor = [System.Drawing.Color]::FromArgb(118, 128, 128)
$navTitle.Font = New-Object System.Drawing.Font($FontName, 8, [System.Drawing.FontStyle]::Bold)
$sidebar.Controls.Add($navTitle)

$allThemesButton = New-SidebarButton -Text '皮肤库' -Top 116
$installedButton = New-SidebarButton -Text '已安装' -Top 162
$integrationButton = New-SidebarButton -Text '主题接入' -Top 208
$runtimeButton = New-SidebarButton -Text '运行状态' -Top 254
$sidebar.Controls.AddRange(@($allThemesButton, $installedButton, $integrationButton, $runtimeButton))

$createTitle = New-Object System.Windows.Forms.Label
$createTitle.Location = New-Object System.Drawing.Point(24, 316)
$createTitle.Size = New-Object System.Drawing.Size(170, 20)
$createTitle.Text = '创作'
$createTitle.ForeColor = [System.Drawing.Color]::FromArgb(118, 128, 128)
$createTitle.Font = New-Object System.Drawing.Font($FontName, 8, [System.Drawing.FontStyle]::Bold)
$sidebar.Controls.Add($createTitle)

$createSidebarButton = New-SidebarButton -Text '创建主题' -Top 340
$importSidebarButton = New-SidebarButton -Text '导入主题' -Top 386
$sidebar.Controls.AddRange(@($createSidebarButton, $importSidebarButton))

$utilityTitle = New-Object System.Windows.Forms.Label
$utilityTitle.Location = New-Object System.Drawing.Point(24, 448)
$utilityTitle.Size = New-Object System.Drawing.Size(170, 20)
$utilityTitle.Text = '工具'
$utilityTitle.ForeColor = [System.Drawing.Color]::FromArgb(118, 128, 128)
$utilityTitle.Font = New-Object System.Drawing.Font($FontName, 8, [System.Drawing.FontStyle]::Bold)
$sidebar.Controls.Add($utilityTitle)

$dataButton = New-SidebarButton -Text '打开主题目录' -Top 472
$openCodexButton = New-SidebarButton -Text '打开 Codex' -Top 518
$sidebar.Controls.AddRange(@($dataButton, $openCodexButton))

$sidebarStatus = New-Object System.Windows.Forms.Label
$sidebarStatus.Anchor = 'Left,Bottom'
$sidebarStatus.Location = New-Object System.Drawing.Point(24, 750)
$sidebarStatus.Size = New-Object System.Drawing.Size(180, 42)
$sidebarStatus.Text = "安全注入 · 本机回环`r`nWindows v$ManagerVersion"
$sidebarStatus.ForeColor = [System.Drawing.Color]::FromArgb(135, 146, 144)
$sidebarStatus.Font = New-Object System.Drawing.Font($FontName, 8)
$sidebar.Controls.Add($sidebarStatus)

$pageHeader = New-Object System.Windows.Forms.Panel
$pageHeader.Dock = 'Fill'
$pageHeader.Margin = New-Object System.Windows.Forms.Padding(0)
$pageHeader.BackColor = $SurfaceColor
$contentLayout.Controls.Add($pageHeader, 0, 0)

$pageAccent = New-Object System.Windows.Forms.Panel
$pageAccent.Location = New-Object System.Drawing.Point(28, 25)
$pageAccent.Size = New-Object System.Drawing.Size(5, 62)
$pageAccent.BackColor = $AccentColor
$pageHeader.Controls.Add($pageAccent)

$pageEyebrow = New-Object System.Windows.Forms.Label
$pageEyebrow.Location = New-Object System.Drawing.Point(48, 17)
$pageEyebrow.Size = New-Object System.Drawing.Size(420, 18)
$pageEyebrow.Text = 'SKIN MANAGER'
$pageEyebrow.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$pageEyebrow.ForeColor = $MutedColor
$pageHeader.Controls.Add($pageEyebrow)

$pageTitle = New-Object System.Windows.Forms.Label
$pageTitle.Location = New-Object System.Drawing.Point(48, 37)
$pageTitle.Size = New-Object System.Drawing.Size(520, 34)
$pageTitle.Text = '主题工作台'
$pageTitle.Font = New-Object System.Drawing.Font($FontName, 21, [System.Drawing.FontStyle]::Bold)
$pageTitle.ForeColor = $InkColor
$pageHeader.Controls.Add($pageTitle)

$pageSubtitle = New-Object System.Windows.Forms.Label
$pageSubtitle.Location = New-Object System.Drawing.Point(49, 76)
$pageSubtitle.Size = New-Object System.Drawing.Size(650, 22)
$pageSubtitle.ForeColor = $MutedColor
$pageSubtitle.AutoEllipsis = $true
$pageHeader.Controls.Add($pageSubtitle)

$checkUpdateHeaderButton = New-ManagerButton -Text '检查更新' -Width 104
$checkUpdateHeaderButton.Anchor = 'Top,Right'
$checkUpdateHeaderButton.Location = New-Object System.Drawing.Point(680, 38)
$pageHeader.Controls.Add($checkUpdateHeaderButton)

$refreshHeaderButton = New-ManagerButton -Text '刷新' -Width 88
$refreshHeaderButton.Anchor = 'Top,Right'
$refreshHeaderButton.Location = New-Object System.Drawing.Point(796, 38)
$pageHeader.Controls.Add($refreshHeaderButton)

$createHeaderButton = New-ManagerButton -Text '创建主题' -Width 112 -Primary
$createHeaderButton.Anchor = 'Top,Right'
$createHeaderButton.Location = New-Object System.Drawing.Point(896, 38)
$pageHeader.Controls.Add($createHeaderButton)

$activeThemePanel = New-Object System.Windows.Forms.Panel
$activeThemePanel.Dock = 'Fill'
$activeThemePanel.Margin = New-Object System.Windows.Forms.Padding(24, 10, 24, 8)
$activeThemePanel.BackColor = $SurfaceColor
$activeThemePanel.add_Paint({
  param($sender, $eventArgs)
  $pen = New-Object System.Drawing.Pen($LineColor, 1)
  try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) } finally {
    $pen.Dispose()
  }
})
$contentLayout.Controls.Add($activeThemePanel, 0, 1)

$activeThemeMeta = New-Object System.Windows.Forms.Label
$activeThemeMeta.Location = New-Object System.Drawing.Point(22, 13)
$activeThemeMeta.Size = New-Object System.Drawing.Size(430, 18)
$activeThemeMeta.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$activeThemeMeta.ForeColor = $SignalColor
$activeThemePanel.Controls.Add($activeThemeMeta)

$activeThemeTitle = New-Object System.Windows.Forms.Label
$activeThemeTitle.Location = New-Object System.Drawing.Point(22, 34)
$activeThemeTitle.Size = New-Object System.Drawing.Size(370, 31)
$activeThemeTitle.Font = New-Object System.Drawing.Font($FontName, 17, [System.Drawing.FontStyle]::Bold)
$activeThemeTitle.ForeColor = $InkColor
$activeThemeTitle.AutoEllipsis = $true
$activeThemePanel.Controls.Add($activeThemeTitle)

$activeThemeDescription = New-Object System.Windows.Forms.Label
$activeThemeDescription.Location = New-Object System.Drawing.Point(23, 67)
$activeThemeDescription.Size = New-Object System.Drawing.Size(370, 34)
$activeThemeDescription.ForeColor = $MutedColor
$activeThemeDescription.AutoEllipsis = $true
$activeThemePanel.Controls.Add($activeThemeDescription)

$activeThemeRuntime = New-Object System.Windows.Forms.Label
$activeThemeRuntime.Location = New-Object System.Drawing.Point(23, 108)
$activeThemeRuntime.Size = New-Object System.Drawing.Size(128, 22)
$activeThemeRuntime.Font = New-Object System.Drawing.Font($FontName, 8.5, [System.Drawing.FontStyle]::Bold)
$activeThemePanel.Controls.Add($activeThemeRuntime)

$restoreOriginalButton = New-ManagerButton -Text '恢复原版' -Width 104
$restoreOriginalButton.Location = New-Object System.Drawing.Point(156, 101)
$restoreOriginalButton.Height = 32
$activeThemePanel.Controls.Add($restoreOriginalButton)

$activeThemePreview = New-Object System.Windows.Forms.PictureBox
$activeThemePreview.Anchor = 'Top,Right'
$activeThemePreview.Location = New-Object System.Drawing.Point(610, 10)
$activeThemePreview.Size = New-Object System.Drawing.Size(360, 120)
$activeThemePreview.SizeMode = 'Zoom'
$activeThemePreview.BackColor = $SidebarColor
$activeThemePanel.Controls.Add($activeThemePreview)

$currentBadge = New-Object System.Windows.Forms.Label
$currentBadge.Anchor = 'Right,Bottom'
$currentBadge.Location = New-Object System.Drawing.Point(894, 108)
$currentBadge.Size = New-Object System.Drawing.Size(66, 22)
$currentBadge.Text = 'CURRENT'
$currentBadge.TextAlign = 'MiddleCenter'
$currentBadge.Font = New-Object System.Drawing.Font('Consolas', 7.5, [System.Drawing.FontStyle]::Bold)
$currentBadge.ForeColor = [System.Drawing.Color]::White
$currentBadge.BackColor = [System.Drawing.Color]::FromArgb(34, 37, 40)
$activeThemePanel.Controls.Add($currentBadge)
$currentBadge.BringToFront()

$libraryToolbar = New-Object System.Windows.Forms.Panel
$libraryToolbar.Dock = 'Fill'
$libraryToolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$libraryToolbar.BackColor = $CanvasColor
$contentLayout.Controls.Add($libraryToolbar, 0, 2)

$libraryTitle = New-Object System.Windows.Forms.Label
$libraryTitle.Location = New-Object System.Drawing.Point(28, 19)
$libraryTitle.Size = New-Object System.Drawing.Size(130, 26)
$libraryTitle.Text = '皮肤库'
$libraryTitle.Font = New-Object System.Drawing.Font($FontName, 13, [System.Drawing.FontStyle]::Bold)
$libraryTitle.ForeColor = $InkColor
$libraryToolbar.Controls.Add($libraryTitle)

$libraryCount = New-Object System.Windows.Forms.Label
$libraryCount.Location = New-Object System.Drawing.Point(154, 22)
$libraryCount.Size = New-Object System.Drawing.Size(180, 21)
$libraryCount.ForeColor = $MutedColor
$libraryToolbar.Controls.Add($libraryCount)

$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Anchor = 'Top,Right'
$searchLabel.Location = New-Object System.Drawing.Point(633, 21)
$searchLabel.Size = New-Object System.Drawing.Size(42, 20)
$searchLabel.Text = '搜索'
$searchLabel.ForeColor = $MutedColor
$libraryToolbar.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Anchor = 'Top,Right'
$searchBox.Location = New-Object System.Drawing.Point(678, 16)
$searchBox.Size = New-Object System.Drawing.Size(206, 30)
$searchBox.BorderStyle = 'FixedSingle'
$searchBox.Font = New-Object System.Drawing.Font($FontName, 10)
$libraryToolbar.Controls.Add($searchBox)

$importHeaderButton = New-ManagerButton -Text '导入主题' -Width 112
$importHeaderButton.Anchor = 'Top,Right'
$importHeaderButton.Location = New-Object System.Drawing.Point(896, 12)
$libraryToolbar.Controls.Add($importHeaderButton)

$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Fill'
$footer.Margin = New-Object System.Windows.Forms.Padding(0)
$footer.BackColor = $SurfaceColor
$contentLayout.Controls.Add($footer, 0, 4)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(28, 15)
$statusLabel.Size = New-Object System.Drawing.Size(620, 20)
$statusLabel.ForeColor = $MutedColor
$footer.Controls.Add($statusLabel)

$runtimeLabel = New-Object System.Windows.Forms.Label
$runtimeLabel.Anchor = 'Top,Right'
$runtimeLabel.Location = New-Object System.Drawing.Point(862, 15)
$runtimeLabel.Size = New-Object System.Drawing.Size(146, 20)
$runtimeLabel.TextAlign = 'MiddleRight'
$runtimeLabel.Font = New-Object System.Drawing.Font($FontName, 8.5, [System.Drawing.FontStyle]::Bold)
$footer.Controls.Add($runtimeLabel)

$themeFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$themeFlow.Dock = 'Fill'
$themeFlow.AutoScroll = $true
$themeFlow.WrapContents = $true
$themeFlow.FlowDirection = 'LeftToRight'
$themeFlow.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 14)
$themeFlow.BackColor = $CanvasColor
$themeFlow.Margin = New-Object System.Windows.Forms.Padding(0)
$contentLayout.Controls.Add($themeFlow, 0, 3)

$emptyLabel = New-Object System.Windows.Forms.Label
$emptyLabel.AutoSize = $true
$emptyLabel.Text = '没有找到匹配的主题'
$emptyLabel.ForeColor = $MutedColor
$emptyLabel.Font = New-Object System.Drawing.Font($FontName, 11)
$emptyLabel.Visible = $false
$emptyLabel.Margin = New-Object System.Windows.Forms.Padding(24, 32, 0, 0)
$themeFlow.Controls.Add($emptyLabel)

$integrationPanel = New-Object System.Windows.Forms.Panel
$integrationPanel.Dock = 'Fill'
$integrationPanel.Margin = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
$integrationPanel.BackColor = $SurfaceColor
$integrationPanel.Visible = $false
$integrationPanel.add_Paint({
  param($sender, $eventArgs)
  $pen = New-Object System.Drawing.Pen($LineColor, 1)
  try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) } finally {
    $pen.Dispose()
  }
})
$contentLayout.Controls.Add($integrationPanel, 0, 1)
$contentLayout.SetRowSpan($integrationPanel, 3)

$formatTitle = New-Object System.Windows.Forms.Label
$formatTitle.Location = New-Object System.Drawing.Point(30, 28)
$formatTitle.Size = New-Object System.Drawing.Size(420, 30)
$formatTitle.Text = '主题导入格式'
$formatTitle.Font = New-Object System.Drawing.Font($FontName, 16, [System.Drawing.FontStyle]::Bold)
$formatTitle.ForeColor = $InkColor
$integrationPanel.Controls.Add($formatTitle)

$formatBadge = New-Object System.Windows.Forms.Label
$formatBadge.Anchor = 'Top,Right'
$formatBadge.Location = New-Object System.Drawing.Point(828, 30)
$formatBadge.Size = New-Object System.Drawing.Size(110, 24)
$formatBadge.Text = 'SCHEMA 2'
$formatBadge.TextAlign = 'MiddleCenter'
$formatBadge.Font = New-Object System.Drawing.Font('Consolas', 8.5, [System.Drawing.FontStyle]::Bold)
$formatBadge.ForeColor = $SignalColor
$formatBadge.BackColor = $SignalSoftColor
$integrationPanel.Controls.Add($formatBadge)

$formatDescription = New-Object System.Windows.Forms.Label
$formatDescription.Location = New-Object System.Drawing.Point(31, 66)
$formatDescription.Size = New-Object System.Drawing.Size(820, 22)
$formatDescription.Text = '导入文件夹必须包含以下三个文件，图片均使用精确 3:1 PNG。'
$formatDescription.ForeColor = $MutedColor
$integrationPanel.Controls.Add($formatDescription)

$formatRows = @(
  @{ Name = 'theme.json'; Detail = '主题清单、配色、明暗模式与图片焦点' },
  @{ Name = 'background.png'; Detail = '完整背景图，至少 1200 × 400' },
  @{ Name = 'preview.png'; Detail = '主题卡片预览，至少 600 × 200' }
)
$formatTop = 112
foreach ($row in $formatRows) {
  $nameLabel = New-Object System.Windows.Forms.Label
  $nameLabel.Location = New-Object System.Drawing.Point(32, $formatTop)
  $nameLabel.Size = New-Object System.Drawing.Size(190, 32)
  $nameLabel.Text = $row.Name
  $nameLabel.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
  $nameLabel.ForeColor = $AccentColor
  $integrationPanel.Controls.Add($nameLabel)

  $detailLabel = New-Object System.Windows.Forms.Label
  $detailLabel.Location = New-Object System.Drawing.Point(224, $formatTop)
  $detailLabel.Size = New-Object System.Drawing.Size(620, 32)
  $detailLabel.Text = $row.Detail
  $detailLabel.ForeColor = $MutedColor
  $integrationPanel.Controls.Add($detailLabel)
  $formatTop += 46
}

$formatRules = New-Object System.Windows.Forms.Label
$formatRules.Location = New-Object System.Drawing.Point(32, 252)
$formatRules.Size = New-Object System.Drawing.Size(850, 58)
$formatRules.Text = "主题 ID 仅使用小写字母、数字和连字符。`r`navatarOverlay 固定为 show，宠物不会随主题隐藏。`r`n不接受 taskImage、符号链接或目录外文件。"
$formatRules.ForeColor = $MutedColor
$integrationPanel.Controls.Add($formatRules)

$integrationCreateButton = New-ManagerButton -Text '创建主题' -Width 112 -Primary
$integrationCreateButton.Location = New-Object System.Drawing.Point(32, 318)
$integrationPanel.Controls.Add($integrationCreateButton)

$integrationImportButton = New-ManagerButton -Text '导入主题' -Width 112
$integrationImportButton.Location = New-Object System.Drawing.Point(156, 318)
$integrationPanel.Controls.Add($integrationImportButton)

$integrationFolderButton = New-ManagerButton -Text '打开主题目录' -Width 130
$integrationFolderButton.Location = New-Object System.Drawing.Point(280, 318)
$integrationPanel.Controls.Add($integrationFolderButton)

$skillPanel = New-Object System.Windows.Forms.Panel
$skillPanel.Location = New-Object System.Drawing.Point(32, 374)
$skillPanel.Size = New-Object System.Drawing.Size(906, 104)
$skillPanel.Anchor = 'Top,Left,Right'
$skillPanel.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 250)
$skillPanel.add_Paint({
  param($sender, $eventArgs)
  $pen = New-Object System.Drawing.Pen($LineColor, 1)
  try {
    $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
  } finally {
    $pen.Dispose()
  }
})
$integrationPanel.Controls.Add($skillPanel)

$skillIcon = New-Object System.Windows.Forms.Label
$skillIcon.Location = New-Object System.Drawing.Point(18, 22)
$skillIcon.Size = New-Object System.Drawing.Size(52, 52)
$skillIcon.Text = 'AI'
$skillIcon.TextAlign = 'MiddleCenter'
$skillIcon.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$skillIcon.ForeColor = $AccentColor
$skillIcon.BackColor = [System.Drawing.Color]::FromArgb(255, 237, 233)
$skillPanel.Controls.Add($skillIcon)

$skillTitle = New-Object System.Windows.Forms.Label
$skillTitle.Location = New-Object System.Drawing.Point(86, 20)
$skillTitle.Size = New-Object System.Drawing.Size(245, 24)
$skillTitle.Text = 'Codex 主题创建 Skill'
$skillTitle.Font = New-Object System.Drawing.Font($FontName, 11, [System.Drawing.FontStyle]::Bold)
$skillTitle.ForeColor = $InkColor
$skillPanel.Controls.Add($skillTitle)

$skillDescription = New-Object System.Windows.Forms.Label
$skillDescription.Location = New-Object System.Drawing.Point(86, 51)
$skillDescription.Size = New-Object System.Drawing.Size(470, 32)
$skillDescription.Text = '通过对话生成或重做主题，完成后自动加入当前皮肤库。'
$skillDescription.ForeColor = $MutedColor
$skillPanel.Controls.Add($skillDescription)

$skillStatusLabel = New-Object System.Windows.Forms.Label
$skillStatusLabel.Location = New-Object System.Drawing.Point(335, 20)
$skillStatusLabel.Size = New-Object System.Drawing.Size(82, 23)
$skillStatusLabel.TextAlign = 'MiddleCenter'
$skillStatusLabel.Font = New-Object System.Drawing.Font($FontName, 8, [System.Drawing.FontStyle]::Bold)
$skillPanel.Controls.Add($skillStatusLabel)

$skillInstallButton = New-ManagerButton -Text '安装 Skill' -Width 112 -Primary
$skillInstallButton.Location = New-Object System.Drawing.Point(656, 34)
$skillInstallButton.Anchor = 'Top,Right'
$skillPanel.Controls.Add($skillInstallButton)

$skillFolderButton = New-ManagerButton -Text '打开目录' -Width 104
$skillFolderButton.Location = New-Object System.Drawing.Point(780, 34)
$skillFolderButton.Anchor = 'Top,Right'
$skillPanel.Controls.Add($skillFolderButton)
$skillPanel.add_Resize({
  $skillDescription.Width = [Math]::Max(220, $skillInstallButton.Left - $skillDescription.Left - 18)
})

$runtimePanel = New-Object System.Windows.Forms.Panel
$runtimePanel.Dock = 'Fill'
$runtimePanel.Margin = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
$runtimePanel.BackColor = $CanvasColor
$runtimePanel.Visible = $false
$contentLayout.Controls.Add($runtimePanel, 0, 1)
$contentLayout.SetRowSpan($runtimePanel, 3)

$runtimeMetricFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$runtimeMetricFlow.Dock = 'Top'
$runtimeMetricFlow.Height = 158
$runtimeMetricFlow.Padding = New-Object System.Windows.Forms.Padding(8, 12, 8, 8)
$runtimeMetricFlow.WrapContents = $false
$runtimeMetricFlow.BackColor = $CanvasColor
$runtimePanel.Controls.Add($runtimeMetricFlow)

$runtimeConnectionMetric = New-RuntimeMetricPanel -Title '皮肤会话' -Caption '未启动' -Tone $SignalColor
$runtimeConnectionValue = [System.Windows.Forms.Label]$runtimeConnectionMetric.Tag
$runtimeThemeMetric = New-RuntimeMetricPanel -Title '当前皮肤' -Caption '未识别' -Tone $AccentColor
$runtimeThemeValue = [System.Windows.Forms.Label]$runtimeThemeMetric.Tag
$runtimeCountMetric = New-RuntimeMetricPanel -Title '主题数量' -Caption '0 套' -Tone $GoldColor
$runtimeCountValue = [System.Windows.Forms.Label]$runtimeCountMetric.Tag
$runtimeMetricFlow.Controls.AddRange(@($runtimeConnectionMetric, $runtimeThemeMetric, $runtimeCountMetric))
$runtimeMetricFlow.add_Resize({
  $available = $runtimeMetricFlow.ClientSize.Width - $runtimeMetricFlow.Padding.Horizontal - 54
  $metricWidth = [Math]::Max(210, [Math]::Floor($available / 3))
  foreach ($metric in @($runtimeConnectionMetric, $runtimeThemeMetric, $runtimeCountMetric)) {
    $metric.Width = $metricWidth
    ([System.Windows.Forms.Label]$metric.Tag).Width = [Math]::Max(150, $metricWidth - 66)
  }
})

$runtimeDetail = New-Object System.Windows.Forms.Panel
$runtimeDetail.Location = New-Object System.Drawing.Point(16, 178)
$runtimeDetail.Size = New-Object System.Drawing.Size(926, 170)
$runtimeDetail.Anchor = 'Top,Left,Right'
$runtimeDetail.BackColor = $SurfaceColor
$runtimeDetail.add_Paint({
  param($sender, $eventArgs)
  $pen = New-Object System.Drawing.Pen($LineColor, 1)
  try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) } finally {
    $pen.Dispose()
  }
})
$runtimePanel.Controls.Add($runtimeDetail)

$runtimeDetailTitle = New-Object System.Windows.Forms.Label
$runtimeDetailTitle.Location = New-Object System.Drawing.Point(24, 22)
$runtimeDetailTitle.Size = New-Object System.Drawing.Size(420, 28)
$runtimeDetailTitle.Text = 'Windows 运行信息'
$runtimeDetailTitle.Font = New-Object System.Drawing.Font($FontName, 14, [System.Drawing.FontStyle]::Bold)
$runtimeDetailTitle.ForeColor = $InkColor
$runtimeDetail.Controls.Add($runtimeDetailTitle)

$runtimeDetailText = New-Object System.Windows.Forms.Label
$runtimeDetailText.Location = New-Object System.Drawing.Point(25, 60)
$runtimeDetailText.Size = New-Object System.Drawing.Size(820, 58)
$runtimeDetailText.Text = "引擎：$EngineRoot`r`n主题库：$ThemeRoot`r`n切换进程使用隐藏窗口，不再常驻 Windows Terminal。"
$runtimeDetailText.ForeColor = $MutedColor
$runtimeDetail.Controls.Add($runtimeDetailText)

$runtimeRefreshButton = New-ManagerButton -Text '刷新状态' -Width 104 -Primary
$runtimeRefreshButton.Location = New-Object System.Drawing.Point(24, 124)
$runtimeDetail.Controls.Add($runtimeRefreshButton)

$runtimeOpenButton = New-ManagerButton -Text '打开 Codex' -Width 104
$runtimeOpenButton.Location = New-Object System.Drawing.Point(140, 124)
$runtimeDetail.Controls.Add($runtimeOpenButton)

$runtimeRestoreButton = New-ManagerButton -Text '恢复原版' -Width 104
$runtimeRestoreButton.Location = New-Object System.Drawing.Point(256, 124)
$runtimeDetail.Controls.Add($runtimeRestoreButton)

$runtimeUpdateButton = New-ManagerButton -Text '检查更新' -Width 116
$runtimeUpdateButton.Location = New-Object System.Drawing.Point(372, 124)
$runtimeDetail.Controls.Add($runtimeUpdateButton)

$switchTimer = New-Object System.Windows.Forms.Timer
$switchTimer.Interval = 250
$switchTimer.add_Tick({
  if ($null -eq $script:switchProcess -or -not $script:switchProcess.HasExited) { return }
  $switchTimer.Stop()
  $process = $script:switchProcess
  $exitCode = $process.ExitCode
  $output = $process.StandardOutput.ReadToEnd().Trim()
  $errorOutput = $process.StandardError.ReadToEnd().Trim()
  $process.Dispose()
  $appliedThemeId = $script:switchThemeId
  $script:switchProcess = $null
  $script:switchThemeId = $null

  if ($exitCode -eq 0) {
    Reload-ThemeLibrary
    $theme = $script:themes | Where-Object Id -ceq $appliedThemeId | Select-Object -First 1
    $statusLabel.Text = '已应用：{0}' -f $theme.Manifest.name
  } elseif ($exitCode -eq 3) {
    Reload-ThemeLibrary
    $theme = $script:themes | Where-Object Id -ceq $appliedThemeId | Select-Object -First 1
    $statusLabel.Text = '已保存：{0}，重新打开 Codex 后生效' -f $theme.Manifest.name
  } else {
    Reload-ThemeLibrary
    $message = Get-ThemeSwitchFailureMessage `
      -ErrorText $errorOutput `
      -OutputText $output `
      -ExitCode $exitCode
    $theme = $script:themes | Where-Object Id -ceq $appliedThemeId | Select-Object -First 1
    $themeName = if ($null -ne $theme) { [string]$theme.Manifest.name } else { $appliedThemeId }
    $statusLabel.Text = '已选择：{0}，实时应用未完成' -f $themeName
    [System.Windows.Forms.MessageBox]::Show($message, '主题切换失败', 'OK', 'Error') | Out-Null
  }
})

$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 250
$updateTimer.add_Tick({
  if ($null -eq $script:updateProcess -or -not $script:updateProcess.HasExited) { return }
  $updateTimer.Stop()
  $process = $script:updateProcess
  $operation = $script:updateOperation
  $manualCheck = $script:updateManualCheck
  $exitCode = $process.ExitCode
  $output = $process.StandardOutput.ReadToEnd().Trim()
  $errorOutput = $process.StandardError.ReadToEnd().Trim()
  $process.Dispose()
  $script:updateProcess = $null
  $script:updateOperation = $null
  $script:updateManualCheck = $false

  try {
    if ($exitCode -ne 0) {
      $detail = if ($errorOutput) { $errorOutput } else { "更新进程退出代码：$exitCode" }
      throw $detail
    }
    switch ($operation) {
      'check' {
        $result = $output | ConvertFrom-Json
        if (-not $result.pass) { throw '更新清单验证未通过。' }
        [IO.Directory]::CreateDirectory($UpdateRoot) | Out-Null
        Write-DreamSkinUtf8FileAtomically -Path $UpdateCheckResultPath -Content ($output + [Environment]::NewLine)
        $checkState = [ordered]@{
          schemaVersion = 1
          checkedAt = (Get-Date).ToUniversalTime().ToString('o')
          managerVersion = $ManagerVersion
          feedVersion = [string]$result.version
        }
        Write-DreamSkinUtf8FileAtomically -Path $UpdateCheckStatePath -Content (
          ($checkState | ConvertTo-Json -Depth 3) + [Environment]::NewLine
        )
        $script:updateInfo = $result
        $themeCount = @($result.themes).Count
        if ([bool]$result.updateAvailable) {
          $statusLabel.Text = "发现新版本：$($result.version)"
        } elseif ($themeCount -gt 0) {
          $statusLabel.Text = "发现 $themeCount 套官方在线主题"
        } else {
          $statusLabel.Text = "当前版本 $ManagerVersion 已是最新版本"
        }
        Update-ManagerUpdateControls
        if ($manualCheck) {
          Show-ManagerUpdateAction
        } elseif ([bool]$result.updateAvailable -or $themeCount -gt 0) {
          $script:trayIcon.BalloonTipTitle = 'Codex 皮肤管理器有更新'
          $script:trayIcon.BalloonTipText = $statusLabel.Text
          $script:trayIcon.ShowBalloonTip(2500)
        }
      }
      'download' {
        $result = $output | ConvertFrom-Json
        if (-not $result.pass -or -not (Test-Path -LiteralPath ([string]$result.output))) {
          throw '下载后的安装包验证未通过。'
        }
        $statusLabel.Text = '安装包已验证，正在启动静默更新…'
        Update-ManagerUpdateControls
        Start-VerifiedManagerUpdateInstall -InstallerPath ([string]$result.output)
        return
      }
      'themes' {
        $result = $output | ConvertFrom-Json
        if (-not $result.pass) { throw '在线主题安装结果无效。' }
        $count = @($result.installed).Count
        $script:updateInfo.themes = @()
        Reload-ThemeLibrary
        $statusLabel.Text = if ($count -gt 0) {
          "已安装 $count 套在线主题"
        } else {
          '在线主题已经是最新版本'
        }
        $script:trayIcon.BalloonTipTitle = '在线主题更新完成'
        $script:trayIcon.BalloonTipText = $statusLabel.Text
        $script:trayIcon.ShowBalloonTip(2200)
      }
    }
  } catch {
    $statusLabel.Text = '更新操作未完成'
    if ($manualCheck -or $operation -ne 'check') {
      [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        '更新失败',
        'OK',
        'Error'
      ) | Out-Null
    }
  }
  Update-ManagerUpdateControls
})

$automaticUpdateTimer = New-Object System.Windows.Forms.Timer
$automaticUpdateTimer.Interval = 6000
$automaticUpdateTimer.add_Tick({
  $automaticUpdateTimer.Stop()
  if (Test-ManagerAutomaticUpdateCheckDue) {
    Start-ManagerUpdateCheck -Manual $false
  }
})

$libraryMonitorTimer = New-Object System.Windows.Forms.Timer
$libraryMonitorTimer.Interval = 3000
$libraryMonitorTimer.add_Tick({
  if ($null -ne $script:switchProcess) { return }
  $fingerprint = Get-ThemeLibraryFingerprint
  if ($fingerprint -cne $script:themeLibraryFingerprint) {
    Reload-ThemeLibrary
    $statusLabel.Text = '检测到新主题，皮肤库已自动刷新'
    return
  }

  $newActiveThemeId = Get-ActiveThemeId
  $newRuntimeSnapshot = Get-ManagerRuntimeSnapshot
  $activeChanged = [string]$newActiveThemeId -cne [string]$script:activeThemeId
  $runtimeChanged = $null -eq $script:runtimeSnapshot -or
    [string]$newRuntimeSnapshot.Label -cne [string]$script:runtimeSnapshot.Label -or
    [bool]$newRuntimeSnapshot.Connected -ne [bool]$script:runtimeSnapshot.Connected
  $script:activeThemeId = $newActiveThemeId
  $script:runtimeSnapshot = $newRuntimeSnapshot
  if ($activeChanged -or $runtimeChanged) {
    Update-HeaderState
  }
  if ($activeChanged) {
    Update-ThemeCards
  }
  Update-TrayState
})

$activationTimer = New-Object System.Windows.Forms.Timer
$activationTimer.Interval = 350
$activationTimer.add_Tick({
  if ($showEvent.WaitOne(0)) { Show-ManagerWindow }
})

$allThemesButton.add_Click({ Set-ManagerView -Mode 'all' })
$installedButton.add_Click({ Set-ManagerView -Mode 'installed' })
$integrationButton.add_Click({ Set-ManagerView -Mode 'integration' })
$runtimeButton.add_Click({ Set-ManagerView -Mode 'runtime' })
$searchBox.add_TextChanged({
  if ($script:viewMode -in @('all', 'installed')) { Update-ThemeCards }
})

$createAction = {
  if (Show-ThemeCreator -Owner $form) {
    Reload-ThemeLibrary
    $statusLabel.Text = '主题创建完成'
  }
}
$createSidebarButton.add_Click($createAction)
$createHeaderButton.add_Click($createAction)
$integrationCreateButton.add_Click($createAction)

$importAction = { Import-ThemeFromFolder }
$importSidebarButton.add_Click($importAction)
$importHeaderButton.add_Click($importAction)
$integrationImportButton.add_Click($importAction)

$openThemeFolderAction = {
  New-Item -ItemType Directory -Force -Path $ThemeRoot | Out-Null
  Start-Process -FilePath explorer.exe -ArgumentList @("`"$ThemeRoot`"") | Out-Null
}
$dataButton.add_Click($openThemeFolderAction)
$integrationFolderButton.add_Click($openThemeFolderAction)

$skillInstallButton.add_Click({
  try {
    $skillInstallButton.Enabled = $false
    $statusLabel.Text = '正在安装主题创建 Skill...'
    $target = Install-DreamSkinThemeSkill -EngineRoot $EngineRoot
    Update-ThemeSkillState
    $statusLabel.Text = "主题创建 Skill 已安装：$target"
  } catch {
    [System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      'Skill 安装失败',
      'OK',
      'Error'
    ) | Out-Null
    $statusLabel.Text = '主题创建 Skill 安装失败'
  } finally {
    $skillInstallButton.Enabled = $true
  }
})
$skillFolderButton.add_Click({
  $target = Get-DreamSkinThemeSkillTarget
  $openTarget = if (Test-Path -LiteralPath $target) { $target } else { Split-Path -Parent $target }
  New-Item -ItemType Directory -Force -Path $openTarget | Out-Null
  Start-Process -FilePath explorer.exe -ArgumentList @("`"$openTarget`"") | Out-Null
})

$openCodexAction = {
  $launcher = Join-Path $PSScriptRoot 'launch-dream-skin.vbs'
  if (Test-Path -LiteralPath $launcher) {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') `
      -ArgumentList @("`"$launcher`"") | Out-Null
  }
}
$openCodexButton.add_Click($openCodexAction)
$runtimeOpenButton.add_Click($openCodexAction)
$trayOpenCodexItem.add_Click($openCodexAction)

$restoreOriginalAction = {
  if ($script:activeThemeId -cne 'codex-default') {
    Start-ThemeSwitch -ThemeId 'codex-default'
  }
}
$restoreOriginalButton.add_Click($restoreOriginalAction)
$runtimeRestoreButton.add_Click($restoreOriginalAction)
$script:trayRestoreItem.add_Click($restoreOriginalAction)

$refreshAction = {
  Reload-ThemeLibrary
  $statusLabel.Text = '皮肤库和运行状态已刷新'
}
$refreshHeaderButton.add_Click($refreshAction)
$runtimeRefreshButton.add_Click($refreshAction)
$checkUpdateHeaderButton.add_Click({ Show-ManagerUpdateAction })
$runtimeUpdateButton.add_Click({ Show-ManagerUpdateAction })
$script:trayUpdateItem.add_Click({ Show-ManagerUpdateAction })

$trayExitItem.add_Click({
  $script:explicitExit = $true
  $form.Close()
})
$form.add_FormClosing({
  param($sender, $eventArgs)
  if (-not $script:explicitExit -and
      $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
    $eventArgs.Cancel = $true
    $form.ShowInTaskbar = $false
    $form.Hide()
    if (-not $script:hasShownTrayHint) {
      $script:hasShownTrayHint = $true
      $script:trayIcon.BalloonTipTitle = 'Codex 皮肤管理器'
      $script:trayIcon.BalloonTipText = '已驻留系统托盘'
      $script:trayIcon.ShowBalloonTip(1800)
    }
  }
})
$form.add_FormClosed({
  $switchTimer.Stop()
  $updateTimer.Stop()
  $automaticUpdateTimer.Stop()
  $libraryMonitorTimer.Stop()
  $activationTimer.Stop()
  if ($null -ne $script:switchProcess -and -not $script:switchProcess.HasExited) {
    try { $script:switchProcess.Kill() } catch {}
  }
  if ($null -ne $script:updateProcess -and -not $script:updateProcess.HasExited) {
    try { $script:updateProcess.Kill() } catch {}
  }
  foreach ($image in $script:themeImages) { if ($null -ne $image) { $image.Dispose() } }
  if ($null -ne $script:activeBannerImage) { $script:activeBannerImage.Dispose() }
  if ($null -ne $logo.Image) { $logo.Image.Dispose() }
  $script:trayIcon.Visible = $false
  $script:trayIcon.Dispose()
  $script:trayMenu.Dispose()
  $showEvent.Dispose()
  try { $instanceMutex.ReleaseMutex() } catch {}
  $instanceMutex.Dispose()
})
$form.add_Resize({
  $pageSubtitle.Width = [Math]::Max(300, $pageHeader.ClientSize.Width - 390)
  $pageSubtitle.AutoEllipsis = $true
})

Reload-ThemeLibrary
$libraryMonitorTimer.Start()
$activationTimer.Start()
$automaticUpdateTimer.Start()
[System.Windows.Forms.Application]::Run($form)
if ($null -ne $form.Icon) { $form.Icon.Dispose() }
$form.Dispose()
