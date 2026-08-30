#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$PackageRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot = $PSScriptRoot }
if (-not [System.IO.Path]::IsPathRooted($PackageRoot)) { $PackageRoot = Join-Path $PSScriptRoot $PackageRoot }
$PackageRoot = [System.IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $PackageRoot -PathType Container)) { throw "PackageRoot does not exist: $PackageRoot" }

$requiredFiles = @(
  'DSH-Desktop.exe', 'DSH-Setup.exe', 'Uninstall-DSH-Desktop.exe', 'DSH-Desktop.exe.config',
  'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll',
  'runtimes\win-x86\native\WebView2Loader.dll',
  'runtimes\win-x64\native\WebView2Loader.dll',
  'runtimes\win-arm64\native\WebView2Loader.dll',
  'Install.ps1', 'Setup.ps1', 'Setup-GUI.ps1', 'Ensure-WebView2.ps1', 'Uninstall.ps1',
  'CHANGELOG.md', 'CODE_SIGNING_POLICY.md', 'LICENSE', 'PRIVACY.md', 'README.md',
  'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'VERSION',
  'assets\deepseek-harness.ico', 'assets\deepseek-harness.svg'
)
foreach ($relative in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $relative) -PathType Leaf)) { throw "Required release file is missing: $relative" }
}
if (Test-Path -LiteralPath (Join-Path $PackageRoot 'launcher.config.json')) {
  throw 'launcher.config.json contains local paths and must not be included in a release.'
}

$desktopConfig = Get-Content -LiteralPath (Join-Path $PackageRoot 'DSH-Desktop.exe.config') -Raw
if ($desktopConfig -notmatch '<add\s+key="DpiAwareness"\s+value="PerMonitorV2"\s*/>') {
  throw 'DSH-Desktop.exe.config does not enable PerMonitorV2 DPI awareness.'
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktopProject = Join-Path $projectRoot 'src\DSH-Desktop\DSH-Desktop.csproj'
$desktopManifest = Join-Path $projectRoot 'src\DSH-Desktop\app.manifest'
if ((Test-Path -LiteralPath $desktopProject -PathType Leaf) -and
    (Get-Content -LiteralPath $desktopProject -Raw) -notmatch '<ApplicationManifest>app\.manifest</ApplicationManifest>') {
  throw 'DSH-Desktop.csproj does not embed the application manifest.'
}
if ((Test-Path -LiteralPath $desktopManifest -PathType Leaf) -and
    (Get-Content -LiteralPath $desktopManifest -Raw) -notmatch '\{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a\}') {
  throw 'The application manifest does not declare Windows 10 compatibility.'
}

foreach ($script in (Get-ChildItem -LiteralPath $PackageRoot -Filter '*.ps1' -File)) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) {
    throw "PowerShell parse failure in $($script.Name):`n$(($errors | ForEach-Object Message) -join [Environment]::NewLine)"
  }
}

$uninstallScriptText = Get-Content -LiteralPath (Join-Path $PackageRoot 'Uninstall.ps1') -Raw -Encoding UTF8
foreach ($requiredPattern in @(
    '\[switch\]\$RemoveHarness',
    '\[switch\]\$ConfirmExistingHarnessRemoval',
    '@deepseek-ai/dsh-root',
    'ReparsePoint',
    'Join-Path \$LauncherRoot ''\.git'''
  )) {
  if ($uninstallScriptText -notmatch $requiredPattern) {
    throw "Uninstall.ps1 is missing a required Harness-removal safety check: $requiredPattern"
  }
}

$version = (Get-Content -LiteralPath (Join-Path $PackageRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION is invalid.' }
$expectedFileVersion = $version + '.0'

function Assert-PortableExecutable {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [string]$ExpectedVersion)
  $path = Join-Path $PackageRoot $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -lt 128 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw "$RelativePath has an invalid PE header." }
  $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
  if ($peOffset -lt 0x40 -or $peOffset + 4 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550) {
    throw "$RelativePath has an invalid PE signature."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $actual = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileVersion
    if (-not [string]::Equals($actual, $ExpectedVersion, [System.StringComparison]::Ordinal)) {
      throw "Unexpected $RelativePath version: $actual"
    }
  }
}

foreach ($relative in @('DSH-Desktop.exe', 'DSH-Setup.exe', 'Uninstall-DSH-Desktop.exe')) {
  Assert-PortableExecutable -RelativePath $relative -ExpectedVersion $expectedFileVersion
}
$uninstallerMetadata = [System.Text.Encoding]::Unicode.GetString(
  [System.IO.File]::ReadAllBytes((Join-Path $PackageRoot 'Uninstall-DSH-Desktop.exe'))
)
foreach ($requiredText in @('RemoveHarness', 'ConfirmExistingHarnessRemoval')) {
  if ($uninstallerMetadata.IndexOf($requiredText, [System.StringComparison]::Ordinal) -lt 0) {
    throw "Uninstall-DSH-Desktop.exe is missing expected v0.4.2 behavior: $requiredText"
  }
}
foreach ($relative in @(
    'runtimes\win-x86\native\WebView2Loader.dll',
    'runtimes\win-x64\native\WebView2Loader.dll',
    'runtimes\win-arm64\native\WebView2Loader.dll'
  )) { Assert-PortableExecutable -RelativePath $relative }

$setupAssemblyBytes = [System.IO.File]::ReadAllBytes((Join-Path $PackageRoot 'DSH-Setup.exe'))
$setupAssembly = [System.Reflection.Assembly]::ReflectionOnlyLoad($setupAssemblyBytes)
if ($setupAssembly.GetManifestResourceNames() -notcontains 'DSHDesktop.Payload.zip') {
  throw 'DSH-Setup.exe does not contain the embedded installer payload.'
}

$iconBytes = [System.IO.File]::ReadAllBytes((Join-Path $PackageRoot 'assets\deepseek-harness.ico'))
if ($iconBytes.Length -lt 6 -or [BitConverter]::ToUInt16($iconBytes, 0) -ne 0 -or [BitConverter]::ToUInt16($iconBytes, 2) -ne 1) {
  throw 'The Windows icon is invalid.'
}
$imageCount = [BitConverter]::ToUInt16($iconBytes, 4)
if ($imageCount -lt 1) { throw 'The Windows icon has no embedded images.' }

$checksumFile = Join-Path $PackageRoot 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $checksumFile -PathType Leaf) {
  foreach ($line in (Get-Content -LiteralPath $checksumFile)) {
    if ($line -notmatch '^(?<hash>[0-9a-f]{64}) \*(?<path>.+)$') { throw "Invalid checksum line: $line" }
    $target = Join-Path $PackageRoot $Matches.path.Replace('/', '\')
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Matches.hash) { throw "Checksum mismatch: $($Matches.path)" }
  }
}

Write-Output 'Release validation passed.'
Write-Output "Package root:      $PackageRoot"
Write-Output "Version:           $version"
Write-Output "PowerShell scripts: $(@(Get-ChildItem -LiteralPath $PackageRoot -Filter '*.ps1' -File).Count)"
Write-Output "Icon images:       $imageCount"
