#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$DestinationRoot,
  [string]$NodePath,
  [string]$EdgePath,
  [string]$ShortcutPath,
  [string]$HarnessRef,
  [switch]$NonInteractive,
  [switch]$AcceptUpstreamScripts,
  [switch]$DownloadOnly,
  [switch]$SkipAudit,
  [switch]$ForceLauncherConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$officialRepositoryUrl = 'https://github.com/deepseek-ai/deepseek-harness.git'
$minimumFreeBytes = 4GB

Add-Type -AssemblyName System.Windows.Forms

function Show-SetupMessage {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][System.Windows.Forms.MessageBoxIcon]$Icon
  )

  if ($NonInteractive) { return }
  [System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    $Icon
  ) | Out-Null
}

function Get-AbsoluteLocalPath {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ([string]::IsNullOrWhiteSpace($Value) -or -not [System.IO.Path]::IsPathRooted($Value)) {
    throw "$Name must be an absolute path on a local drive."
  }
  $fullPath = [System.IO.Path]::GetFullPath($Value)
  if ($fullPath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
    throw "$Name cannot be a network path. Choose a local drive."
  }
  $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
  if ([string]::Equals($fullPath, $pathRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $pathRoot
  }
  return $fullPath.TrimEnd('\')
}

function Select-DestinationRoot {
  if (-not [string]::IsNullOrWhiteSpace($DestinationRoot)) {
    return Get-AbsoluteLocalPath -Value $DestinationRoot -Name 'DestinationRoot'
  }
  if ($NonInteractive) {
    throw 'DestinationRoot is required in non-interactive mode.'
  }

  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  try {
    $dialog.Description = 'Choose where DeepSeek Harness and its data will be installed.'
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath 'D:\' -PathType Container) {
      $dialog.SelectedPath = 'D:\'
    } else {
      $dialog.SelectedPath = [Environment]::GetFolderPath('LocalApplicationData')
    }
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
      exit 2
    }
    return Get-AbsoluteLocalPath -Value $dialog.SelectedPath -Name 'DestinationRoot'
  } finally {
    $dialog.Dispose()
  }
}

function Get-CompatibleNodeInfo {
  param([AllowNull()][string]$Candidate)

  Write-Verbose ("Checking Node candidate: [{0}]" -f $Candidate)
  if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
  try {
    if (-not [System.IO.Path]::IsPathRooted($Candidate)) {
      Write-Verbose 'Node candidate is not absolute.'
      return $null
    }
    $fullPath = [System.IO.Path]::GetFullPath($Candidate)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
      Write-Verbose 'Node candidate does not exist.'
      return $null
    }
    if (-not [string]::Equals((Split-Path -Leaf $fullPath), 'node.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
      Write-Verbose 'Node candidate filename is not node.exe.'
      return $null
    }
    $versionLines = @(& $fullPath --version 2>$null)
    $nodeExitCode = $LASTEXITCODE
    $versionText = $versionLines | Select-Object -First 1
    Write-Verbose ("Node candidate version output: [{0}], exit code: {1}" -f $versionText, $nodeExitCode)
    if ($nodeExitCode -ne 0) { return $null }
    $match = [regex]::Match([string]$versionText, '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$')
    if (-not $match.Success) {
      Write-Verbose 'Node candidate version output did not match semver.'
      return $null
    }
    $major = [int]$match.Groups['major'].Value
    $minor = [int]$match.Groups['minor'].Value
    if (-not (($major -eq 22 -and $minor -ge 19) -or $major -ge 24)) {
      Write-Verbose 'Node candidate version is outside the supported range.'
      return $null
    }
    return [pscustomobject]@{
      Path = $fullPath
      Version = [string]$versionText
    }
  } catch {
    Write-Verbose ("Node candidate check failed: {0}" -f $_.Exception.Message)
    return $null
  }
}

function Find-CompatibleNode {
  Write-Verbose ("Requested NodePath: [{0}]" -f $NodePath)
  if (-not [string]::IsNullOrWhiteSpace($NodePath)) {
    $requested = Get-CompatibleNodeInfo -Candidate $NodePath
    if ($null -eq $requested) {
      throw 'The requested NodePath is missing or incompatible. DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0.'
    }
    return $requested
  }

  $candidates = New-Object 'System.Collections.Generic.List[string]'
  $nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $nodeCommand) { $candidates.Add($nodeCommand.Source) }
  if (-not [string]::IsNullOrWhiteSpace($env:NVM_SYMLINK)) {
    $candidates.Add((Join-Path $env:NVM_SYMLINK 'node.exe'))
  }
  if (-not [string]::IsNullOrWhiteSpace($env:NVM_HOME) -and (Test-Path -LiteralPath $env:NVM_HOME -PathType Container)) {
    foreach ($versionDir in (Get-ChildItem -LiteralPath $env:NVM_HOME -Directory -Filter 'v*' | Sort-Object Name -Descending)) {
      $candidates.Add((Join-Path $versionDir.FullName 'node.exe'))
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\node.exe'))
  }
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe'))
  }

  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($candidate in $candidates) {
    if (-not $seen.Add($candidate)) { continue }
    $info = Get-CompatibleNodeInfo -Candidate $candidate
    if ($null -ne $info) { return $info }
  }

  if (-not $NonInteractive) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
      $dialog.Title = 'Select a compatible node.exe'
      $dialog.Filter = 'Node.js executable (node.exe)|node.exe'
      $dialog.CheckFileExists = $true
      $dialog.Multiselect = $false
      if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selected = Get-CompatibleNodeInfo -Candidate $dialog.FileName
        if ($null -ne $selected) { return $selected }
      }
    } finally {
      $dialog.Dispose()
    }
  }

  throw 'Compatible Node.js was not found. Install Node.js ^22.19.0 or >=24.0.0, then run setup again.'
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$Description
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE."
  }
}

function Get-PnpmRunner {
  param(
    [Parameter(Mandatory = $true)][string]$SelectedNodePath,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion
  )

  $nodeDir = Split-Path -Parent $SelectedNodePath
  $corepackPath = Join-Path $nodeDir 'corepack.cmd'
  if (Test-Path -LiteralPath $corepackPath -PathType Leaf) {
    $versionLines = @(& $corepackPath pnpm --version 2>&1)
    $versionExitCode = $LASTEXITCODE
    $versionOutput = $versionLines | Select-Object -Last 1
    if ($versionExitCode -ne 0 -or -not [string]::Equals(
        ([string]$versionOutput).Trim(),
        $ExpectedVersion,
        [System.StringComparison]::Ordinal
      )) {
      throw "Corepack did not provide the pnpm version pinned by Harness: $ExpectedVersion"
    }
    return [pscustomobject]@{
      FilePath = $corepackPath
      Prefix = @('pnpm')
    }
  }

  $npxPath = Join-Path $nodeDir 'npx.cmd'
  if (-not (Test-Path -LiteralPath $npxPath -PathType Leaf)) {
    throw 'Neither corepack.cmd nor npx.cmd was found beside node.exe.'
  }
  $versionLines = @(& $npxPath --yes "pnpm@$ExpectedVersion" --version 2>&1)
  $versionExitCode = $LASTEXITCODE
  $versionOutput = $versionLines | Select-Object -Last 1
  if ($versionExitCode -ne 0 -or -not [string]::Equals(
      ([string]$versionOutput).Trim(),
      $ExpectedVersion,
      [System.StringComparison]::Ordinal
    )) {
    throw "npx did not provide the pnpm version pinned by Harness: $ExpectedVersion"
  }
  return [pscustomobject]@{
    FilePath = $npxPath
    Prefix = @('--yes', "pnpm@$ExpectedVersion")
  }
}

function Invoke-PnpmCommand {
  param(
    [Parameter(Mandatory = $true)][psobject]$Runner,
    [Parameter(Mandatory = $true)][string[]]$CommandArguments,
    [Parameter(Mandatory = $true)][string]$Description,
    [switch]$AllowFailure,
    [ref]$ResultExitCode
  )

  $allArguments = @($Runner.Prefix) + $CommandArguments
  & $Runner.FilePath @allArguments
  $exitCode = $LASTEXITCODE
  if ($null -ne $ResultExitCode) { $ResultExitCode.Value = $exitCode }
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "$Description failed with exit code $exitCode."
  }
}

function New-PnpmShim {
  param(
    [Parameter(Mandatory = $true)][psobject]$Runner,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if ($Runner.FilePath.IndexOf('"', [System.StringComparison]::Ordinal) -ge 0) {
    throw 'The package-manager executable path contains an unsupported quote character.'
  }
  foreach ($argument in $Runner.Prefix) {
    if ([string]$argument -notmatch '^[A-Za-z0-9@._\-]+$') {
      throw 'The package-manager shim received an unsupported argument.'
    }
  }

  $shimDir = Join-Path $RootPath ('.dsh-desktop-tools-' + $PID)
  if (Test-Path -LiteralPath $shimDir) {
    throw "Temporary package-manager path already exists: $shimDir"
  }
  New-Item -ItemType Directory -Path $shimDir | Out-Null

  $prefixText = (@($Runner.Prefix) | ForEach-Object { '"' + [string]$_ + '"' }) -join ' '
  $shimText = "@echo off`r`n`"$($Runner.FilePath)`" $prefixText %*`r`n"
  $shimPath = Join-Path $shimDir 'pnpm.cmd'
  [System.IO.File]::WriteAllText($shimPath, $shimText, [System.Text.Encoding]::ASCII)
  return $shimDir
}

function Remove-PnpmShim {
  param(
    [AllowNull()][string]$ShimDir,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if ([string]::IsNullOrWhiteSpace($ShimDir) -or -not (Test-Path -LiteralPath $ShimDir -PathType Container)) {
    return
  }
  $resolvedShim = [System.IO.Path]::GetFullPath($ShimDir)
  $resolvedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
  if (-not $resolvedShim.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return }
  if (-not (Split-Path -Leaf $resolvedShim).StartsWith('.dsh-desktop-tools-', [System.StringComparison]::Ordinal)) {
    return
  }

  $shimPath = Join-Path $resolvedShim 'pnpm.cmd'
  if (Test-Path -LiteralPath $shimPath -PathType Leaf) {
    Remove-Item -LiteralPath $shimPath -Force
  }
  Remove-Item -LiteralPath $resolvedShim -Force -ErrorAction SilentlyContinue
}

function Invoke-Setup {
  $root = Select-DestinationRoot
  if (Test-Path -LiteralPath $root -PathType Leaf) {
    throw "DestinationRoot points to a file: $root"
  }

  if (-not [string]::IsNullOrWhiteSpace($HarnessRef)) {
    if ($HarnessRef.StartsWith('-', [System.StringComparison]::Ordinal) -or $HarnessRef -notmatch '^[A-Za-z0-9._/\-]{1,200}$') {
      throw 'HarnessRef contains unsupported characters.'
    }
  }

  $harnessDir = Join-Path $root 'deepseek-harness'
  $dataDir = Join-Path $root 'deepseek-harness-data'
  if (Test-Path -LiteralPath $harnessDir) {
    throw "Refusing to overwrite an existing Harness path: $harnessDir"
  }

  $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $gitCommand) {
    throw 'Git for Windows was not found. Install Git, then run setup again.'
  }
  $nodeInfo = Find-CompatibleNode

  $confirmation = @(
    'DeepSeek Harness will be downloaded from:',
    $officialRepositoryUrl,
    '',
    "Program: $harnessDir",
    "Data:    $dataDir",
    "Node:    $($nodeInfo.Path) ($($nodeInfo.Version))"
  )
  if (-not $DownloadOnly) {
    $confirmation += @(
      '',
      'The official locked dependencies and reviewed install scripts will run before the project is built.'
    )
  }
  $confirmation += @('', 'Continue?')

  if ($NonInteractive) {
    if (-not $DownloadOnly -and -not $AcceptUpstreamScripts) {
      throw 'AcceptUpstreamScripts is required for a non-interactive full installation.'
    }
  } else {
    $answer = [System.Windows.Forms.MessageBox]::Show(
      ($confirmation -join [Environment]::NewLine),
      'Install DeepSeek Harness',
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { exit 2 }
  }

  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    New-Item -ItemType Directory -Path $root | Out-Null
  }

  $driveRoot = [System.IO.Path]::GetPathRoot($root)
  try {
    $drive = New-Object System.IO.DriveInfo($driveRoot)
    if ($drive.IsReady -and $drive.AvailableFreeSpace -lt $minimumFreeBytes) {
      throw 'At least 4 GB of free space is required for the source checkout, dependencies, and build.'
    }
  } catch [System.IO.IOException] {
    throw "Unable to inspect free space for: $driveRoot"
  }

  Write-Host '[1/6] Cloning the official DeepSeek Harness repository...'
  $cloneArguments = @('clone', '--depth', '1', '--single-branch')
  if (-not [string]::IsNullOrWhiteSpace($HarnessRef)) {
    $cloneArguments += @('--branch', $HarnessRef)
  }
  $cloneArguments += @('--', $officialRepositoryUrl, $harnessDir)
  Invoke-NativeCommand -FilePath $gitCommand.Source -ArgumentList $cloneArguments -Description 'Official Harness clone'

  $originLines = @(& $gitCommand.Source -C $harnessDir remote get-url origin)
  $originExitCode = $LASTEXITCODE
  $origin = $originLines | Select-Object -First 1
  if ($originExitCode -ne 0 -or -not [string]::Equals(
      ([string]$origin).Trim(),
      $officialRepositoryUrl,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'The cloned repository origin is not the official DeepSeek Harness URL.'
  }
  $commitLines = @(& $gitCommand.Source -C $harnessDir rev-parse HEAD)
  $commitExitCode = $LASTEXITCODE
  $commit = $commitLines | Select-Object -First 1
  if ($commitExitCode -ne 0 -or ([string]$commit) -notmatch '^[0-9a-f]{40}$') {
    throw 'Unable to verify the cloned Harness commit.'
  }

  if ($DownloadOnly) {
    $message = "Official DeepSeek Harness was downloaded.`n`nPath: $harnessDir`nCommit: $commit"
    Write-Output $message
    Show-SetupMessage -Title 'Download complete' -Message $message -Icon Information
    return
  }

  Write-Host '[2/6] Verifying the upstream package manager and lockfile...'
  foreach ($requiredFile in @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $harnessDir $requiredFile) -PathType Leaf)) {
      throw "The official checkout is missing: $requiredFile"
    }
  }
  $package = Get-Content -LiteralPath (Join-Path $harnessDir 'package.json') -Raw | ConvertFrom-Json
  $nodeEngine = [string]$package.engines.node
  if (-not [string]::Equals($nodeEngine, '^22.19.0 || >=24.0.0', [System.StringComparison]::Ordinal)) {
    throw "The official checkout changed its Node.js requirement. Review before installing: $nodeEngine"
  }
  $packageManager = [string]$package.packageManager
  $managerMatch = [regex]::Match($packageManager, '^pnpm@(?<version>\d+\.\d+\.\d+)$')
  if (-not $managerMatch.Success) {
    throw "The official checkout requested an unsupported package manager: $packageManager"
  }
  $pnpmVersion = $managerMatch.Groups['version'].Value
  $workspacePolicy = Get-Content -LiteralPath (Join-Path $harnessDir 'pnpm-workspace.yaml') -Raw
  if ($workspacePolicy -notmatch '(?m)^allowBuilds:\s*$') {
    throw 'The official checkout no longer contains the expected dependency-build allowlist.'
  }

  $nodeDir = Split-Path -Parent $nodeInfo.Path
  $originalPath = $env:PATH
  $hadCorepackPrompt = Test-Path -LiteralPath 'Env:\COREPACK_ENABLE_DOWNLOAD_PROMPT'
  $originalCorepackPrompt = [Environment]::GetEnvironmentVariable('COREPACK_ENABLE_DOWNLOAD_PROMPT', 'Process')
  $hadPnpmSelfUpdate = Test-Path -LiteralPath 'Env:\PNPM_DISABLE_SELF_UPDATE_CHECK'
  $originalPnpmSelfUpdate = [Environment]::GetEnvironmentVariable('PNPM_DISABLE_SELF_UPDATE_CHECK', 'Process')
  $env:PATH = $nodeDir + ';' + $env:PATH
  $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
  $env:PNPM_DISABLE_SELF_UPDATE_CHECK = '1'

  $shimDir = $null
  Push-Location $harnessDir
  try {
    $runner = Get-PnpmRunner -SelectedNodePath $nodeInfo.Path -ExpectedVersion $pnpmVersion
    $shimDir = New-PnpmShim -Runner $runner -RootPath $root
    $env:PATH = $shimDir + ';' + $nodeDir + ';' + $originalPath

    Write-Host "[3/6] Installing locked dependencies with pnpm $pnpmVersion..."
    Invoke-PnpmCommand -Runner $runner -CommandArguments @('install', '--frozen-lockfile', '--reporter=append-only') -Description 'Dependency installation'

    Write-Host '[4/6] Building DeepSeek Harness...'
    Invoke-PnpmCommand -Runner $runner -CommandArguments @('run', 'build') -Description 'Harness build'

    $auditWarning = $false
    if (-not $SkipAudit) {
      Write-Host '[5/6] Auditing the upstream dependency lockfile...'
      $auditExit = 0
      Invoke-PnpmCommand -Runner $runner -CommandArguments @('audit', '--audit-level', 'high') -Description 'Dependency audit' -AllowFailure -ResultExitCode ([ref]$auditExit)
      if ($auditExit -ne 0) {
        $auditWarning = $true
        Write-Warning 'The upstream dependency audit reported high-severity advisories. Review the audit output before sensitive use.'
      }
    }
  } finally {
    Pop-Location
    $env:PATH = $originalPath
    if ($hadCorepackPrompt) {
      $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = $originalCorepackPrompt
    } else {
      Remove-Item -LiteralPath 'Env:\COREPACK_ENABLE_DOWNLOAD_PROMPT' -ErrorAction SilentlyContinue
    }
    if ($hadPnpmSelfUpdate) {
      $env:PNPM_DISABLE_SELF_UPDATE_CHECK = $originalPnpmSelfUpdate
    } else {
      Remove-Item -LiteralPath 'Env:\PNPM_DISABLE_SELF_UPDATE_CHECK' -ErrorAction SilentlyContinue
    }
    Remove-PnpmShim -ShimDir $shimDir -RootPath $root
  }

  foreach ($builtFile in @(
      (Join-Path $harnessDir 'apps\cli\src\bin.ts'),
      (Join-Path $harnessDir 'apps\web\dist\index.html'),
      (Join-Path $harnessDir 'node_modules\tsx')
    )) {
    if (-not (Test-Path -LiteralPath $builtFile)) {
      throw "The Harness build did not produce a required file: $builtFile"
    }
  }

  Write-Host '[6/6] Creating the launcher configuration and desktop shortcut...'
  $installParameters = @{
    HarnessDir = $harnessDir
    DataDir = $dataDir
    NodePath = $nodeInfo.Path
  }
  if (-not [string]::IsNullOrWhiteSpace($EdgePath)) { $installParameters.EdgePath = $EdgePath }
  if (-not [string]::IsNullOrWhiteSpace($ShortcutPath)) { $installParameters.ShortcutPath = $ShortcutPath }
  if ($ForceLauncherConfig) { $installParameters.Force = $true }
  & (Join-Path $PSScriptRoot 'Install.ps1') @installParameters

  $successLines = @(
    'DeepSeek Harness installation completed.',
    '',
    "Program: $harnessDir",
    "Data:    $dataDir",
    "Commit:  $commit"
  )
  if ($auditWarning) {
    $successLines += @('', 'Warning: the upstream dependency audit reported high-severity advisories. See the setup console output.')
  }
  $successMessage = $successLines -join [Environment]::NewLine
  Write-Output $successMessage
  Show-SetupMessage -Title 'Installation complete' -Message $successMessage -Icon Information
}

try {
  Invoke-Setup
} catch {
  $message = $_.Exception.Message
  Write-Error $message
  Show-SetupMessage -Title 'DeepSeek Harness setup failed' -Message $message -Icon Error
  exit 1
}
