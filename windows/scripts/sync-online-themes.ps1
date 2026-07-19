[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$CheckResultPath,
  [Parameter(Mandatory = $true)][string]$ThemeRoot
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$EngineRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-package.ps1')

$node = (Get-DreamSkinNodeRuntime).Path
$client = Join-Path $PSScriptRoot 'update-client.mjs'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$updateRoot = Join-Path $stateRoot 'updates\themes'
$versionsPath = Join-Path $stateRoot 'official-theme-versions.json'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "codex-skin-theme-sync-$PID-$([guid]::NewGuid().ToString('N'))"

function Read-OfficialThemeVersions {
  if (-not (Test-Path -LiteralPath $versionsPath)) { return @{} }
  try {
    $object = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = @{}
    foreach ($property in $object.PSObject.Properties) {
      $result[[string]$property.Name] = [int]$property.Value
    }
    return $result
  } catch {
    return @{}
  }
}

function Assert-SafeThemeZip {
  param([Parameter(Mandatory = $true)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    if ($archive.Entries.Count -lt 3 -or $archive.Entries.Count -gt 64) {
      throw '在线主题 ZIP 文件数量无效。'
    }
    $totalLength = [long]0
    foreach ($entry in $archive.Entries) {
      $totalLength += [long]$entry.Length
      $name = $entry.FullName.Replace('\', '/')
      $parts = @($name.Split('/') | Where-Object { $_ })
      if ($name.StartsWith('/') -or $parts -contains '..' -or
          [IO.Path]::IsPathRooted($entry.FullName) -or $entry.Length -gt 31457280) {
        throw '在线主题 ZIP 包含越界路径或异常文件。'
      }
    }
    if ($totalLength -gt 67108864) {
      throw '在线主题 ZIP 解压后超过 64 MB。'
    }
  } finally {
    $archive.Dispose()
  }
}

try {
  $check = Get-Content -LiteralPath $CheckResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $themes = @($check.themes)
  $versions = Read-OfficialThemeVersions
  [IO.Directory]::CreateDirectory($updateRoot) | Out-Null
  [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
  $installed = @()

  foreach ($theme in $themes) {
    $themeId = [string]$theme.id
    $themeVersion = [int]$theme.version
    if (-not (Test-DreamSkinThemeId -ThemeId $themeId) -or $themeVersion -lt 1) {
      throw '在线主题标识或版本无效。'
    }
    if ($versions.ContainsKey($themeId) -and [int]$versions[$themeId] -ge $themeVersion) {
      continue
    }

    $archivePath = Join-Path $updateRoot "$themeId-$themeVersion.zip"
    $downloadOutput = & $node $client download --url ([string]$theme.url) --output $archivePath --sha256 ([string]$theme.sha256) --size ([string]$theme.size)
    if ($LASTEXITCODE -ne 0) { throw "在线主题下载失败：$themeId" }
    $downloadResult = $downloadOutput | ConvertFrom-Json
    if (-not $downloadResult.pass) { throw "在线主题校验失败：$themeId" }

    Assert-SafeThemeZip -Path $archivePath
    $extractRoot = Join-Path $temporaryRoot "$themeId-$themeVersion"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    $manifestFiles = @(Get-ChildItem -LiteralPath $extractRoot -Filter 'theme.json' -File -Recurse)
    if ($manifestFiles.Count -ne 1) {
      throw "在线主题 ZIP 必须只包含一套主题：$themeId"
    }
    $package = Assert-DreamSkinThemePackage -Path $manifestFiles[0].Directory.FullName
    if ([string]$package.Manifest.id -cne $themeId) {
      throw "在线主题 ID 与目录不一致：$themeId"
    }
    Install-DreamSkinThemePackage -Package $package -ThemeRoot $ThemeRoot -Replace
    $versions[$themeId] = $themeVersion
    $installed += $themeId
  }

  $versionsObject = [ordered]@{}
  foreach ($key in @($versions.Keys | Sort-Object)) { $versionsObject[$key] = [int]$versions[$key] }
  Write-DreamSkinUtf8FileAtomically -Path $versionsPath -Content (($versionsObject | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
  [IO.File]::WriteAllText(
    (Join-Path $stateRoot 'theme-library.changed'),
    (Get-Date).ToUniversalTime().ToString('o'),
    (New-Object System.Text.UTF8Encoding($false))
  )
  [pscustomobject]@{ pass = $true; installed = $installed } | ConvertTo-Json -Compress
} finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
