#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredFiles = @(
  '.gitignore',
  'Build-Exe.ps1',
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
  'Uninstall.ps1',
  'VERSION',
  'assets\deepseek-harness.ico',
  'assets\deepseek-harness.svg',
  'launcher.config.example.json',
  'src\DSH-Desktop\Program.cs'
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

$exePath = Join-Path $PSScriptRoot 'DSH-Desktop.exe'
$exeBytes = [System.IO.File]::ReadAllBytes($exePath)
if ($exeBytes.Length -lt 128) { throw 'DSH-Desktop.exe is truncated.' }
if ($exeBytes[0] -ne 0x4D -or $exeBytes[1] -ne 0x5A) { throw 'DSH-Desktop.exe has an invalid DOS header.' }
$peOffset = [BitConverter]::ToInt32($exeBytes, 0x3C)
if ($peOffset -lt 0x40 -or $peOffset + 4 -gt $exeBytes.Length) { throw 'DSH-Desktop.exe has an invalid PE offset.' }
if ([BitConverter]::ToUInt32($exeBytes, $peOffset) -ne 0x00004550) { throw 'DSH-Desktop.exe has an invalid PE signature.' }
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
if (-not [string]::Equals($versionInfo.FileVersion, '0.2.0.0', [System.StringComparison]::Ordinal)) {
  throw "Unexpected DSH-Desktop.exe version: $($versionInfo.FileVersion)"
}

Write-Output 'Release validation passed.'
Write-Output ("PowerShell scripts: {0}" -f @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File).Count)
Write-Output ("Icon images:       {0}" -f $imageCount)
Write-Output ("Entry executable:  {0}" -f $versionInfo.FileVersion)
