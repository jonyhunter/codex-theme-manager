[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RepositoryRoot = Split-Path -Parent $Root
. (Join-Path $Root 'scripts\common-windows.ps1')

& {
  Set-StrictMode -Version 2.0
  function Get-TestItems([int]$Count) {
    for ($index = 0; $index -lt $Count; $index++) {
      [pscustomobject]@{ Index = $index }
    }
  }
  foreach ($expectedCount in @(0, 1, 3)) {
    $items = @(Get-TestItems -Count $expectedCount)
    if ($items.Count -ne $expectedCount) {
      throw "Strict-mode collection normalization failed for $expectedCount items."
    }
  }
}

foreach ($scriptFile in @(Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File)) {
  [void][scriptblock]::Create((Get-Content -LiteralPath $scriptFile.FullName -Raw -Encoding UTF8))
}
foreach ($scriptFile in @(Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse)) {
  $scriptBytes = [IO.File]::ReadAllBytes($scriptFile.FullName)
  if ($scriptBytes.Length -lt 3 -or $scriptBytes[0] -ne 0xEF -or
      $scriptBytes[1] -ne 0xBB -or $scriptBytes[2] -ne 0xBF) {
    throw "Windows PowerShell 5.1 UTF-8 BOM is missing: $($scriptFile.FullName)"
  }
}
$sharedSkillRoot = Join-Path $RepositoryRoot 'skill\codex-skin-theme-creator'
$sharedSkillPowerShell = Join-Path $sharedSkillRoot 'scripts\create-theme-windows.ps1'
[void][scriptblock]::Create(
  (Get-Content -LiteralPath $sharedSkillPowerShell -Raw -Encoding UTF8)
)
$sharedSkillBytes = [IO.File]::ReadAllBytes($sharedSkillPowerShell)
if ($sharedSkillBytes.Length -lt 3 -or $sharedSkillBytes[0] -ne 0xEF -or
    $sharedSkillBytes[1] -ne 0xBB -or $sharedSkillBytes[2] -ne 0xBF) {
  throw 'The shared Windows theme creator Skill script is missing its UTF-8 BOM.'
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-dream-skin-tests-$PID-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
  $configPath = Join-Path $temporaryRoot 'config.toml'
  $backupPath = Join-Path $temporaryRoot 'config.before-dream-skin.toml'
  $projectName = -join @([char]0x4EE3, [char]0x7801, [char]0x9879, [char]0x76EE, [char]0x7532)
  $laterValue = -join @([char]0x4FDD, [char]0x7559)
  $sample = "model = `"gpt-5`"`r`n`r`n[other]`r`nappearanceTheme = `"keep-other`"`r`n`r`n[projects.'C:\$projectName']`r`ntrust_level = `"trusted`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"theme-`$special`"`r`n"
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
  [System.IO.File]::WriteAllText($configPath, $sample, $utf8NoBom)
  $originalBytes = [System.IO.File]::ReadAllBytes($configPath)

  Install-DreamSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $installed = Read-DreamSkinUtf8File -Path $configPath
  if (-not $installed.Contains($projectName) -or $installed -notmatch 'appearanceTheme = "light"') {
    throw 'Install changed a non-ASCII project name or missed the base theme.'
  }
  $backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
  if ([Convert]::ToBase64String($backupBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Install did not preserve an exact pre-change config backup.'
  }

  $written = [System.IO.File]::ReadAllBytes($configPath)
  if ($written.Length -ge 3 -and $written[0] -eq 0xEF -and $written[1] -eq 0xBB -and $written[2] -eq 0xBF) {
    throw 'Config writer added an unexpected UTF-8 BOM.'
  }

  $installed += "afterInstall = `"$laterValue`"`r`n"
  Write-DreamSkinUtf8FileAtomically -Path $configPath -Content $installed
  Restore-DreamSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $restored = Read-DreamSkinUtf8File -Path $configPath
  if (-not $restored.Contains($projectName) -or -not $restored.Contains($laterValue)) {
    throw 'Restore changed a project name or unrelated post-install setting.'
  }
  if ($restored -notmatch 'appearanceTheme = "system"' -or -not $restored.Contains('appearanceLightCodeThemeId = "theme-$special"')) {
    throw 'Restore did not put the original base theme keys back.'
  }
  if ($restored -notmatch '(?ms)^\[other\].*?appearanceTheme = "keep-other"') {
    throw 'Restore changed an appearance key outside the desktop section.'
  }

  $lfConfigPath = Join-Path $temporaryRoot 'config-lf.toml'
  $lfBackupPath = Join-Path $temporaryRoot 'config-lf.before.toml'
  $lfOriginal = "model = `"gpt-5`"`n[projects.'C:\$projectName']`ntrust_level = `"trusted`"`n"
  [System.IO.File]::WriteAllText($lfConfigPath, $lfOriginal, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfInstalled = Read-DreamSkinUtf8File -Path $lfConfigPath
  if ($lfInstalled.Contains("`r") -or $lfInstalled -notmatch '(?m)^\[desktop\]$') {
    throw 'Install did not preserve LF line endings or create the desktop section.'
  }
  Restore-DreamSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfRestored = Read-DreamSkinUtf8File -Path $lfConfigPath
  if ($lfRestored.Contains("`r") -or $lfRestored -match '(?m)^\[desktop\]$' -or -not $lfRestored.Contains($projectName)) {
    throw 'Restore did not preserve LF content or remove the generated empty desktop section.'
  }

  $quotedConfigPath = Join-Path $temporaryRoot 'config-quoted.toml'
  $quotedBackupPath = Join-Path $temporaryRoot 'config-quoted.before.toml'
  $quotedOriginal = "[`"desktop`"] # retained comment`r`n`"appearanceTheme`" = `"system`"`r`n'appearanceLightCodeThemeId' = `"theme-`$special`"`r`n"
  [System.IO.File]::WriteAllText($quotedConfigPath, $quotedOriginal, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  $quotedInstalled = Read-DreamSkinUtf8File -Path $quotedConfigPath
  if ([regex]::Matches($quotedInstalled, '(?m)^\s*\[(?:"desktop"|desktop)\]').Count -ne 1) {
    throw 'A commented or quoted desktop table was duplicated during install.'
  }
  Restore-DreamSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  if ((Read-DreamSkinUtf8File -Path $quotedConfigPath) -cne $quotedOriginal) {
    throw 'Quoted desktop keys or a table-header comment were not restored exactly.'
  }

  $nestedConfigPath = Join-Path $temporaryRoot 'config-nested-desktop.toml'
  $nestedBackupPath = Join-Path $temporaryRoot 'config-nested-desktop.before.toml'
  $nestedTables = @(
    '["desktop".open-in-target-preferences]'
    'global = "fileManager"'
    ''
    '[desktop.open-in-target-preferences.perPath]'
    "'D:\Nested Project' = `"fileManager`""
  ) -join "`r`n"
  $nestedOriginal = @(
    '[desktop]'
    'appearanceTheme = "system"'
    'followUpQueueMode = "queue"'
    ''
    $nestedTables
    ''
    '[features]'
    'memories = false'
    ''
  ) -join "`r`n"
  [System.IO.File]::WriteAllText($nestedConfigPath, $nestedOriginal, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $nestedConfigPath -BackupPath $nestedBackupPath
  $nestedInstalled = Read-DreamSkinUtf8File -Path $nestedConfigPath
  if (-not $nestedInstalled.Contains('appearanceTheme = "light"') -or
      -not $nestedInstalled.Contains($nestedTables)) {
    throw 'Install did not preserve unrelated nested desktop tables.'
  }
  Restore-DreamSkinBaseTheme -ConfigPath $nestedConfigPath -BackupPath $nestedBackupPath
  $nestedRestored = Read-DreamSkinUtf8File -Path $nestedConfigPath
  if ($nestedRestored -cne $nestedOriginal) {
    throw 'Restore did not preserve nested desktop tables exactly.'
  }

  $singleLineArrayPath = Join-Path $temporaryRoot 'config-single-line-array.toml'
  $singleLineArrayBackup = Join-Path $temporaryRoot 'config-single-line-array.before.toml'
  $singleLineArray = "labels = [`"name[1]`", `"#tag]`"]`r`n"
  [System.IO.File]::WriteAllText($singleLineArrayPath, $singleLineArray, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $singleLineArrayPath -BackupPath $singleLineArrayBackup
  if (-not (Read-DreamSkinUtf8File -Path $singleLineArrayPath).Contains($singleLineArray.TrimEnd())) {
    throw 'A safe single-line array containing bracket text was changed or rejected.'
  }

  foreach ($unsupported in @(
    'desktop.appearanceTheme = "system"',
    'desktop = { appearanceTheme = "system" }',
    '[[desktop]]',
    '[desktop.appearanceTheme]',
    '[desktop."appearanceTheme"]',
    '["desk\u0074op".layout]',
    '["desk\u0074op"]',
    "note = `"`"`"fake`r`n[desktop]`r`nappearanceTheme = `"dark`"`r`n`"`"`"",
    "[desktop]`r`nappearanceTheme = [`r`n  `"light`"`r`n]",
    "[desktop]`r`nlayout = [`r`n  [1, 2],`r`n  [3, 4],`r`n]`r`nappearanceTheme = `"dark`"",
    "[desktop]`r`nlayout = [`"]`",`r`n  [`"[`", `"]`"],`r`n]`r`nappearanceTheme = `"dark`""
  )) {
    $unsupportedPath = Join-Path $temporaryRoot ("unsupported-$([guid]::NewGuid().ToString('N')).toml")
    $unsupportedBackup = "$unsupportedPath.before"
    [System.IO.File]::WriteAllText($unsupportedPath, $unsupported, $utf8NoBom)
    $unsupportedRejected = $false
    try { Install-DreamSkinBaseTheme -ConfigPath $unsupportedPath -BackupPath $unsupportedBackup } catch { $unsupportedRejected = $true }
    if (-not $unsupportedRejected -or (Test-Path -LiteralPath $unsupportedBackup)) {
      throw "Unsupported TOML desktop representation was not rejected safely: $unsupported"
    }
  }

  $recoveryPath = Join-Path $temporaryRoot 'config.before-recovery.toml'
  Write-DreamSkinUtf8FileAtomically -Path $configPath -Content 'intentionally changed'
  Restore-DreamSkinConfigBackup -ConfigPath $configPath -BackupPath $backupPath -RecoveryBackupPath $recoveryPath
  $recoveredBytes = [System.IO.File]::ReadAllBytes($configPath)
  if ([Convert]::ToBase64String($recoveredBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Exact config recovery did not restore the original bytes.'
  }
  if ((Read-DreamSkinUtf8File -Path $recoveryPath) -cne 'intentionally changed') {
    throw 'Exact config recovery did not preserve the replaced current config.'
  }
  $archivePath = Join-Path $temporaryRoot 'config.restored.toml'
  Archive-DreamSkinConfigBackup -BackupPath $backupPath -ArchivePath $archivePath
  if ((Test-Path -LiteralPath $backupPath) -or -not (Test-Path -LiteralPath $archivePath)) {
    throw 'Completed config backup was not archived for a safe future reinstall.'
  }
  $secondBaseline = "[desktop]`r`nappearanceTheme = `"dark`"`r`n"
  [System.IO.File]::WriteAllText($configPath, $secondBaseline, $utf8NoBom)
  $secondBaselineBytes = [System.IO.File]::ReadAllBytes($configPath)
  Install-DreamSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  if (-not (Test-DreamSkinBytesEqual -Left $secondBaselineBytes -Right ([System.IO.File]::ReadAllBytes($backupPath)))) {
    throw 'Reinstall did not capture a fresh config baseline after completed restore.'
  }

  $invalidPath = Join-Path $temporaryRoot 'invalid.toml'
  $invalidBackupPath = Join-Path $temporaryRoot 'invalid.before.toml'
  [System.IO.File]::WriteAllBytes($invalidPath, [byte[]](0x66, 0x6f, 0x80))
  $rejected = $false
  try { Install-DreamSkinBaseTheme -ConfigPath $invalidPath -BackupPath $invalidBackupPath } catch { $rejected = $true }
  if (-not $rejected -or (Test-Path -LiteralPath $invalidBackupPath)) {
    throw 'Invalid UTF-8 input was not rejected before backup creation.'
  }
  $utf16Path = Join-Path $temporaryRoot 'utf16.toml'
  $utf16BackupPath = Join-Path $temporaryRoot 'utf16.before.toml'
  [System.IO.File]::WriteAllText($utf16Path, 'model = "gpt-5"', [System.Text.Encoding]::Unicode)
  $utf16Rejected = $false
  try { Install-DreamSkinBaseTheme -ConfigPath $utf16Path -BackupPath $utf16BackupPath } catch { $utf16Rejected = $true }
  if (-not $utf16Rejected -or (Test-Path -LiteralPath $utf16BackupPath)) {
    throw 'A UTF-16 config was silently transcoded instead of being rejected.'
  }
  $utf16NoBomPath = Join-Path $temporaryRoot 'utf16-no-bom.toml'
  $utf16NoBomBackupPath = Join-Path $temporaryRoot 'utf16-no-bom.before.toml'
  [System.IO.File]::WriteAllBytes($utf16NoBomPath, [System.Text.Encoding]::Unicode.GetBytes('model = "gpt-5"'))
  $utf16NoBomRejected = $false
  try { Install-DreamSkinBaseTheme -ConfigPath $utf16NoBomPath -BackupPath $utf16NoBomBackupPath } catch { $utf16NoBomRejected = $true }
  if (-not $utf16NoBomRejected -or (Test-Path -LiteralPath $utf16NoBomBackupPath)) {
    throw 'A BOM-less UTF-16 config was silently treated as UTF-8 instead of being rejected.'
  }
  $racePath = Join-Path $temporaryRoot 'race.toml'
  [System.IO.File]::WriteAllText($racePath, 'before', $utf8NoBom)
  $raceExpected = [System.IO.File]::ReadAllBytes($racePath)
  [System.IO.File]::WriteAllText($racePath, 'after', $utf8NoBom)
  $raceRejected = $false
  try { Assert-DreamSkinFileUnchanged -Path $racePath -ExpectedBytes $raceExpected } catch { $raceRejected = $true }
  if (-not $raceRejected) { throw 'Concurrent config modification was not detected.' }
  $conditionalWriteRejected = $false
  try {
    Write-DreamSkinUtf8FileAtomically -Path $racePath -Content 'replacement' -ExpectedBytes $raceExpected
  } catch {
    $conditionalWriteRejected = $true
  }
  if (-not $conditionalWriteRejected -or (Read-DreamSkinUtf8File -Path $racePath) -cne 'after') {
    throw 'Conditional atomic write replaced newer config content.'
  }

  if (-not (Test-DreamSkinWebSocketUrl -Value 'ws://127.0.0.1:9335/devtools/page/test' -Port 9335)) {
    throw 'PowerShell loopback WebSocket validation rejected a safe target.'
  }
  foreach ($unsafe in @(
    'ws://example.com:9335/devtools/page/test',
    'ws://127.0.0.1:9336/devtools/page/test',
    'wss://127.0.0.1:9335/devtools/page/test',
    'ws://user@127.0.0.1:9335/devtools/page/test',
    'ws://127.0.0.1:9335/unexpected/test',
    'ws://127.0.0.1:9335/devtools/page/test?query=1'
  )) {
    if (Test-DreamSkinWebSocketUrl -Value $unsafe -Port 9335) { throw "Accepted unsafe CDP target: $unsafe" }
  }
  $safePageTarget = [pscustomobject]@{
    id = 'page-123'
    type = 'page'
    url = 'app://codex/'
    webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123'
  }
  if (-not (Test-DreamSkinCdpPageTarget -Target $safePageTarget -Port 9335)) {
    throw 'A valid same-ID CDP page target was rejected.'
  }
  foreach ($unsafePageTarget in @(
    [pscustomobject]@{ id = 'page-123'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/browser/page-123' },
    [pscustomobject]@{ id = 'other-page'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' },
    [pscustomobject]@{ id = 123; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/123' },
    [pscustomobject]@{ id = 'page-123'; type = 'other'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' }
  )) {
    if (Test-DreamSkinCdpPageTarget -Target $unsafePageTarget -Port 9335) {
      throw 'Accepted an inconsistent CDP page target.'
    }
  }
  $watchCommand = '"C:\Program Files\nodejs\node.exe" "C:\Dream Skin\injector.mjs" --watch --port 9335 --browser-id browser-123'
  if (-not (Test-DreamSkinCommandLineToken -CommandLine $watchCommand -Token 'C:\Dream Skin\injector.mjs') -or
    (Test-DreamSkinCommandLineToken -CommandLine $watchCommand -Token 'Dream Skin\injector.mjs')) {
    throw 'Injector command-line token validation is not boundary-safe.'
  }
  if (-not (Test-DreamSkinBrowserId -Value 'browser-123') -or
    (Test-DreamSkinBrowserId -Value 'browser 123')) {
    throw 'CDP browser ID validation is not boundary-safe.'
  }
  $quotedProfile = ConvertTo-DreamSkinProcessArgument -Value '--user-data-dir=C:\Dream Skin\Profile\'
  if ($quotedProfile -cne '"--user-data-dir=C:\Dream Skin\Profile\\"') {
    throw 'Process argument quoting did not protect spaces and a trailing backslash.'
  }

  $statePath = Join-Path $temporaryRoot 'state.json'
  $state = [pscustomobject]@{
    schemaVersion = 3
    platform = 'windows'
    port = 9335
    injectorPid = 1234
    injectorStartedAt = '2026-01-01T00:00:00.0000000Z'
    injectorPath = 'C:\Dream Skin\injector.mjs'
    nodePath = 'C:\Program Files\nodejs\node.exe'
    codexExe = 'C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe'
    codexPackageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex'
    codexPackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    codexPackageFamilyName = 'OpenAI.Codex_test'
    browserId = 'browser-123'
  }
  Write-DreamSkinState -Path $statePath -State $state
  $loadedState = Read-DreamSkinState -Path $statePath
  if ($loadedState.schemaVersion -ne 3 -or $loadedState.port -ne 9335 -or
    $loadedState.browserId -cne 'browser-123') { throw 'State round-trip failed.' }
  $missingIdentityState = [pscustomobject]@{ schemaVersion = 3; platform = 'windows'; port = 9335 }
  Write-DreamSkinState -Path $statePath -State $missingIdentityState
  $missingIdentityRejected = $false
  try { $null = Read-DreamSkinState -Path $statePath } catch { $missingIdentityRejected = $true }
  if (-not $missingIdentityRejected) { throw 'Schema 3 accepted a state missing process and package identity.' }
  $legacyState = [pscustomobject]@{ schemaVersion = 2; platform = 'windows'; port = 9335; injectorPid = 1234 }
  Write-DreamSkinState -Path $statePath -State $legacyState
  if ((Read-DreamSkinState -Path $statePath).schemaVersion -ne 2) {
    throw 'A supported schema 2 state was rejected.'
  }

  $fakePackageRoot = Join-Path $temporaryRoot 'OpenAI.Codex_1.2.3.4_x64__test'
  $fakeExecutable = Join-Path $fakePackageRoot 'app\ChatGPT.exe'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fakeExecutable) -Force | Out-Null
  [System.IO.File]::WriteAllBytes($fakeExecutable, [byte[]]@())
  $fakePackage = [pscustomobject]@{
    Name = 'OpenAI.Codex'
    InstallLocation = $fakePackageRoot
    PackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    PackageFamilyName = 'OpenAI.Codex_test'
    SignatureKind = 'Store'
    IsDevelopmentMode = $false
    Version = [version]'1.2.3.4'
  }
  $fakeInstall = ConvertTo-DreamSkinCodexInstall -Package $fakePackage
  if ($null -eq $fakeInstall -or $fakeInstall.PackageFullName -cne $fakePackage.PackageFullName -or
    -not (Test-DreamSkinPathEqual -Left $fakeInstall.Executable -Right $fakeExecutable)) {
    throw 'Registered Appx package identity conversion failed.'
  }
  $fakePackage.SignatureKind = 'Developer'
  if ($null -ne (ConvertTo-DreamSkinCodexInstall -Package $fakePackage)) {
    throw 'A non-Store Appx package was accepted as official Codex.'
  }
  $fakePackage.SignatureKind = 'Store'
  $pathOnlyState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
  }
  if ($null -eq (Get-DreamSkinCodexStatePathCandidate -State $pathOnlyState)) {
    throw 'A structurally valid legacy Codex path was not recognized for read-only activity checks.'
  }
  if ($null -eq (Resolve-DreamSkinCodexInstallFromState -State $pathOnlyState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A legacy state path was not revalidated against a registered Store package.'
  }
  $verifiedPackageState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
    codexPackageFullName = $fakePackage.PackageFullName
    codexPackageFamilyName = $fakePackage.PackageFamilyName
  }
  $resolvedInstall = Resolve-DreamSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall)
  if ($null -eq $resolvedInstall -or -not $resolvedInstall.RegisteredPackageVerified) {
    throw 'State package identity did not resolve against the registered Appx package.'
  }
  $verifiedPackageState.codexPackageFamilyName = 'OpenAI.Codex_wrong'
  if ($null -ne (Resolve-DreamSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A mismatched Appx package family was accepted from state.'
  }
  Write-DreamSkinUtf8FileAtomically -Path $statePath -Content '[]'
  $badStateRejected = $false
  try { $null = Read-DreamSkinState -Path $statePath } catch { $badStateRejected = $true }
  if (-not $badStateRejected) { throw 'A non-object state file was accepted.' }
  $staleStatePath = Archive-DreamSkinStateFile -Path $statePath
  if ((Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $staleStatePath)) {
    throw 'Stale state was not preserved under an archive name.'
  }

  $node = Get-DreamSkinNodeRuntime
  & $node.Path (Join-Path $Root 'scripts\injector.mjs') --self-test *> $null
  if ($LASTEXITCODE -ne 0) { throw 'Injector CDP self-test failed.' }
  if ((Get-Content -LiteralPath (Join-Path $Root 'scripts\injector.mjs') -Raw) -notmatch 'markers\.library') {
    throw 'Injector does not recognize the plugin and skill library shell.'
  }
  $injectorSource = Get-Content -LiteralPath (Join-Path $Root 'scripts\injector.mjs') -Raw
  $rendererSource = Get-Content -LiteralPath (Join-Path $Root 'assets\renderer-inject.js') -Raw
  if ($injectorSource -notmatch 'markers\.settings' -or
      $rendererSource -notmatch 'dream-skin-settings-sidebar' -or
      $rendererSource -notmatch 'dream-skin-settings-shell') {
    throw 'The renderer or injector does not recognize the settings shell.'
  }
  & $node.Path (Join-Path $Root 'scripts\injector.mjs') --check-payload *> $null
  if ($LASTEXITCODE -ne 0) { throw 'Injector self-test failed.' }

  $themeIds = @(
    'codex-default',
    'salary-cat-office',
    'miku-dream-skin',
    'nailong-sunshine',
    'cyrene-star-rail',
    'blue-archive-ensemble',
    'cartethyia-wuthering-waves',
    'furina-genshin',
    'firefly-star-rail',
    'saber-fate',
    'asuka-eva',
    'rem-rezero',
    'red-horizon',
    'black-gold-stage'
  )
  foreach ($themeId in $themeIds) {
    $themeRoot = Join-Path $Root "themes\$themeId"
    $manifestPath = Join-Path $themeRoot 'theme.json'
    foreach ($file in @('background.png', 'preview.png', 'theme.json')) {
      if (-not (Test-Path -LiteralPath (Join-Path $themeRoot $file))) {
        throw "Theme $themeId is missing $file."
      }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 2 -or $manifest.id -cne $themeId -or
      $manifest.image -cne 'background.png' -or $manifest.preview -cne 'preview.png' -or
      [string]::IsNullOrWhiteSpace([string]$manifest.style) -or
      @('auto', 'light', 'dark') -cnotcontains [string]$manifest.appearance -or
      $manifest.avatarOverlay -cne 'show' -or $null -ne $manifest.taskImage) {
      throw "Theme $themeId does not follow the schema 2 single-image format."
    }
    if ($themeId -ceq 'miku-dream-skin' -and
      ($manifest.appearance -cne 'auto' -or $null -eq $manifest.colorsLight -or $null -eq $manifest.colorsDark)) {
      throw 'The Hatsune Miku theme must follow the system and provide both light and dark palettes.'
    }
    if ($themeId -ne 'codex-default') {
      $payloadText = & $node.Path (Join-Path $Root 'scripts\injector.mjs') --check-payload --theme-dir $themeRoot
      if ($LASTEXITCODE -ne 0) { throw "Theme payload validation failed: $themeId" }
      $payload = $payloadText | ConvertFrom-Json
      if ($payload.avatarOverlay -cne 'show') {
        throw "Theme payload can hide the pet overlay: $themeId"
      }
    }
  }
  $cssSource = Get-Content -LiteralPath (Join-Path $Root 'assets\dream-skin.css') -Raw -Encoding UTF8
  if ($cssSource -notmatch 'data-dream-view="settings"' -or
      $cssSource -notmatch '--color-background-panel' -or
      $cssSource -notmatch 'dream-skin-settings-sidebar' -or
      $cssSource -notmatch 'dream-skin-settings-shell.*rounded-2xl') {
    throw 'The settings shell is missing theme-aware panel and control styles.'
  }
  if ($cssSource -notmatch 'red-horizon.*app-shell-main-content-top-fade' -or
    $cssSource -notmatch 'red-horizon.*data-sonner-toaster' -or
    $cssSource -notmatch 'blue-archive-ensemble.*app-shell-main-content-top-fade' -or
    $cssSource -notmatch 'blue-archive-ensemble.*data-sonner-toaster') {
    throw 'A built-in light-shell theme is missing module overrides.'
  }
  foreach ($themeStyle in @(
    'cartethyia-wuthering-waves',
    'furina-genshin',
    'firefly-star-rail',
    'saber-fate',
    'asuka-eva',
    'rem-rezero'
  )) {
    if ($cssSource -notmatch [regex]::Escape($themeStyle)) {
      throw "Character theme $themeStyle is missing module overrides."
    }
  }
  if ($cssSource -notmatch 'Character scene collection' -or
    $cssSource -notmatch '\) main\.main-surface \.app-shell-main-content-top-fade' -or
    $cssSource -notmatch '\) \[data-sonner-toaster\] \[data-sonner-toast\]') {
    throw 'The character theme collection is missing shared module overrides.'
  }
  if ($cssSource -match '--dream-skin-character-task-focus' -or
    $cssSource -match 'main\.main-surface:not\(\.dream-skin-home-shell\) \.thread-scroll-container') {
    throw 'A character theme has a task-only focus or reading-wash override.'
  }
  $installerSource = Get-Content -LiteralPath (Join-Path $Root 'installer\CodexDreamSkin.nsi') -Raw -Encoding UTF8
  if ($installerSource -notmatch 'PRODUCT_NAME "Codex 皮肤管理器"' -or
    $installerSource -notmatch 'PRODUCT_VERSION "1\.7\.1"' -or
    $installerSource -notmatch 'Codex-Skin-Manager-Setup-\$\{PRODUCT_VERSION\}\.exe' -or
    $installerSource -notmatch 'engine-\$\{PRODUCT_VERSION\}') {
    throw 'The Windows product name or release filename is stale.'
  }
  if ($installerSource -match '-PromptCloseCodex' -or
      $installerSource -notmatch 'install-error\.log' -or
      $installerSource -notmatch 'wscript\.exe.*launch-theme-manager\.vbs' -or
      $installerSource -notmatch 'skill\\codex-skin-theme-creator') {
    throw 'The Windows installer still requests a Codex shutdown or omits its detailed error log.'
  }
  $installScriptSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\install-dream-skin.ps1') -Raw -Encoding UTF8
  if ($installScriptSource -match 'PromptCloseCodex' -or
      $installScriptSource -match 'Stop-DreamSkinCodex.*-AllowForce' -or
      $installScriptSource -notmatch 'Codex 保持运行' -or
      $installScriptSource -notmatch 'configInstalled' -or
      $installScriptSource -notmatch 'selection\.json' -or
      $installScriptSource -notmatch 'install-error\.log' -or
      $installScriptSource -notmatch 'Install-DreamSkinThemeSkill') {
    throw 'The install script is missing live-install retries, keep-running behavior, or persistent error logging.'
  }
  $managerSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\theme-manager.ps1') -Raw -Encoding UTF8
  $switchSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\switch-theme.ps1') -Raw -Encoding UTF8
  $pauseSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\pause-dream-skin.ps1') -Raw -Encoding UTF8
  $startSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\start-dream-skin.ps1') -Raw -Encoding UTF8
  $commonSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\common-windows.ps1') -Raw -Encoding UTF8
  $restoreSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\restore-dream-skin.ps1') -Raw -Encoding UTF8
  $injectorSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\injector.mjs') -Raw -Encoding UTF8
  $updateClientSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\update-client.mjs') -Raw -Encoding UTF8
  $updateInstallerSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\install-update-windows.ps1') -Raw -Encoding UTF8
  $onlineThemeSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\sync-online-themes.ps1') -Raw -Encoding UTF8
  if ($managerSource -notmatch 'CodexDreamSkin\\themes' -or
      $switchSource -notmatch 'CodexDreamSkin\\themes') {
    throw 'The manager and switcher do not share the persistent user theme library.'
  }
  if ($managerSource -notmatch 'FlowLayoutPanel' -or
      $managerSource -notmatch 'CreateNoWindow' -or
      $managerSource -notmatch 'EncodedCommand' -or
      $managerSource -notmatch 'TableLayoutPanel' -or
      $managerSource -notmatch 'activeThemePanel' -or
      $managerSource -notmatch 'integrationPanel' -or
      $managerSource -notmatch 'runtimePanel' -or
      $managerSource -notmatch 'New-ThemeActionCard' -or
      $managerSource -notmatch 'Get-ManagerRuntimeSnapshot' -or
      $managerSource -notmatch 'Get-DreamSkinVerifiedCdpIdentity' -or
      $managerSource -notmatch 'Update-ThemeSkillState' -or
      $managerSource -notmatch 'Get-ThemeLibraryFingerprint' -or
      $managerSource -notmatch 'switchErrorPath' -or
      $managerSource -notmatch 'RedirectStandardOutput = \$false' -or
      $managerSource -notmatch '-OutputFormat Text' -or
      $managerSource -notmatch '深色侧栏|SidebarColor' -or
      $managerSource -match 'System\.Windows\.Forms\.ListView') {
    throw 'The Windows manager is missing the card library or hidden asynchronous switching.'
  }
  if ([regex]::Matches(
      $managerSource,
      '\$process\.Standard(?:Output|Error)\.ReadToEnd\(\)'
    ).Count -ne 2) {
    throw 'Theme switching can still block the UI while waiting for inherited output pipes.'
  }
  if ($managerSource -notmatch 'System\.Windows\.Forms\.NotifyIcon' -or
      $managerSource -notmatch 'System\.Windows\.Forms\.ContextMenuStrip' -or
      $managerSource -notmatch 'Local\\CodexSkinManager\.Show' -or
      $managerSource -notmatch 'add_FormClosing' -or
      $managerSource -notmatch 'ShowInTaskbar = \$false' -or
      $managerSource -notmatch 'Application\]::Run\(\$form\)' -or
      $managerSource -notmatch 'Update-TrayState' -or
      $managerSource -notmatch 'libraryMonitorTimer\.Interval = 3000') {
    throw 'The Windows manager is missing tray residency, single-instance wake-up, or live status refresh.'
  }
  if ($managerSource -notmatch 'Start-ManagerUpdateCheck' -or
      $managerSource -notmatch 'trayUpdateItem' -or
      $managerSource -notmatch 'automaticUpdateTimer\.Interval = 6000' -or
      $managerSource -notmatch 'Codex-Skin-Manager-Setup-\$version\.exe' -or
      $updateClientSource -notmatch 'Ed25519' -or
      $updateClientSource -notmatch 'verify\(null, data, publicKey, signature\)' -or
      $updateClientSource -notmatch 'SHA-256 校验失败' -or
      $updateInstallerSource -notmatch "ArgumentList = '/S'" -or
      $updateInstallerSource -notmatch 'launch-theme-manager\.vbs' -or
      $onlineThemeSource -notmatch 'Assert-SafeThemeZip' -or
      $onlineThemeSource -notmatch 'Install-DreamSkinThemePackage') {
    throw 'The Windows signed updater or online theme workflow is incomplete.'
  }
  if ($switchSource -notmatch 'selection\.json' -or
      $switchSource -notmatch 'pause-dream-skin\.ps1' -or
      $pauseSource -notmatch '--remove' -or
      $pauseSource -notmatch "session = 'paused'" -or
      $startSource -notmatch 'selection\.json' -or
      $startSource -notmatch "themeId -ceq 'codex-default'") {
    throw 'The original-theme pause state or persistent theme selection workflow is incomplete.'
  }
  if ($managerSource -match 'previousThemeId' -or
      $switchSource -match 'previousSelectionBytes' -or
      $startSource -notmatch 'Test-DreamSkinRecordedInjector' -or
      $startSource -notmatch '--once' -or
      $commonSource -notmatch 'function Test-DreamSkinRecordedInjector' -or
      $commonSource -notmatch 'AddSeconds\(10\)' -or
      $injectorSource -notmatch 'getThemeRevision' -or
      $injectorSource -notmatch 'closeAndWait' -or
      $injectorSource -notmatch 'reloaded theme') {
    throw 'The hot-switch workflow can still roll back selection or restart the injector unnecessarily.'
  }
  foreach ($processSource in @($installScriptSource, $startSource, $restoreSource, $commonSource)) {
    if ($processSource -match '(?<!@)\(Get-DreamSkinCodexProcesses[^\r\n]*\)\.Count' -or
        $processSource -match '(?m)^\s*\$\w+Processes\s*=\s*Get-DreamSkinCodexProcesses\b') {
      throw 'A Windows process query can still collapse to null or a scalar before Count is read.'
    }
  }
  $releaseWorkflowSource = Get-Content `
    -LiteralPath (Join-Path $RepositoryRoot '.github\workflows\release.yml') -Raw -Encoding UTF8
  $localBuildSource = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\build-installer-windows.sh') -Raw -Encoding UTF8
  if ($releaseWorkflowSource -notmatch '& \$makensis /INPUTCHARSET UTF8' -or
      $releaseWorkflowSource -notmatch 'VersionInfo\.ProductName' -or
      $releaseWorkflowSource -notmatch 'Copy-Item[^\r\n]*node\.exe' -or
      $releaseWorkflowSource -notmatch 'windows\\runtime\\node\.exe' -or
      $localBuildSource -notmatch '\$MAKENSIS" -INPUTCHARSET UTF8') {
    throw 'The Windows installer build omits UTF-8 verification or its bundled Node.js runtime.'
  }
  foreach ($launcherName in @('launch-theme-manager.vbs', 'launch-dream-skin.vbs', 'launch-restore.vbs')) {
    $launcherSource = Get-Content `
      -LiteralPath (Join-Path $Root "scripts\$launcherName") -Raw -Encoding ASCII
    if ($launcherSource -notmatch '-WindowStyle Hidden' -or
        $launcherSource -notmatch 'shell\.Run\(command, 0, True\)') {
      throw "Hidden launcher does not wait without showing a console: $launcherName"
    }
  }
  if ($injectorSource -notmatch 'process\.exit\(process\.exitCode') {
    throw 'One-shot injector modes do not terminate explicitly.'
  }
  foreach ($required in @(
    'scripts\pause-dream-skin.ps1',
    'scripts\switch-theme.ps1',
    'scripts\theme-manager.ps1',
    'scripts\theme-package.ps1',
    'scripts\theme-skill.ps1',
    'scripts\update-client.mjs',
    'scripts\install-update-windows.ps1',
    'scripts\sync-online-themes.ps1',
    'scripts\launch-theme-manager.vbs',
    'scripts\launch-dream-skin.vbs',
    'scripts\launch-restore.vbs',
    'installer\CodexDreamSkin.nsi',
    'assets\DreamSkinAppIcon.ico'
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $required))) {
      throw "Windows package is missing $required."
    }
  }
  Add-Type -AssemblyName System.Drawing
  . (Join-Path $Root 'scripts\theme-package.ps1')
  $validatedTheme = Assert-DreamSkinThemePackage -Path (Join-Path $Root 'themes\rem-rezero')
  if ($validatedTheme.Manifest.id -cne 'rem-rezero') {
    throw 'The strict theme package validator rejected the Rem theme.'
  }
  foreach ($missingField in @('style', 'appearance')) {
    $invalidTheme = Join-Path $temporaryRoot "invalid-theme-$missingField"
    Copy-Item -LiteralPath (Join-Path $Root 'themes\rem-rezero') `
      -Destination $invalidTheme -Recurse
    $invalidManifestPath = Join-Path $invalidTheme 'theme.json'
    $invalidManifest = Get-Content -LiteralPath $invalidManifestPath -Raw -Encoding UTF8 |
      ConvertFrom-Json
    $invalidManifest.PSObject.Properties.Remove($missingField)
    Write-DreamSkinUtf8FileAtomically `
      -Path $invalidManifestPath `
      -Content ($invalidManifest | ConvertTo-Json -Depth 8)
    $invalidRejected = $false
    try {
      Assert-DreamSkinThemePackage -Path $invalidTheme | Out-Null
    } catch {
      $invalidRejected = $true
    }
    if (-not $invalidRejected) {
      throw "The strict theme package validator accepted a package without $missingField."
    }
  }
  if ($managerSource -notmatch 'Show-ThemeCreator' -or
      $managerSource -notmatch 'Assert-DreamSkinThemePackage') {
    throw 'The Windows manager is missing theme creation or strict import.'
  }

  Write-Host 'PASS: config transactions, restore scoping, state safety, theme payloads, argument quoting, and loopback CDP validation.'
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
