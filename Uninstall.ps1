#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$ShortcutPath,
  [switch]$RemoveConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
  $ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'
}
if (-not [System.IO.Path]::IsPathRooted($ShortcutPath)) {
  throw 'ShortcutPath must be an absolute path.'
}
$ShortcutPath = [System.IO.Path]::GetFullPath($ShortcutPath)
if (-not [string]::Equals([System.IO.Path]::GetExtension($ShortcutPath), '.lnk', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'ShortcutPath must end in .lnk.'
}

$launcherScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'DeepSeek-Harness-Desktop.ps1'))
if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($ShortcutPath)
  $expectedArgument = '-File "' + $launcherScript + '"'
  if ($shortcut.Arguments.IndexOf($expectedArgument, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "Refusing to remove a shortcut not owned by this launcher: $ShortcutPath"
  }
  Remove-Item -LiteralPath $ShortcutPath -Force
  Write-Output ("Removed shortcut: {0}" -f $ShortcutPath)
} else {
  Write-Output ("Shortcut was not present: {0}" -f $ShortcutPath)
}

if ($RemoveConfig) {
  $configPath = Join-Path $PSScriptRoot 'launcher.config.json'
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Remove-Item -LiteralPath $configPath -Force
    Write-Output ("Removed configuration: {0}" -f $configPath)
  }
}

Write-Output 'Harness source code, data, Node.js, Edge, and environment variables were not changed.'
