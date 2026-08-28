#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$LauncherPath,
  [string]$UninstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredFiles = @(
  '.gitignore',
  'Build-Exe.ps1',
  'Build-Release.ps1',
  'CHANGELOG.md',
  'CONTRIBUTING.md',
  'DeepSeek-Harness-Desktop.ps1',
  'DSH-Desktop.exe',
  'Install.ps1',
  'LICENSE',
  'README.md',
  'SECURITY.md',
  'Setup.ps1',
  'THIRD_PARTY_NOTICES.md',
  'Uninstall-DSH-Desktop.exe',
  'Uninstall.ps1',
  'VERSION',
  'assets\deepseek-harness.ico',
  'assets\deepseek-harness.svg',
  'launcher.config.example.json',
  'src\DSH-Desktop\Program.cs',
  'src\DSH-Desktop\UninstallProgram.cs',
  '.github\workflows\release.yml'
)

foreach ($relativePath in $requiredFiles) {
  $path = Join-Path $PSScriptRoot $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required release file is missing: $relativePath"
  }
}

$localConfig = Join-Path $PSScriptRoot 'launcher.config.json'
if (Test-Path -LiteralPath $localConfig) {
  throw 'launcher.config.json contains local paths and must not be included in a release.'
}

foreach ($script in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $script.FullName,
    [ref]$tokens,
    [ref]$errors
  )
  if ($errors.Count -gt 0) {
    $messages = ($errors | ForEach-Object { $_.Message }) -join [Environment]::NewLine
    throw "PowerShell parse failure in $($script.Name):`n$messages"
  }
}

$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
$iconBytes = [System.IO.File]::ReadAllBytes($iconPath)
if ($iconBytes.Length -lt 6) { throw 'The Windows icon is truncated.' }
if ([BitConverter]::ToUInt16($iconBytes, 0) -ne 0) { throw 'The Windows icon header is invalid.' }
if ([BitConverter]::ToUInt16($iconBytes, 2) -ne 1) { throw 'The Windows icon type is invalid.' }
$imageCount = [BitConverter]::ToUInt16($iconBytes, 4)
if ($imageCount -lt 1) { throw 'The Windows icon has no embedded images.' }

function Assert-WindowsExecutable {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$DisplayName,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion
  )

  $exePath = if ([System.IO.Path]::IsPathRooted($Path)) {
    [System.IO.Path]::GetFullPath($Path)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
  }
  if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Required executable is missing: $DisplayName"
  }
  $exeBytes = [System.IO.File]::ReadAllBytes($exePath)
  if ($exeBytes.Length -lt 128) { throw "$DisplayName is truncated." }
  if ($exeBytes[0] -ne 0x4D -or $exeBytes[1] -ne 0x5A) { throw "$DisplayName has an invalid DOS header." }
  $peOffset = [BitConverter]::ToInt32($exeBytes, 0x3C)
  if ($peOffset -lt 0x40 -or $peOffset + 4 -gt $exeBytes.Length) { throw "$DisplayName has an invalid PE offset." }
  if ([BitConverter]::ToUInt32($exeBytes, $peOffset) -ne 0x00004550) { throw "$DisplayName has an invalid PE signature." }
  $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
  if (-not [string]::Equals($versionInfo.FileVersion, $ExpectedVersion, [System.StringComparison]::Ordinal)) {
    throw "Unexpected $DisplayName version: $($versionInfo.FileVersion)"
  }
  return $versionInfo.FileVersion
}

$projectVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($projectVersion -notmatch '^\d+\.\d+\.\d+$') {
  throw 'VERSION must contain a semantic version such as 0.3.0.'
}
$expectedFileVersion = $projectVersion + '.0'
if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
  $LauncherPath = 'DSH-Desktop.exe'
}
if ([string]::IsNullOrWhiteSpace($UninstallerPath)) {
  $UninstallerPath = 'Uninstall-DSH-Desktop.exe'
}

$launcherVersion = Assert-WindowsExecutable -Path $LauncherPath -DisplayName 'DSH-Desktop.exe' -ExpectedVersion $expectedFileVersion
$uninstallerVersion = Assert-WindowsExecutable -Path $UninstallerPath -DisplayName 'Uninstall-DSH-Desktop.exe' -ExpectedVersion $expectedFileVersion

Write-Output 'Release validation passed.'
Write-Output ("PowerShell scripts: {0}" -f @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File).Count)
Write-Output ("Icon images:       {0}" -f $imageCount)
Write-Output ("Entry executable:  {0}" -f $launcherVersion)
Write-Output ("Uninstaller:       {0}" -f $uninstallerVersion)
