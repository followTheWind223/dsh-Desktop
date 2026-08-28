#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$HarnessDir = 'D:\deepseek-harness',
  [string]$DataDir = 'D:\deepseek-harness-data',
  [string]$NodePath,
  [string]$EdgePath,
  [string]$ShortcutPath,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsolutePath {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ([string]::IsNullOrWhiteSpace($Value) -or -not [System.IO.Path]::IsPathRooted($Value)) {
    throw "$Name must be an absolute path."
  }
  return [System.IO.Path]::GetFullPath($Value)
}

function Get-CompatibleNodeVersion {
  param([Parameter(Mandatory = $true)][string]$Executable)

  if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Node.js was not found: $Executable"
  }

  $versionText = (& $Executable --version 2>&1 | Select-Object -First 1)
  $match = [regex]::Match([string]$versionText, '^v(?<major>\d+)\.(?<minor>\d+)\.')
  if (-not $match.Success) {
    throw "Unable to read the Node.js version from: $Executable"
  }

  $major = [int]$match.Groups['major'].Value
  $minor = [int]$match.Groups['minor'].Value
  if (-not (($major -eq 22 -and $minor -ge 19) -or $major -ge 24)) {
    throw "DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0. Found: $versionText"
  }
  return [string]$versionText
}

function Find-EdgePath {
  $candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  throw 'Microsoft Edge was not found. Pass -EdgePath with an absolute path to msedge.exe.'
}

$launcherScript = Join-Path $PSScriptRoot 'DeepSeek-Harness-Desktop.ps1'
$entryExecutable = Join-Path $PSScriptRoot 'DSH-Desktop.exe'
$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
$configPath = Join-Path $PSScriptRoot 'launcher.config.json'
foreach ($projectFile in @($launcherScript, $entryExecutable, $iconPath)) {
  if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "The launcher package is incomplete: $projectFile"
  }
}

$HarnessDir = Get-AbsolutePath -Value $HarnessDir -Name 'HarnessDir'
$DataDir = Get-AbsolutePath -Value $DataDir -Name 'DataDir'
if (-not (Test-Path -LiteralPath $HarnessDir -PathType Container)) {
  throw "HarnessDir does not exist: $HarnessDir"
}

$requiredHarnessFiles = @(
  (Join-Path $HarnessDir 'apps\cli\src\bin.ts'),
  (Join-Path $HarnessDir 'apps\web\dist\index.html'),
  (Join-Path $HarnessDir 'node_modules\tsx')
)
foreach ($requiredFile in $requiredHarnessFiles) {
  if (-not (Test-Path -LiteralPath $requiredFile)) {
    throw "Harness is not installed and built. Missing: $requiredFile"
  }
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
  $nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $nodeCommand) {
    throw 'Node.js was not found. Pass -NodePath with an absolute path to a compatible node.exe.'
  }
  $NodePath = $nodeCommand.Source
}
$NodePath = Get-AbsolutePath -Value $NodePath -Name 'NodePath'
if (-not [string]::Equals((Split-Path -Leaf $NodePath), 'node.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "NodePath must point to node.exe: $NodePath"
}
$nodeVersion = Get-CompatibleNodeVersion -Executable $NodePath

if ([string]::IsNullOrWhiteSpace($EdgePath)) { $EdgePath = Find-EdgePath }
$EdgePath = Get-AbsolutePath -Value $EdgePath -Name 'EdgePath'
if (-not (Test-Path -LiteralPath $EdgePath -PathType Leaf)) {
  throw "Microsoft Edge was not found: $EdgePath"
}
if (-not [string]::Equals((Split-Path -Leaf $EdgePath), 'msedge.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "EdgePath must point to msedge.exe: $EdgePath"
}

if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
  $ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'
}
$ShortcutPath = Get-AbsolutePath -Value $ShortcutPath -Name 'ShortcutPath'
if (-not [string]::Equals([System.IO.Path]::GetExtension($ShortcutPath), '.lnk', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'ShortcutPath must end in .lnk.'
}

if ((Test-Path -LiteralPath $configPath) -and -not $Force) {
  throw "Configuration already exists. Re-run with -Force to replace it: $configPath"
}
if ((Test-Path -LiteralPath $ShortcutPath) -and -not $Force) {
  throw "Shortcut already exists. Re-run with -Force to replace it: $ShortcutPath"
}

if (-not (Test-Path -LiteralPath $DataDir -PathType Container)) {
  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}
$shortcutParent = Split-Path -Parent $ShortcutPath
if (-not (Test-Path -LiteralPath $shortcutParent -PathType Container)) {
  throw "The shortcut parent directory does not exist: $shortcutParent"
}

$config = [ordered]@{
  HarnessDir = $HarnessDir
  DataDir = $DataDir
  NodePath = $NodePath
  EdgePath = $EdgePath
}
$configJson = ($config | ConvertTo-Json -Depth 3) + [Environment]::NewLine
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $configJson, $utf8NoBom)

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $entryExecutable
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $HarnessDir
$shortcut.IconLocation = $entryExecutable + ',0'
$shortcut.Description = 'Unofficial desktop launcher for DeepSeek Harness'
$shortcut.WindowStyle = 7
$shortcut.Save()

Write-Output 'DeepSeek Harness desktop launcher configured.'
Write-Output ("Launcher: {0}" -f $PSScriptRoot)
Write-Output ("Entry EXE: {0}" -f $entryExecutable)
Write-Output ("Shortcut: {0}" -f $ShortcutPath)
Write-Output ("Harness:  {0}" -f $HarnessDir)
Write-Output ("Data:     {0}" -f $DataDir)
Write-Output ("Node.js:  {0} ({1})" -f $NodePath, $nodeVersion)
