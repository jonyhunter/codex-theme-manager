[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$RestartExisting,
  [switch]$PromptRestart,
  [string]$ProfilePath,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

function Invoke-DreamSkinFastHotApply {
  param(
    [AllowNull()][object]$State,
    [Parameter(Mandatory = $true)][object]$Node,
    [Parameter(Mandatory = $true)][string]$InjectorPath,
    [Parameter(Mandatory = $true)][string]$ThemePath,
    [Parameter(Mandatory = $true)][string]$StateFile,
    [Parameter(Mandatory = $true)][string]$VerifyFile,
    [AllowNull()][string]$SelectedThemeId,
    [int]$RequestedPort,
    [bool]$RequestedPortExplicit,
    [bool]$HasExplicitProfile,
    [bool]$UseForegroundInjector
  )

  if ($null -eq $State -or $HasExplicitProfile -or $UseForegroundInjector -or
      (Test-DreamSkinStatePaused -State $State)) {
    return $false
  }
  $properties = @($State.PSObject.Properties.Name)
  foreach ($required in @('port', 'browserId', 'injectorPath', 'nodePath')) {
    if ($properties -notcontains $required -or -not $State.$required) { return $false }
  }

  $recordedPort = [int]$State.port
  if ($RequestedPortExplicit -and $RequestedPort -ne $recordedPort) { return $false }
  if (-not (Test-DreamSkinPathEqual -Left "$($State.injectorPath)" -Right $InjectorPath) -or
      -not (Test-DreamSkinPathEqual -Left "$($State.nodePath)" -Right $Node.Path) -or
      -not (Test-DreamSkinRecordedInjector -State $State)) {
    return $false
  }

  $hotApplyOutput = @(& $Node.Path $InjectorPath --once --port $recordedPort `
    --browser-id "$($State.browserId)" --theme-dir $ThemePath --timeout-ms 30000 2>&1)
  $hotApplyExitCode = $LASTEXITCODE
  Write-DreamSkinUtf8FileAtomically `
    -Path $VerifyFile `
    -Content (($hotApplyOutput -join "`r`n") + "`r`n")
  if ($hotApplyExitCode -ne 0) { return $false }

  $State | Add-Member -NotePropertyName selectedThemeId -NotePropertyValue $SelectedThemeId -Force
  $State | Add-Member -NotePropertyName themeDir -NotePropertyValue $ThemePath -Force
  $State | Add-Member `
    -NotePropertyName updatedAt `
    -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') `
    -Force
  Write-DreamSkinState -Path $StateFile -State $State
  return $true
}

$operationLock = Enter-DreamSkinOperationLock
try {
  Assert-DreamSkinPort -Port $Port
  if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
  $node = Get-DreamSkinNodeRuntime
  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
  $ThemeDir = Join-Path $StateRoot 'theme'
  $StatePath = Join-Path $StateRoot 'state.json'
  $StdoutPath = Join-Path $StateRoot 'injector.log'
  $StderrPath = Join-Path $StateRoot 'injector-error.log'
  $VerifyPath = Join-Path $StateRoot 'verify.log'
  New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
  if (-not (Test-Path -LiteralPath (Join-Path $ThemeDir 'theme.json'))) {
    throw "No active Dream Skin theme is installed at $ThemeDir. Run install-dream-skin.ps1 first."
  }
  $SelectionPath = Join-Path $StateRoot 'selection.json'
  $selectedThemeId = $null
  if (Test-Path -LiteralPath $SelectionPath) {
    try {
      $selection = (Read-DreamSkinUtf8File -Path $SelectionPath) | ConvertFrom-Json -ErrorAction Stop
      $selectedThemeId = [string]$selection.themeId
      if ([string]$selection.themeId -ceq 'codex-default') {
        $currentCodex = Get-DreamSkinCodexInstall
        if (@(Get-DreamSkinCodexProcesses -Codex $currentCodex).Count -eq 0) {
          Start-Process -FilePath $currentCodex.Executable | Out-Null
        }
        Write-Host 'Codex 当前使用原版外观。'
        exit 0
      }
    } catch {
      throw "Dream Skin selection is unreadable; it was preserved for inspection: $SelectionPath"
    }
  }

  $previousState = Read-DreamSkinState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $previousState -and $previousState.port) {
    $savedPort = [int]$previousState.port
    Assert-DreamSkinPort -Port $savedPort
    $Port = $savedPort
  }
  if (Invoke-DreamSkinFastHotApply `
      -State $previousState `
      -Node $node `
      -InjectorPath $Injector `
      -ThemePath $ThemeDir `
      -StateFile $StatePath `
      -VerifyFile $VerifyPath `
      -SelectedThemeId $selectedThemeId `
      -RequestedPort $Port `
      -RequestedPortExplicit $PortExplicit `
      -HasExplicitProfile ([bool]$ProfilePath) `
      -UseForegroundInjector ([bool]$ForegroundInjector)) {
    Write-Host "Codex 皮肤已热切换；现有监视器继续在本机端口 $Port 运行。"
    exit 0
  }

  $currentCodex = Get-DreamSkinCodexInstall
  $codex = $currentCodex
  $savedPathCandidate = Get-DreamSkinCodexStatePathCandidate -State $previousState
  $savedCodex = Get-DreamSkinCodexInstallFromState -State $previousState
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = @(Get-DreamSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0
    $unverifiedSavedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedPathCandidate
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state was preserved.'
    }
  }

  $currentProcesses = @(Get-DreamSkinCodexProcesses -Codex $currentCodex)
  $codexToStop = $currentCodex
  $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $currentCodex
  $savedIsDifferent = [bool]($null -ne $savedCodex -and
    -not (Test-DreamSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  if ($savedIsDifferent) {
    $savedProcesses = @(Get-DreamSkinCodexProcesses -Codex $savedCodex)
    $savedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedCodex
    if ($currentProcesses.Count -gt 0 -and ($savedProcesses.Count -gt 0 -or $savedOwnsPort)) {
      throw 'Multiple registered Codex package versions are active. Close them manually before starting Dream Skin.'
    }
    if ($savedProcesses.Count -gt 0 -or $savedOwnsPort) {
      if ($savedOwnsPort -and $savedProcesses.Count -eq 0) {
        throw 'The saved Codex listener is active but its process cannot be managed safely; state was preserved.'
      }
      $savedIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $codexToStop = $savedCodex
        $cdpIdentity = $savedIdentity
        Write-Warning 'Reapplying Dream Skin to the still-running registered Codex version; the current Store version will be used after that app exits.'
      } else {
        $codexToStop = $savedCodex
        $currentProcesses = $savedProcesses
      }
    }
  }
  $debugReady = $null -ne $cdpIdentity
  $codexProcesses = @(if (Test-DreamSkinPathEqual -Left $codexToStop.Executable -Right $currentCodex.Executable) {
    $currentProcesses
  } else {
    Get-DreamSkinCodexProcesses -Codex $codexToStop
  })
  $closedExistingCodex = $false
  if (-not $debugReady -and $codexProcesses.Count -gt 0) {
    $restartAuthorized = [bool]$RestartExisting
    if (-not $restartAuthorized -and $PromptRestart) {
      $restartAuthorized = Confirm-DreamSkinRestart -Message 'Codex must restart once to enable Dream Skin. Unsaved input may be lost. Restart now?'
      if (-not $restartAuthorized) {
        Write-Host 'Dream Skin launch was cancelled; Codex was not changed.'
        exit 3
      }
    }
    if (-not $restartAuthorized) {
      throw 'Codex is open without a verified Dream Skin CDP endpoint. Close it first or explicitly use -RestartExisting.'
    }
    Stop-DreamSkinCodex -Codex $codexToStop -AllowForce
    $closedExistingCodex = $true
    $codex = $currentCodex
  }

  $launchedWithCdp = $false
  try {
    if ($null -eq (Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex)) {
      if (-not (Test-DreamSkinPortAvailable -Port $Port)) {
        if ($PortExplicit) { throw "Port $Port is already occupied by an unverified listener. Choose another port." }
        $Port = Select-DreamSkinPort -PreferredPort $Port
      }
      $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
      if ($ProfilePath) {
        New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
        $arguments += ConvertTo-DreamSkinProcessArgument -Value "--user-data-dir=$ProfilePath"
      }
      Start-Process -FilePath $codex.Executable -ArgumentList $arguments | Out-Null
      $launchedWithCdp = $true
    }

    $deadline = (Get-Date).AddSeconds(45)
    $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    while ($null -eq $cdpIdentity) {
      if ((Get-Date) -ge $deadline) {
        throw "Codex did not expose a verified loopback CDP endpoint on port $Port within 45 seconds."
      }
      Start-Sleep -Milliseconds 400
      $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    }
  } catch {
    $launchError = $_
    if ($launchedWithCdp) {
      try { Stop-DreamSkinCodex -Codex $codex -AllowForce } catch {
        Write-Warning 'Launch rollback could not fully close the failed CDP session.'
      }
    }
    if (($closedExistingCodex -or $launchedWithCdp) -and
      @(Get-DreamSkinCodexProcesses -Codex $codex).Count -eq 0) {
      if ($launchedWithCdp) {
        Write-Warning 'Dream Skin launch failed; reopening Codex without a debugging port.'
      }
      try { Start-Process -FilePath $codex.Executable | Out-Null } catch {
        Write-Warning 'Launch rollback could not reopen Codex automatically.'
      }
    }
    throw $launchError
  }

  $canReuseInjector = -not $ForegroundInjector -and
    $null -ne $previousState -and
    (Test-DreamSkinRecordedInjector -State $previousState) -and
    (Test-DreamSkinPathEqual -Left "$($previousState.injectorPath)" -Right $Injector) -and
    "$($previousState.browserId)" -ceq $cdpIdentity.BrowserId
  if ($canReuseInjector) {
    $hotApplyOutput = @(& $node.Path $Injector --once --port $Port `
      --browser-id $cdpIdentity.BrowserId --theme-dir $ThemeDir --timeout-ms 30000 2>&1)
    $hotApplyExitCode = $LASTEXITCODE
    Write-DreamSkinUtf8FileAtomically `
      -Path $VerifyPath `
      -Content (($hotApplyOutput -join "`r`n") + "`r`n")
    if ($hotApplyExitCode -eq 0) {
      $previousState | Add-Member -NotePropertyName selectedThemeId -NotePropertyValue $selectedThemeId -Force
      $previousState | Add-Member -NotePropertyName themeDir -NotePropertyValue $ThemeDir -Force
      $previousState | Add-Member `
        -NotePropertyName updatedAt `
        -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') `
        -Force
      Write-DreamSkinState -Path $StatePath -State $previousState
      Write-Host "Codex 皮肤已热切换；现有监视器继续在本机端口 $Port 运行。"
      exit 0
    }
    Write-Warning '实时热切换未通过验证，正在重建皮肤监视器。'
  }

  try {
    $recordedInjectorStopped = Stop-DreamSkinRecordedInjector -State $previousState
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-DreamSkinStateFile -Path $StatePath
      Write-Warning "Archived stale Dream Skin state at $staleStatePath"
    }
  } catch {
    if ($launchedWithCdp) {
      try {
        Stop-DreamSkinCodex -Codex $codex -AllowForce
        Start-Process -FilePath $codex.Executable | Out-Null
      } catch {
        Write-Warning 'State validation rollback could not fully restart Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    throw
  }

  if ($ForegroundInjector) {
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    Exit-DreamSkinOperationLock -Mutex $operationLock
    $operationLock = $null
    & $node.Path $Injector --watch --port $Port --browser-id $cdpIdentity.BrowserId --theme-dir $ThemeDir
    exit $LASTEXITCODE
  }

  $state = $null
  $daemon = $null
  try {
    $injectorArgs = @((ConvertTo-DreamSkinProcessArgument -Value $Injector), '--watch', '--port', "$Port",
      '--browser-id', $cdpIdentity.BrowserId, '--theme-dir', (ConvertTo-DreamSkinProcessArgument -Value $ThemeDir))
    $daemon = Start-Process -FilePath $node.Path -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    Start-Sleep -Milliseconds 500
    if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }

    $injectorStartedAt = Get-DreamSkinProcessStartedAt -ProcessId $daemon.Id
    if (-not $injectorStartedAt) { throw 'The injector process identity could not be recorded safely.' }
    $state = [pscustomobject]@{
      schemaVersion = 3
      platform = 'windows'
      port = $Port
      injectorPid = $daemon.Id
      injectorStartedAt = $injectorStartedAt
      injectorPath = $Injector
      nodePath = $node.Path
      nodeVersion = $node.Version
      codexExe = $codex.Executable
      codexPackageRoot = $codex.PackageRoot
      codexPackageFullName = $codex.PackageFullName
      codexPackageFamilyName = $codex.PackageFamilyName
      codexVersion = $codex.Version
      browserId = $cdpIdentity.BrowserId
      themeDir = $ThemeDir
      selectedThemeId = $selectedThemeId
      profilePath = $ProfilePath
      createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-DreamSkinState -Path $StatePath -State $state

    $verifyOutput = @(& $node.Path $Injector --verify --port $Port --browser-id $cdpIdentity.BrowserId `
      --theme-dir $ThemeDir --timeout-ms 30000 2>&1)
    $verifyExitCode = $LASTEXITCODE
    Write-DreamSkinUtf8FileAtomically -Path $VerifyPath -Content (($verifyOutput -join "`r`n") + "`r`n")
    if ($verifyExitCode -ne 0) { throw "Dream Skin verification failed. See $VerifyPath" }
  } catch {
    $startupError = $_
    $injectorStopped = $true
    if ($null -ne $state) {
      try {
        $injectorStopped = Stop-DreamSkinRecordedInjector -State $state
      } catch {
        $injectorStopped = $false
        Write-Warning $_.Exception.Message
      }
    } elseif ($null -ne $daemon -and -not $daemon.HasExited) {
      try {
        Stop-Process -InputObject $daemon -Force -ErrorAction Stop
        [void]$daemon.WaitForExit(5000)
        $injectorStopped = $daemon.HasExited
      } catch {
        $injectorStopped = $false
        Write-Warning 'The newly created injector could not be stopped during startup rollback.'
      }
    }
    if ($injectorStopped -and -not $launchedWithCdp) {
      try {
        $rollbackIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
        if ($null -ne $rollbackIdentity -and $rollbackIdentity.BrowserId -ceq $cdpIdentity.BrowserId) {
          & $node.Path $Injector --remove --port $Port --browser-id $cdpIdentity.BrowserId `
            --timeout-ms 5000 *> $null
          if ($LASTEXITCODE -ne 0) { throw 'Injector removal returned a failure status.' }
        }
      } catch {
        Write-Warning 'Startup rollback could not remove the partially applied live skin; reload or close Codex to clear it.'
      }
    }
    if ($injectorStopped) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
    if ($launchedWithCdp) {
      try {
        Stop-DreamSkinCodex -Codex $codex -AllowForce
        Start-Process -FilePath $codex.Executable | Out-Null
      } catch {
        Write-Warning 'Startup rollback could not fully restart Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    throw $startupError
  }

  Write-Host "Codex 皮肤管理器已在验证通过的本机端口 $Port 运行。"
  exit 0
} finally {
  if ($null -ne $operationLock) { Exit-DreamSkinOperationLock -Mutex $operationLock }
}
