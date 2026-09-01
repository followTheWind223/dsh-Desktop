#Requires -Version 5.1

[CmdletBinding()]
param(
  [ValidateSet('win-x64', 'win-arm64')][string]$Architecture = 'win-x64',
  [string]$OutputDirectory,
  [string]$DotNetPath,
  [switch]$SkipAudit,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsolutePath {
  param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$BasePath)
  if (-not [System.IO.Path]::IsPathRooted($Value)) { $Value = Join-Path $BasePath $Value }
  return [System.IO.Path]::GetFullPath($Value).TrimEnd('\')
}

function Assert-ChildPath {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Parent)
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
  $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
  if (-not $full.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing a path outside the build artifacts directory: $full"
  }
  return $full
}

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$Description
  )
  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE." }
}

function Invoke-OfficialDownload {
  param(
    [Parameter(Mandatory = $true)][uri]$Uri,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [Parameter(Mandatory = $true)][string[]]$AllowedHosts
  )
  if ($Uri.Scheme -ne 'https' -or $AllowedHosts -notcontains $Uri.Host) {
    throw "Refusing an unapproved download URL: $Uri"
  }
  $parent = Split-Path -Parent $OutFile
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parent -Force)
  }
  $temporary = $OutFile + '.download-' + [Guid]::NewGuid().ToString('N')
  try {
    $originalProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    [System.Net.ServicePointManager]::SecurityProtocol = $originalProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $Uri.AbsoluteUri -OutFile $temporary
    } finally {
      [System.Net.ServicePointManager]::SecurityProtocol = $originalProtocol
    }
    if (-not (Test-Path -LiteralPath $temporary -PathType Leaf) -or (Get-Item -LiteralPath $temporary).Length -eq 0) {
      throw "The download did not produce a file: $Uri"
    }
    Move-Item -LiteralPath $temporary -Destination $OutFile -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}

function Expand-VerifiedZip {
  param(
    [Parameter(Mandatory = $true)][string]$ArchivePath,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$ExpectedTopDirectory
  )
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try {
    if ($archive.Entries.Count -gt 15000) { throw 'The Node.js archive contains too many entries.' }
    [long]$expandedBytes = 0
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName.Replace('\', '/')
      $segments = @($entryName.Split('/') | Where-Object { $_.Length -gt 0 })
      if ([System.IO.Path]::IsPathRooted($entryName) -or $segments -contains '..' -or
          -not ($entryName -eq $ExpectedTopDirectory -or
            $entryName.StartsWith($ExpectedTopDirectory + '/', [System.StringComparison]::Ordinal))) {
        throw "The Node.js archive contains an unsafe path: $entryName"
      }
      $expandedBytes += $entry.Length
      if ($expandedBytes -gt 2GB) { throw 'The expanded Node.js archive is unexpectedly large.' }
    }
  } finally {
    $archive.Dispose()
  }
  [void](New-Item -ItemType Directory -Path $Destination -Force)
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination
}

function Assert-LifecycleScript {
  param(
    [Parameter(Mandatory = $true)][string]$HarnessRoot,
    [Parameter(Mandatory = $true)][string]$PackageName,
    [Parameter(Mandatory = $true)][hashtable]$ExpectedScripts
  )
  $packagePath = Join-Path $HarnessRoot ('node_modules\' + $PackageName.Replace('/', '\') + '\package.json')
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw "Lifecycle package is missing: $PackageName" }
  $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($entry in $ExpectedScripts.GetEnumerator()) {
    $actualProperty = $package.scripts.PSObject.Properties[$entry.Key]
    $actual = if ($null -eq $actualProperty) { $null } else { [string]$actualProperty.Value }
    if (-not [string]::Equals($actual, [string]$entry.Value, [System.StringComparison]::Ordinal)) {
      throw "The reviewed $PackageName $($entry.Key) script changed. Expected '$($entry.Value)', found '$actual'."
    }
  }
}

$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$artifactsRoot = Join-Path $repoRoot 'artifacts'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $artifactsRoot ('bundled-runtime-' + $Architecture)
}
$outputRoot = Get-AbsolutePath -Value $OutputDirectory -BasePath $repoRoot
$cacheRoot = Join-Path $artifactsRoot 'cache'
$workRoot = Join-Path $artifactsRoot ('work\bundled-' + $Architecture + '-' + [Guid]::NewGuid().ToString('N'))
$stagingRoot = Join-Path $artifactsRoot ('.bundled-runtime-' + $Architecture + '-' + [Guid]::NewGuid().ToString('N'))
[void](Assert-ChildPath -Path $workRoot -Parent $artifactsRoot)
[void](Assert-ChildPath -Path $stagingRoot -Parent $artifactsRoot)

if ((Test-Path -LiteralPath $outputRoot) -and -not $Force) {
  throw "Bundled runtime output already exists. Use -Force to replace it: $outputRoot"
}

$lockPath = Join-Path $repoRoot 'runtime\runtime.lock.json'
$packagePath = Join-Path $repoRoot 'runtime\package.json'
$packageLockPath = Join-Path $repoRoot 'runtime\package-lock.json'
foreach ($required in @($lockPath, $packagePath, $packageLockPath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required runtime lock input is missing: $required" }
}
$runtimeLock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$runtimeLock.schemaVersion -ne 1) { throw 'runtime.lock.json has an unsupported schema version.' }
$nodeDownloadProperty = $runtimeLock.node.downloads.PSObject.Properties[$Architecture]
if ($null -eq $nodeDownloadProperty) { throw "runtime.lock.json has no Node.js download for $Architecture." }
$nodeDownload = $nodeDownloadProperty.Value
$nodeVersion = [string]$runtimeLock.node.version
$nodeArchiveName = [string]$nodeDownload.file
$expectedNodeHash = ([string]$nodeDownload.sha256).ToLowerInvariant()
$expectedNodeFolder = [System.IO.Path]::GetFileNameWithoutExtension($nodeArchiveName)
if ($nodeArchiveName -ne ('node-' + $nodeVersion + '-' + $Architecture + '.zip') -or
    $expectedNodeHash -notmatch '^[0-9a-f]{64}$') {
  throw 'runtime.lock.json contains an invalid Node.js artifact definition.'
}

$nodeArchive = Join-Path $cacheRoot $nodeArchiveName
$desktopBuild = Join-Path $workRoot 'desktop'
$nodeExpanded = Join-Path $workRoot 'node-expanded'
$harnessRoot = Join-Path $stagingRoot 'runtime\harness'
$nodeRoot = Join-Path $stagingRoot 'runtime\node'
$webViewBootstrapper = Join-Path $stagingRoot 'redist\MicrosoftEdgeWebview2Setup.exe'
$backupOutput = $null

try {
  [void](New-Item -ItemType Directory -Path $workRoot -Force)
  [void](New-Item -ItemType Directory -Path $stagingRoot -Force)
  [void](New-Item -ItemType Directory -Path $cacheRoot -Force)

  $downloadNode = $true
  if (Test-Path -LiteralPath $nodeArchive -PathType Leaf) {
    $cachedHash = (Get-FileHash -LiteralPath $nodeArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($cachedHash -eq $expectedNodeHash) { $downloadNode = $false } else { Remove-Item -LiteralPath $nodeArchive -Force }
  }
  if ($downloadNode) {
    Write-Output "Downloading locked Node.js $nodeVersion for $Architecture..."
    Invoke-OfficialDownload -Uri ([uri]("https://nodejs.org/dist/{0}/{1}" -f $nodeVersion, $nodeArchiveName)) `
      -OutFile $nodeArchive -AllowedHosts @('nodejs.org')
  }
  $actualNodeHash = (Get-FileHash -LiteralPath $nodeArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualNodeHash -ne $expectedNodeHash) { throw 'The Node.js archive failed SHA-256 verification.' }

  Expand-VerifiedZip -ArchivePath $nodeArchive -Destination $nodeExpanded -ExpectedTopDirectory $expectedNodeFolder
  $expandedNodeRoot = Join-Path $nodeExpanded $expectedNodeFolder
  $nodeExecutable = Join-Path $expandedNodeRoot 'node.exe'
  $npmExecutable = Join-Path $expandedNodeRoot 'npm.cmd'
  foreach ($required in @($nodeExecutable, $npmExecutable)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "The Node.js archive is incomplete: $required" }
  }
  $reportedNodeVersion = (& $nodeExecutable --version | Select-Object -First 1).Trim()
  if ($reportedNodeVersion -ne $nodeVersion) { throw "Unexpected Node.js version: $reportedNodeVersion" }

  $lockCheck = @'
const fs = require('fs');
const lock = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const entry = lock.packages && lock.packages['node_modules/@deepseek-ai/dsh'];
if (!entry || entry.version !== process.argv[2] || entry.integrity !== process.argv[3]) process.exit(9);
'@
  & $nodeExecutable -e $lockCheck $packageLockPath ([string]$runtimeLock.harness.version) ([string]$runtimeLock.harness.integrity)
  if ($LASTEXITCODE -ne 0) { throw 'package-lock.json does not match the reviewed Harness package identity.' }

  [void](New-Item -ItemType Directory -Path $harnessRoot -Force)
  Copy-Item -LiteralPath $packagePath -Destination (Join-Path $harnessRoot 'package.json')
  Copy-Item -LiteralPath $packageLockPath -Destination (Join-Path $harnessRoot 'package-lock.json')

  $originalPath = $env:PATH
  $originalAudit = $env:npm_config_audit
  $originalFund = $env:npm_config_fund
  try {
    $env:PATH = $expandedNodeRoot + ';' + $originalPath
    $env:npm_config_audit = 'false'
    $env:npm_config_fund = 'false'
    Invoke-CheckedCommand -FilePath $npmExecutable `
      -ArgumentList @('ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--prefix', $harnessRoot) `
      -Description 'Locked Harness runtime installation'

    Assert-LifecycleScript -HarnessRoot $harnessRoot -PackageName '@deepseek-ai/dsh-subprocess-local' `
      -ExpectedScripts @{ postinstall = 'node scripts/ensure-spawn-helper.mjs' }
    Assert-LifecycleScript -HarnessRoot $harnessRoot -PackageName 'koffi' `
      -ExpectedScripts @{ install = 'node ./cnoke.cjs -P . -D src/koffi --prebuild --release' }
    Assert-LifecycleScript -HarnessRoot $harnessRoot -PackageName 'node-pty' `
      -ExpectedScripts @{
        install = 'node scripts/prebuild.js || node-gyp rebuild'
        postinstall = 'node scripts/post-install.js'
      }

    Invoke-CheckedCommand -FilePath $npmExecutable `
      -ArgumentList @('rebuild', '@deepseek-ai/dsh-subprocess-local', 'koffi', 'node-pty', '--foreground-scripts', '--no-audit', '--no-fund', '--prefix', $harnessRoot) `
      -Description 'Reviewed Harness native lifecycle scripts'
    if (-not $SkipAudit) {
      Invoke-CheckedCommand -FilePath $npmExecutable `
        -ArgumentList @('audit', '--omit=dev', '--audit-level=high', '--prefix', $harnessRoot) `
        -Description 'Harness production dependency audit'
    }
  } finally {
    $env:PATH = $originalPath
    $env:npm_config_audit = $originalAudit
    $env:npm_config_fund = $originalFund
  }

  $entryPath = Join-Path $harnessRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
  if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) { throw 'The packaged Harness entry point is missing.' }

  [void](New-Item -ItemType Directory -Path $nodeRoot -Force)
  foreach ($nodeFile in @('node.exe', 'LICENSE', 'README.md')) {
    $nodeSource = Join-Path $expandedNodeRoot $nodeFile
    if (-not (Test-Path -LiteralPath $nodeSource -PathType Leaf)) {
      throw "The Node.js archive is missing a required runtime file: $nodeFile"
    }
    Copy-Item -LiteralPath $nodeSource -Destination (Join-Path $nodeRoot $nodeFile) -Force
  }
  & (Join-Path $repoRoot 'Build-Exe.ps1') -OutputDirectory $desktopBuild -DotNetPath $DotNetPath

  foreach ($relative in @(
      'DSH-Desktop.exe', 'DSH-Desktop.exe.config',
      'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll',
      'runtimes\win-x86\native\WebView2Loader.dll',
      'runtimes\win-x64\native\WebView2Loader.dll',
      'runtimes\win-arm64\native\WebView2Loader.dll'
    )) {
    $source = Join-Path $desktopBuild $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Desktop build output is missing: $relative" }
    $destination = Join-Path $stagingRoot $relative
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }
  foreach ($relative in @(
      'LICENSE', 'PRIVACY.md', 'README.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'VERSION',
      'assets\deepseek-harness.ico', 'assets\deepseek-harness.svg'
    )) {
    $source = Join-Path $repoRoot $relative
    $destination = Join-Path $stagingRoot $relative
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }

  Write-Output 'Downloading the Microsoft WebView2 Evergreen Bootstrapper for the installer payload...'
  Invoke-OfficialDownload -Uri ([uri]'https://go.microsoft.com/fwlink/p/?LinkId=2124703') `
    -OutFile $webViewBootstrapper -AllowedHosts @('go.microsoft.com')
  $webViewSignature = Get-AuthenticodeSignature -LiteralPath $webViewBootstrapper
  if ($webViewSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
      $null -eq $webViewSignature.SignerCertificate -or
      $webViewSignature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(,|$)') {
    throw 'The WebView2 Bootstrapper does not have a valid Microsoft Authenticode signature.'
  }

  $manifest = [ordered]@{
    SchemaVersion = 1
    DshDesktopVersion = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
    Architecture = $Architecture
    Harness = [ordered]@{
      Package = [string]$runtimeLock.harness.package
      Version = [string]$runtimeLock.harness.version
      Integrity = [string]$runtimeLock.harness.integrity
      SourceRepository = [string]$runtimeLock.harness.sourceRepository
      SourceCommit = [string]$runtimeLock.harness.sourceCommit
      PackageLockSHA256 = (Get-FileHash -LiteralPath $packageLockPath -Algorithm SHA256).Hash.ToLowerInvariant()
      EntrySHA256 = (Get-FileHash -LiteralPath $entryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Node = [ordered]@{
      Version = $nodeVersion
      Archive = $nodeArchiveName
      ArchiveSHA256 = $actualNodeHash
      ExecutableSHA256 = (Get-FileHash -LiteralPath (Join-Path $nodeRoot 'node.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    WebView2Bootstrapper = [ordered]@{
      SHA256 = (Get-FileHash -LiteralPath $webViewBootstrapper -Algorithm SHA256).Hash.ToLowerInvariant()
      Publisher = $webViewSignature.SignerCertificate.Subject
    }
  }
  $manifestPath = Join-Path $stagingRoot 'runtime-manifest.json'
  [System.IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    (New-Object System.Text.UTF8Encoding($false))
  )

  & (Join-Path $repoRoot 'Test-BundledRuntime.ps1') -BundleDirectory $stagingRoot

  if (Test-Path -LiteralPath $outputRoot) {
    $backupOutput = $outputRoot + '.backup-' + [Guid]::NewGuid().ToString('N')
    Move-Item -LiteralPath $outputRoot -Destination $backupOutput
  }
  Move-Item -LiteralPath $stagingRoot -Destination $outputRoot
  if (-not [string]::IsNullOrWhiteSpace($backupOutput) -and (Test-Path -LiteralPath $backupOutput)) {
    Remove-Item -LiteralPath $backupOutput -Recurse -Force
  }
  Write-Output "Bundled runtime: $outputRoot"
} catch {
  if (-not [string]::IsNullOrWhiteSpace($backupOutput) -and
      (Test-Path -LiteralPath $backupOutput) -and -not (Test-Path -LiteralPath $outputRoot)) {
    Move-Item -LiteralPath $backupOutput -Destination $outputRoot
  }
  throw
} finally {
  foreach ($temporary in @($workRoot, $stagingRoot)) {
    if ((Test-Path -LiteralPath $temporary -PathType Container) -and
        ([System.IO.Path]::GetFullPath($temporary).StartsWith($artifactsRoot + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
      Remove-Item -LiteralPath $temporary -Recurse -Force
    }
  }
}
