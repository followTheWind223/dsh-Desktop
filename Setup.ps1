#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$DestinationRoot,
  [string]$NodePath,
  [string]$EdgePath,
  [string]$ShortcutPath,
  [string]$HarnessRef,
  [ValidateSet('auto', 'zh-CN', 'en-US')][string]$Language = 'auto',
  [switch]$NonInteractive,
  [switch]$Inspect,
  [switch]$AcceptUpstreamScripts,
  [switch]$AcceptUnverifiedHarness,
  [switch]$DownloadNode,
  [switch]$NodeOnly,
  [switch]$DownloadOnly,
  [switch]$SkipAudit,
  [switch]$CreateDesktopShortcut,
  [switch]$CreateStartMenuShortcut,
  [switch]$RemoveDesktopShortcut,
  [switch]$RemoveStartMenuShortcut,
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
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $candidates = New-Object 'System.Collections.Generic.List[string]'
  $portableRoot = Join-Path $RootPath 'nodejs'
  if (Test-Path -LiteralPath $portableRoot -PathType Container) {
    foreach ($portableVersion in (Get-ChildItem -LiteralPath $portableRoot -Directory -Filter 'node-v*-win-*' | Sort-Object Name -Descending)) {
      $candidates.Add((Join-Path $portableVersion.FullName 'node.exe'))
    }
  }
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

  return $null
}

function Select-NodeFile {
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  try {
    $dialog.Title = 'Select a compatible node.exe'
    $dialog.Filter = 'Node.js executable (node.exe)|node.exe'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 2 }
    $selected = Get-CompatibleNodeInfo -Candidate $dialog.FileName
    if ($null -eq $selected) {
      throw 'The selected node.exe is incompatible. DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0.'
    }
    return $selected
  } finally {
    $dialog.Dispose()
  }
}

function Select-NodePlan {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  Write-Verbose ("Requested NodePath: [{0}]" -f $NodePath)
  if (-not [string]::IsNullOrWhiteSpace($NodePath) -and $DownloadNode) {
    throw 'NodePath and DownloadNode cannot be used together.'
  }
  if (-not [string]::IsNullOrWhiteSpace($NodePath)) {
    $requested = Get-CompatibleNodeInfo -Candidate $NodePath
    if ($null -eq $requested) {
      throw 'The requested NodePath is missing or incompatible. DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0.'
    }
    return [pscustomobject]@{ Mode = 'Existing'; Info = $requested }
  }
  if ($DownloadNode) {
    return [pscustomobject]@{ Mode = 'Download'; Info = $null }
  }

  $discovered = Find-CompatibleNode -RootPath $RootPath
  if ($NonInteractive) {
    if ($null -eq $discovered) {
      throw 'Compatible Node.js was not found. Pass -DownloadNode to install an official portable LTS release, or pass -NodePath.'
    }
    return [pscustomobject]@{ Mode = 'Existing'; Info = $discovered }
  }

  if ($null -ne $discovered) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
      ("Compatible Node.js was found:`n`n{0} ({1})`n`nYes: use it`nNo: download an official portable Node.js LTS`nCancel: stop setup" -f $discovered.Path, $discovered.Version),
      'Choose Node.js',
      [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
      return [pscustomobject]@{ Mode = 'Existing'; Info = $discovered }
    }
    if ($answer -eq [System.Windows.Forms.DialogResult]::No) {
      return [pscustomobject]@{ Mode = 'Download'; Info = $null }
    }
    exit 2
  }

  $answer = [System.Windows.Forms.MessageBox]::Show(
    "A compatible Node.js installation was not found.`n`nYes: download an official portable Node.js LTS`nNo: select an existing node.exe`nCancel: stop setup",
    'Node.js is required',
    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )
  if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
    return [pscustomobject]@{ Mode = 'Download'; Info = $null }
  }
  if ($answer -eq [System.Windows.Forms.DialogResult]::No) {
    return [pscustomobject]@{ Mode = 'Existing'; Info = (Select-NodeFile) }
  }
  exit 2
}

function Get-WindowsNodeArtifact {
  $nativeArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
    $env:PROCESSOR_ARCHITEW6432
  } else {
    $env:PROCESSOR_ARCHITECTURE
  }
  switch ($nativeArchitecture.ToUpperInvariant()) {
    'AMD64' { return 'win-x64' }
    'ARM64' { return 'win-arm64' }
    default { throw "Portable Node.js setup supports only 64-bit x64 or ARM64 Windows. Found: $nativeArchitecture" }
  }
}

function Invoke-OfficialNodeDownload {
  param(
    [Parameter(Mandatory = $true)][uri]$Uri,
    [Parameter(Mandatory = $true)][string]$OutFile
  )

  if (-not [string]::Equals($Uri.Scheme, 'https', [System.StringComparison]::OrdinalIgnoreCase) -or
      -not [string]::Equals($Uri.Host, 'nodejs.org', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing a non-official Node.js download URL: $Uri"
  }
  Invoke-WebRequest -UseBasicParsing -Uri $Uri.AbsoluteUri -OutFile $OutFile -MaximumRedirection 0
  if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) {
    throw "The official Node.js download did not create: $OutFile"
  }
}

function Remove-NodeTemporaryDirectory {
  param(
    [AllowNull()][string]$TemporaryDirectory,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if ([string]::IsNullOrWhiteSpace($TemporaryDirectory) -or -not (Test-Path -LiteralPath $TemporaryDirectory -PathType Container)) {
    return
  }
  $resolvedTemporary = [System.IO.Path]::GetFullPath($TemporaryDirectory)
  $resolvedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
  if (-not $resolvedTemporary.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return }
  if (-not (Split-Path -Leaf $resolvedTemporary).StartsWith('.dsh-desktop-node-', [System.StringComparison]::Ordinal)) { return }
  Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
}

function Install-PortableNode {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $artifact = Get-WindowsNodeArtifact
  $temporaryDirectory = Join-Path $RootPath ('.dsh-desktop-node-' + $PID)
  if (Test-Path -LiteralPath $temporaryDirectory) {
    throw "Temporary Node.js download path already exists: $temporaryDirectory"
  }
  New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

  $indexPath = Join-Path $temporaryDirectory 'index.json'
  $checksumPath = Join-Path $temporaryDirectory 'SHASUMS256.txt'
  $archivePath = $null
  $originalSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
  $originalProgressPreference = $ProgressPreference
  try {
    [System.Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Write-Host 'Downloading the official Node.js release index...'
    Invoke-OfficialNodeDownload -Uri ([uri]'https://nodejs.org/dist/index.json') -OutFile $indexPath
    if ((Get-Item -LiteralPath $indexPath).Length -gt 5MB) { throw 'The Node.js release index is unexpectedly large.' }

    $releaseIndex = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseCandidates = @($releaseIndex | Where-Object {
        $match = [regex]::Match([string]$_.version, '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$')
        $match.Success -and $_.lts -and
        ((([int]$match.Groups['major'].Value -eq 22) -and ([int]$match.Groups['minor'].Value -ge 19)) -or
          ([int]$match.Groups['major'].Value -ge 24)) -and
        ($_.files -contains ($artifact + '-zip'))
      } | Sort-Object { [version]($_.version.TrimStart('v')) } -Descending)
    $release = $releaseCandidates | Select-Object -First 1
    if ($null -eq $release) { throw "No compatible official Node.js LTS ZIP was found for $artifact." }

    $version = [string]$release.version
    $folderName = "node-$version-$artifact"
    $archiveName = $folderName + '.zip'
    $nodeParent = Join-Path $RootPath 'nodejs'
    $finalDirectory = Join-Path $nodeParent $folderName
    if (Test-Path -LiteralPath $finalDirectory) {
      $existingPortable = Get-CompatibleNodeInfo -Candidate (Join-Path $finalDirectory 'node.exe')
      if ($null -eq $existingPortable -or -not [string]::Equals($existingPortable.Version, $version, [System.StringComparison]::Ordinal)) {
        throw "Refusing to overwrite an invalid existing portable Node.js path: $finalDirectory"
      }
      Write-Host ("Compatible portable Node.js already exists and will be reused: {0} ({1})" -f $existingPortable.Path, $existingPortable.Version)
      return [pscustomobject]@{ Path = $existingPortable.Path; Version = $existingPortable.Version; InstalledNew = $false }
    }

    $releaseBase = [uri]("https://nodejs.org/dist/{0}/" -f $version)
    Invoke-OfficialNodeDownload -Uri ([uri]::new($releaseBase, 'SHASUMS256.txt')) -OutFile $checksumPath
    if ((Get-Item -LiteralPath $checksumPath).Length -gt 5MB) { throw 'The Node.js checksum manifest is unexpectedly large.' }
    $archivePath = Join-Path $temporaryDirectory $archiveName
    Write-Host ("Downloading official Node.js {0} LTS ({1})..." -f $version, $artifact)
    Invoke-OfficialNodeDownload -Uri ([uri]::new($releaseBase, $archiveName)) -OutFile $archivePath
    $archiveLength = (Get-Item -LiteralPath $archivePath).Length
    if ($archiveLength -lt 1MB -or $archiveLength -gt 200MB) { throw 'The Node.js ZIP size is outside the expected range.' }

    $manifest = Get-Content -LiteralPath $checksumPath -Raw -Encoding UTF8
    $checksumMatch = [regex]::Match(
      $manifest,
      ('(?mi)^(?<hash>[0-9a-f]{64})\s+\*?' + [regex]::Escape($archiveName) + '\s*$')
    )
    if (-not $checksumMatch.Success) { throw "The official checksum manifest does not list: $archiveName" }
    $expectedHash = $checksumMatch.Groups['hash'].Value.ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if (-not [string]::Equals($expectedHash, $actualHash, [System.StringComparison]::Ordinal)) {
      throw 'The downloaded Node.js ZIP failed SHA-256 verification.'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
      if ($archive.Entries.Count -gt 10000) { throw 'The Node.js ZIP contains an unexpected number of entries.' }
      [long]$expandedBytes = 0
      foreach ($entry in $archive.Entries) {
        $entryName = $entry.FullName.Replace('\', '/')
        $segments = @($entryName.Split('/') | Where-Object { $_.Length -gt 0 })
        if ([System.IO.Path]::IsPathRooted($entryName) -or $segments -contains '..' -or
            -not ($entryName -eq $folderName -or $entryName.StartsWith($folderName + '/', [System.StringComparison]::Ordinal))) {
          throw "The Node.js ZIP contains an unsafe path: $entryName"
        }
        $expandedBytes += $entry.Length
        if ($expandedBytes -gt 1GB) { throw 'The expanded Node.js ZIP is unexpectedly large.' }
      }
    } finally {
      $archive.Dispose()
    }

    $extractRoot = Join-Path $temporaryDirectory 'expanded'
    New-Item -ItemType Directory -Path $extractRoot | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
    $extractedDirectory = Join-Path $extractRoot $folderName
    $nodeExecutable = Join-Path $extractedDirectory 'node.exe'
    $nodeInfo = Get-CompatibleNodeInfo -Candidate $nodeExecutable
    if ($null -eq $nodeInfo -or -not [string]::Equals($nodeInfo.Version, $version, [System.StringComparison]::Ordinal)) {
      throw 'The extracted Node.js executable did not match the selected official release.'
    }

    if (-not (Test-Path -LiteralPath $nodeParent -PathType Container)) {
      New-Item -ItemType Directory -Path $nodeParent | Out-Null
    }
    Move-Item -LiteralPath $extractedDirectory -Destination $finalDirectory
    $installedNode = Get-CompatibleNodeInfo -Candidate (Join-Path $finalDirectory 'node.exe')
    if ($null -eq $installedNode) { throw 'The portable Node.js installation could not be verified after extraction.' }
    Write-Host ("Portable Node.js installed: {0} ({1})" -f $installedNode.Path, $installedNode.Version)
    return [pscustomobject]@{ Path = $installedNode.Path; Version = $installedNode.Version; InstalledNew = $true }
  } finally {
    $ProgressPreference = $originalProgressPreference
    [System.Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    Remove-NodeTemporaryDirectory -TemporaryDirectory $temporaryDirectory -RootPath $RootPath
  }
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

function Get-NormalizedRepositoryUrl {
  param([AllowNull()][string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return $Value.Trim().TrimEnd('/').ToLowerInvariant()
}

function Get-HarnessState {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowNull()]$GitCommand,
    [switch]$AllowUnverified
  )

  $result = [ordered]@{
    Path = $Path
    State = 'Missing'
    Trusted = $false
    Ready = $false
    Origin = $null
    Commit = $null
    Reason = $null
  }
  if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]$result }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    $result.State = 'Invalid'
    $result.Reason = 'The Harness path is not a directory.'
    return [pscustomobject]$result
  }

  foreach ($requiredSource in @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'apps\cli\src\bin.ts')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Path $requiredSource) -PathType Leaf)) {
      $result.State = 'Invalid'
      $result.Reason = "The existing directory is not a compatible Harness checkout. Missing: $requiredSource"
      return [pscustomobject]$result
    }
  }

  if (Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container) {
    if ($null -eq $GitCommand) {
      $result.State = 'Invalid'
      $result.Reason = 'Git is required to verify the existing Harness checkout.'
      return [pscustomobject]$result
    }
    $originLines = @(& $GitCommand.Source -C $Path remote get-url origin 2>$null)
    $originExitCode = $LASTEXITCODE
    $result.Origin = [string]($originLines | Select-Object -First 1)
    if ($originExitCode -ne 0 -or
        (Get-NormalizedRepositoryUrl -Value $result.Origin) -ne (Get-NormalizedRepositoryUrl -Value $officialRepositoryUrl)) {
      $result.State = 'Invalid'
      $result.Reason = 'The existing Harness Git origin is not the official DeepSeek repository.'
      return [pscustomobject]$result
    }
    $commitLines = @(& $GitCommand.Source -C $Path rev-parse HEAD 2>$null)
    $commitExitCode = $LASTEXITCODE
    $result.Commit = [string]($commitLines | Select-Object -First 1)
    if ($commitExitCode -ne 0 -or $result.Commit -notmatch '^[0-9a-f]{40}$') {
      $result.State = 'Invalid'
      $result.Reason = 'Unable to verify the existing Harness commit.'
      return [pscustomobject]$result
    }
    $result.Trusted = $true
  } elseif (-not $AllowUnverified) {
    $result.State = 'Invalid'
    $result.Reason = 'The existing Harness directory has no Git metadata and cannot be verified. Use -AcceptUnverifiedHarness only if you trust its source.'
    return [pscustomobject]$result
  }

  $result.Ready = (
    (Test-Path -LiteralPath (Join-Path $Path 'apps\web\dist\index.html') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $Path 'node_modules\tsx\package.json') -PathType Leaf)
  )
  $result.State = if ($result.Ready) { 'Ready' } else { 'Source' }
  return [pscustomobject]$result
}

function Get-WebView2State {
  $clientId = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
  $locations = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$clientId",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$clientId",
    "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$clientId"
  )
  foreach ($location in $locations) {
    if (-not (Test-Path -LiteralPath $location)) { continue }
    $version = [string](Get-ItemPropertyValue -LiteralPath $location -Name 'pv' -ErrorAction SilentlyContinue)
    if (-not [string]::IsNullOrWhiteSpace($version) -and $version -ne '0.0.0.0') {
      return [pscustomobject]@{ Available = $true; Version = $version }
    }
  }
  return [pscustomobject]@{ Available = $false; Version = $null }
}

function Write-InspectionResult {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [AllowNull()]$GitCommand
  )

  $harnessPath = Join-Path $RootPath 'deepseek-harness'
  $harness = Get-HarnessState -Path $harnessPath -GitCommand $GitCommand -AllowUnverified:$AcceptUnverifiedHarness
  $compatibleNode = Find-CompatibleNode -RootPath $RootPath
  $pathNode = $null
  $pathNodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $pathNodeCommand) {
    $versionLines = @(& $pathNodeCommand.Source --version 2>$null)
    $pathNode = [pscustomobject]@{
      Path = $pathNodeCommand.Source
      Version = [string]($versionLines | Select-Object -First 1)
      Compatible = ($null -ne (Get-CompatibleNodeInfo -Candidate $pathNodeCommand.Source))
    }
  }
  [pscustomobject]@{
    SchemaVersion = 1
    Root = $RootPath
    LauncherDir = (Join-Path $RootPath 'dsh-desktop')
    Harness = $harness
    Data = [pscustomobject]@{
      Path = (Join-Path $RootPath 'deepseek-harness-data')
      Exists = (Test-Path -LiteralPath (Join-Path $RootPath 'deepseek-harness-data') -PathType Container)
    }
    CompatibleNode = $compatibleNode
    PathNode = $pathNode
    GitAvailable = ($null -ne $GitCommand)
    WebView2 = (Get-WebView2State)
  } | ConvertTo-Json -Depth 7
}

function Invoke-Setup {
  $root = Select-DestinationRoot
  if (Test-Path -LiteralPath $root -PathType Leaf) {
    throw "DestinationRoot points to a file: $root"
  }
  if ($NodeOnly -and $DownloadOnly) { throw 'NodeOnly and DownloadOnly cannot be used together.' }
  if ($NodeOnly -and -not $DownloadNode) { throw 'NodeOnly requires DownloadNode.' }
  if ($Inspect -and ($NodeOnly -or $DownloadOnly -or $DownloadNode)) {
    throw 'Inspect cannot be combined with installation-only switches.'
  }
  if (-not [string]::IsNullOrWhiteSpace($HarnessRef) -and
      ($HarnessRef.StartsWith('-', [System.StringComparison]::Ordinal) -or $HarnessRef -notmatch '^[A-Za-z0-9._/\-]{1,200}$')) {
    throw 'HarnessRef contains unsupported characters.'
  }

  $harnessDir = Join-Path $root 'deepseek-harness'
  $dataDir = Join-Path $root 'deepseek-harness-data'
  $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($Inspect) {
    Write-InspectionResult -RootPath $root -GitCommand $gitCommand
    return
  }

  $harnessState = $null
  if (-not $NodeOnly) {
    $harnessState = Get-HarnessState -Path $harnessDir -GitCommand $gitCommand -AllowUnverified:$AcceptUnverifiedHarness
    if ($harnessState.State -eq 'Invalid') { throw $harnessState.Reason }
    if ($harnessState.State -eq 'Missing' -and $null -eq $gitCommand) {
      throw 'Git for Windows was not found. Git is required only when the official Harness must be downloaded.'
    }
  }

  $nodePlan = $null
  $nodeInfo = $null
  if (-not $DownloadOnly) {
    $nodePlan = Select-NodePlan -RootPath $root
    if ($nodePlan.Mode -eq 'Existing') { $nodeInfo = $nodePlan.Info }
  }

  $requiresBuild = (-not $NodeOnly -and -not $DownloadOnly -and $harnessState.State -ne 'Ready')
  if ($NonInteractive -and $requiresBuild -and -not $AcceptUpstreamScripts) {
    throw 'AcceptUpstreamScripts is required because dependencies must be installed and the upstream project must be built.'
  }

  if ($NodeOnly) {
    $confirmation = @(
      'An official portable Node.js LTS release will be downloaded from:',
      'https://nodejs.org/dist/', '',
      ("Destination: {0}" -f (Join-Path $root 'nodejs')),
      'The ZIP must match the SHA-256 value in the official release manifest.'
    )
  } else {
    $harnessAction = switch ($harnessState.State) {
      'Ready' { 'reuse the existing ready installation' }
      'Source' { 'reuse the verified source and finish its build' }
      default { 'download the official repository' }
    }
    $confirmation = @(
      "Harness: $harnessAction",
      "Program: $harnessDir",
      "Data:    $dataDir"
    )
    if (-not $DownloadOnly) {
      if ($nodePlan.Mode -eq 'Download') {
        $confirmation += "Node:    download official portable LTS to $(Join-Path $root 'nodejs')"
      } else {
        $confirmation += "Node:    reuse $($nodeInfo.Path) ($($nodeInfo.Version))"
      }
    }
    if ($requiresBuild) {
      $confirmation += @('', 'The official locked dependencies and reviewed install scripts will run before the project is built.')
    }
  }
  $confirmation += @('', 'Continue?')

  if (-not $NonInteractive) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
      ($confirmation -join [Environment]::NewLine),
      $(if ($NodeOnly) { 'Install portable Node.js' } else { 'Configure DSH Desktop' }),
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
    $requiredFreeBytes = if ($NodeOnly) { 1GB } elseif ($harnessState.State -eq 'Ready') { 512MB } else { $minimumFreeBytes }
    if ($drive.IsReady -and $drive.AvailableFreeSpace -lt $requiredFreeBytes) {
      throw "At least $([math]::Ceiling($requiredFreeBytes / 1GB)) GB of free space is required."
    }
  } catch [System.IO.IOException] {
    throw "Unable to inspect free space for: $driveRoot"
  }

  $nodeManaged = $false
  if ($null -ne $nodePlan -and $nodePlan.Mode -eq 'Download') {
    $nodeInfo = Install-PortableNode -RootPath $root
    $nodeManaged = [bool]$nodeInfo.InstalledNew
  }
  if ($NodeOnly) {
    $nodeOnlyAction = if ($nodeInfo.InstalledNew) { 'was installed' } else { 'was already present and was reused' }
    $message = "Official portable Node.js $nodeOnlyAction.`n`nPath: $($nodeInfo.Path)`nVersion: $($nodeInfo.Version)`n`nNo global PATH or system environment variables were changed."
    Write-Output $message
    Show-SetupMessage -Title 'Node.js installation complete' -Message $message -Icon Information
    return
  }

  $harnessManaged = $false
  if ($harnessState.State -eq 'Missing') {
    Write-Host '[Harness] Cloning the official DeepSeek Harness repository...'
    $cloneArguments = @('clone', '--depth', '1', '--single-branch')
    if (-not [string]::IsNullOrWhiteSpace($HarnessRef)) { $cloneArguments += @('--branch', $HarnessRef) }
    $cloneArguments += @('--', $officialRepositoryUrl, $harnessDir)
    Invoke-NativeCommand -FilePath $gitCommand.Source -ArgumentList $cloneArguments -Description 'Official Harness clone'
    $harnessManaged = $true
    $harnessState = Get-HarnessState -Path $harnessDir -GitCommand $gitCommand
    if ($harnessState.State -eq 'Invalid' -or $harnessState.State -eq 'Missing') {
      throw "The downloaded Harness failed verification: $($harnessState.Reason)"
    }
  } else {
    Write-Host "[Harness] Reusing existing installation: $harnessDir ($($harnessState.State))"
  }

  if ($DownloadOnly) {
    $message = "Official DeepSeek Harness is available.`n`nPath: $harnessDir`nCommit: $($harnessState.Commit)"
    Write-Output $message
    Show-SetupMessage -Title 'Download complete' -Message $message -Icon Information
    return
  }

  $auditWarning = $false
  if ($harnessState.State -ne 'Ready') {
    Write-Host '[Harness] Verifying the upstream package manager and lockfile...'
    $package = Get-Content -LiteralPath (Join-Path $harnessDir 'package.json') -Raw | ConvertFrom-Json
    $nodeEngine = [string]$package.engines.node
    if (-not [string]::Equals($nodeEngine, '^22.19.0 || >=24.0.0', [System.StringComparison]::Ordinal)) {
      throw "The official checkout changed its Node.js requirement. Review before installing: $nodeEngine"
    }
    $packageManager = [string]$package.packageManager
    $managerMatch = [regex]::Match($packageManager, '^pnpm@(?<version>\d+\.\d+\.\d+)$')
    if (-not $managerMatch.Success) { throw "The official checkout requested an unsupported package manager: $packageManager" }
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
    $hadCi = Test-Path -LiteralPath 'Env:\CI'
    $originalCi = [Environment]::GetEnvironmentVariable('CI', 'Process')
    $env:PATH = $nodeDir + ';' + $env:PATH
    $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
    $env:PNPM_DISABLE_SELF_UPDATE_CHECK = '1'
    $env:CI = 'true'
    $shimDir = $null
    Push-Location $harnessDir
    try {
      $runner = Get-PnpmRunner -SelectedNodePath $nodeInfo.Path -ExpectedVersion $pnpmVersion
      $shimDir = New-PnpmShim -Runner $runner -RootPath $root
      $env:PATH = $shimDir + ';' + $nodeDir + ';' + $originalPath
      Write-Host "[Harness] Installing locked dependencies with pnpm $pnpmVersion..."
      Invoke-PnpmCommand -Runner $runner -CommandArguments @('install', '--frozen-lockfile', '--reporter=append-only') -Description 'Dependency installation'
      Write-Host '[Harness] Building DeepSeek Harness...'
      Invoke-PnpmCommand -Runner $runner -CommandArguments @('run', 'build') -Description 'Harness build'
      if (-not $SkipAudit) {
        Write-Host '[Harness] Auditing the upstream dependency lockfile...'
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
      if ($hadCorepackPrompt) { $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = $originalCorepackPrompt } else { Remove-Item -LiteralPath 'Env:\COREPACK_ENABLE_DOWNLOAD_PROMPT' -ErrorAction SilentlyContinue }
      if ($hadPnpmSelfUpdate) { $env:PNPM_DISABLE_SELF_UPDATE_CHECK = $originalPnpmSelfUpdate } else { Remove-Item -LiteralPath 'Env:\PNPM_DISABLE_SELF_UPDATE_CHECK' -ErrorAction SilentlyContinue }
      if ($hadCi) { $env:CI = $originalCi } else { Remove-Item -LiteralPath 'Env:\CI' -ErrorAction SilentlyContinue }
      Remove-PnpmShim -ShimDir $shimDir -RootPath $root
    }
    $harnessState = Get-HarnessState -Path $harnessDir -GitCommand $gitCommand -AllowUnverified:$AcceptUnverifiedHarness
    if (-not $harnessState.Ready) { throw 'The Harness build completed without producing all required runtime files.' }
  } else {
    Write-Host '[Harness] Ready installation detected; dependency installation and build were skipped.'
  }

  Write-Host '[Desktop] Checking the Microsoft WebView2 Runtime...'
  & (Join-Path $PSScriptRoot 'Ensure-WebView2.ps1') -NonInteractive

  Write-Host '[Desktop] Writing launcher configuration and applying shortcut choices...'
  $installParameters = @{
    HarnessDir = $harnessDir
    DataDir = $dataDir
    NodePath = $nodeInfo.Path
    Language = $Language
  }
  if (-not [string]::IsNullOrWhiteSpace($ShortcutPath)) { $installParameters.ShortcutPath = $ShortcutPath }
  if ($CreateDesktopShortcut) { $installParameters.CreateDesktopShortcut = $true }
  if ($CreateStartMenuShortcut) { $installParameters.CreateStartMenuShortcut = $true }
  if ($RemoveDesktopShortcut) { $installParameters.RemoveDesktopShortcut = $true }
  if ($RemoveStartMenuShortcut) { $installParameters.RemoveStartMenuShortcut = $true }
  if ($harnessManaged) { $installParameters.HarnessManaged = $true }
  if ($nodeManaged) { $installParameters.NodeManaged = $true }
  if ($ForceLauncherConfig) { $installParameters.Force = $true }
  & (Join-Path $PSScriptRoot 'Install.ps1') @installParameters

  $successLines = @(
    'DSH Desktop configuration completed.', '',
    "Harness: $harnessDir ($($harnessState.State))",
    "Data:    $dataDir",
    "Node:    $($nodeInfo.Path) ($($nodeInfo.Version))",
    "Commit:  $($harnessState.Commit)"
  )
  if (-not $CreateDesktopShortcut -and -not $CreateStartMenuShortcut -and [string]::IsNullOrWhiteSpace($ShortcutPath)) {
    $successLines += 'Shortcut: none; open DSH-Desktop.exe from the application folder.'
  }
  if ($auditWarning) { $successLines += @('', 'Warning: the upstream dependency audit reported high-severity advisories. See the setup console output.') }
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
