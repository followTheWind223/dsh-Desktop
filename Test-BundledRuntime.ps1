#Requires -Version 5.1

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$BundleDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($BundleDirectory)) {
  $BundleDirectory = Join-Path $PSScriptRoot $BundleDirectory
}
$bundleRoot = [System.IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) { throw "BundleDirectory does not exist: $bundleRoot" }

$requiredFiles = @(
  'DSH-Desktop.exe', 'DSH-Desktop.exe.config',
  'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll',
  'runtimes\win-x86\native\WebView2Loader.dll',
  'runtimes\win-x64\native\WebView2Loader.dll',
  'runtimes\win-arm64\native\WebView2Loader.dll',
  'runtime\node\node.exe',
  'runtime\harness\package.json', 'runtime\harness\package-lock.json',
  'runtime\harness\node_modules\@deepseek-ai\dsh\lib\bin.js',
  'redist\MicrosoftEdgeWebview2Setup.exe',
  'runtime-manifest.json', 'LICENSE', 'PRIVACY.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'VERSION'
)
foreach ($relative in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $bundleRoot $relative) -PathType Leaf)) {
    throw "Bundled runtime file is missing: $relative"
  }
}
foreach ($forbidden in @('.git', '.env', '.env.local', 'launcher.config.json', 'data')) {
  if (Test-Path -LiteralPath (Join-Path $bundleRoot $forbidden)) { throw "Bundled runtime contains forbidden local state: $forbidden" }
}

$manifestPath = Join-Path $bundleRoot 'runtime-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$manifest.SchemaVersion -ne 1) { throw 'The bundled runtime manifest schema is invalid.' }
$version = (Get-Content -LiteralPath (Join-Path $bundleRoot 'VERSION') -Raw).Trim()
if ([string]$manifest.DshDesktopVersion -ne $version) { throw 'The bundled runtime manifest has the wrong DSH Desktop version.' }
if ([string]$manifest.Architecture -notin @('win-x64', 'win-arm64')) { throw 'The bundled runtime manifest architecture is invalid.' }

$nodePath = Join-Path $bundleRoot 'runtime\node\node.exe'
$nodeVersionOutput = @(& $nodePath --version)
$nodeExitCode = $LASTEXITCODE
$nodeVersion = ($nodeVersionOutput | Select-Object -First 1).Trim()
$expectedNodeVersion = [string]$manifest.Node.Version
if ($nodeExitCode -ne 0 -or
    -not [string]::Equals($nodeVersion, $expectedNodeVersion, [System.StringComparison]::Ordinal)) {
  throw "The bundled Node.js runtime has an unexpected version: $nodeVersion"
}
$nodeHash = (Get-FileHash -LiteralPath $nodePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($nodeHash -ne [string]$manifest.Node.ExecutableSHA256) { throw 'The bundled Node.js executable hash is invalid.' }

$harnessRoot = Join-Path $bundleRoot 'runtime\harness'
$entryPath = Join-Path $harnessRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$harnessPackagePath = Join-Path $harnessRoot 'node_modules\@deepseek-ai\dsh\package.json'
$harnessPackage = Get-Content -LiteralPath $harnessPackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$harnessPackage.name -ne [string]$manifest.Harness.Package -or
    [string]$harnessPackage.version -ne [string]$manifest.Harness.Version) {
  throw 'The bundled Harness package identity is invalid.'
}
$entryHash = (Get-FileHash -LiteralPath $entryPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($entryHash -ne [string]$manifest.Harness.EntrySHA256) { throw 'The bundled Harness entry hash is invalid.' }
$packageLockHash = (Get-FileHash -LiteralPath (Join-Path $harnessRoot 'package-lock.json') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packageLockHash -ne [string]$manifest.Harness.PackageLockSHA256) { throw 'The bundled package-lock.json hash is invalid.' }

$moduleCheck = @'
const { createRequire } = require('module');
const path = require('path');
const root = process.argv[1];
const requireFromRuntime = createRequire(path.join(root, 'package.json'));
for (const name of ['node-pty', 'koffi']) requireFromRuntime.resolve(name);
'@
& $nodePath -e $moduleCheck $harnessRoot
if ($LASTEXITCODE -ne 0) { throw 'A required bundled Harness module cannot be resolved.' }

$helpOutput = @(& $nodePath $entryPath --help 2>&1)
if ($LASTEXITCODE -ne 0 -or ($helpOutput -join [Environment]::NewLine) -notmatch '(?i)usage|deepseek|dsh') {
  throw "The bundled Harness CLI smoke test failed.`n$($helpOutput -join [Environment]::NewLine)"
}

$webViewPath = Join-Path $bundleRoot 'redist\MicrosoftEdgeWebview2Setup.exe'
$webViewSignature = Get-AuthenticodeSignature -LiteralPath $webViewPath
if ($webViewSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
    $null -eq $webViewSignature.SignerCertificate -or
    $webViewSignature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(,|$)') {
  throw 'The bundled WebView2 Bootstrapper signature is invalid.'
}

$desktopVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $bundleRoot 'DSH-Desktop.exe')).FileVersion
if ($desktopVersion -ne ($version + '.0')) { throw "Unexpected DSH-Desktop.exe version: $desktopVersion" }

Write-Output 'Bundled runtime validation passed.'
Write-Output "Bundle:        $bundleRoot"
Write-Output "Version:       $version"
Write-Output "Architecture:  $($manifest.Architecture)"
Write-Output "Harness:       $($manifest.Harness.Package)@$($manifest.Harness.Version)"
Write-Output "Node.js:       $nodeVersion"
