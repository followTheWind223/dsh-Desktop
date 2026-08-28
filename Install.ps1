#Requires -Version 5.1

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$HarnessDir,
  [Parameter(Mandatory = $true)][string]$DataDir,
  [Parameter(Mandatory = $true)][string]$NodePath,
  [ValidateSet('auto', 'zh-CN', 'en-US')][string]$Language = 'auto',
  [string]$ShortcutPath,
  [switch]$CreateDesktopShortcut,
  [switch]$CreateStartMenuShortcut,
  [switch]$RemoveDesktopShortcut,
  [switch]$RemoveStartMenuShortcut,
  [switch]$HarnessManaged,
  [switch]$DataManaged,
  [switch]$NodeManaged,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsoluteLocalPath {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ([string]::IsNullOrWhiteSpace($Value) -or -not [System.IO.Path]::IsPathRooted($Value)) {
    throw "$Name must be an absolute path."
  }
  $fullPath = [System.IO.Path]::GetFullPath($Value)
  if ($fullPath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
    throw "$Name cannot be a network path."
  }
  return $fullPath.TrimEnd('\')
}

function Get-CompatibleNodeVersion {
  param([Parameter(Mandatory = $true)][string]$Executable)

  if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Node.js was not found: $Executable"
  }
  $versionLines = @(& $Executable --version 2>$null)
  $exitCode = $LASTEXITCODE
  $versionText = $versionLines | Select-Object -First 1
  $match = [regex]::Match([string]$versionText, '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$')
  if ($exitCode -ne 0 -or -not $match.Success) {
    throw "Unable to read the Node.js version from: $Executable"
  }
  $major = [int]$match.Groups['major'].Value
  $minor = [int]$match.Groups['minor'].Value
  if (-not (($major -eq 22 -and $minor -ge 19) -or $major -ge 24)) {
    throw "DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0. Found: $versionText"
  }
  return [string]$versionText
}

function Set-LauncherShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [switch]$Replace
  )

  $fullPath = Get-AbsoluteLocalPath -Value $Path -Name 'ShortcutPath'
  if (-not [string]::Equals([System.IO.Path]::GetExtension($fullPath), '.lnk', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "ShortcutPath must end in .lnk: $fullPath"
  }
  $parent = Split-Path -Parent $fullPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $shell = New-Object -ComObject WScript.Shell
  try {
    if ((Test-Path -LiteralPath $fullPath -PathType Leaf) -and -not $Replace) {
      $existing = $shell.CreateShortcut($fullPath)
      if (-not [string]::Equals(
          [System.IO.Path]::GetFullPath($existing.TargetPath),
          [System.IO.Path]::GetFullPath($Target),
          [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace an unrelated shortcut: $fullPath"
      }
    }

    $shortcut = $shell.CreateShortcut($fullPath)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = $Target + ',0'
    $shortcut.Description = 'Unofficial desktop app for DeepSeek Harness'
    $shortcut.WindowStyle = 1
    $shortcut.Save()
  } finally {
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
  }
  return $fullPath
}

function Remove-LauncherShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedTarget
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $shell = New-Object -ComObject WScript.Shell
  try {
    $shortcut = $shell.CreateShortcut($Path)
    if (-not [string]::Equals(
        [System.IO.Path]::GetFullPath($shortcut.TargetPath),
        [System.IO.Path]::GetFullPath($ExpectedTarget),
        [System.StringComparison]::OrdinalIgnoreCase)) {
      Write-Warning "An unrelated shortcut was left unchanged: $Path"
      return
    }
  } finally {
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
  }
  Remove-Item -LiteralPath $Path -Force
}

$entryExecutable = Join-Path $PSScriptRoot 'DSH-Desktop.exe'
$setupExecutable = Join-Path $PSScriptRoot 'DSH-Setup.exe'
$uninstallExecutable = Join-Path $PSScriptRoot 'Uninstall-DSH-Desktop.exe'
$webViewCore = Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.Core.dll'
$webViewWinForms = Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.WinForms.dll'
$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
$configPath = Join-Path $PSScriptRoot 'launcher.config.json'
foreach ($projectFile in @(
    $entryExecutable,
    $setupExecutable,
    $uninstallExecutable,
    $webViewCore,
    $webViewWinForms,
    $iconPath
  )) {
  if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "The DSH Desktop package is incomplete: $projectFile"
  }
}

$HarnessDir = Get-AbsoluteLocalPath -Value $HarnessDir -Name 'HarnessDir'
$DataDir = Get-AbsoluteLocalPath -Value $DataDir -Name 'DataDir'
$NodePath = Get-AbsoluteLocalPath -Value $NodePath -Name 'NodePath'
if (-not (Test-Path -LiteralPath $HarnessDir -PathType Container)) {
  throw "HarnessDir does not exist: $HarnessDir"
}
if (-not [string]::Equals((Split-Path -Leaf $NodePath), 'node.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "NodePath must point to node.exe: $NodePath"
}

foreach ($requiredHarnessPath in @(
    (Join-Path $HarnessDir 'apps\cli\src\bin.ts'),
    (Join-Path $HarnessDir 'apps\web\dist\index.html'),
    (Join-Path $HarnessDir 'node_modules\tsx\package.json')
  )) {
  if (-not (Test-Path -LiteralPath $requiredHarnessPath)) {
    throw "Harness is not installed and built. Missing: $requiredHarnessPath"
  }
}
$nodeVersion = Get-CompatibleNodeVersion -Executable $NodePath

$dataWasCreated = -not (Test-Path -LiteralPath $DataDir -PathType Container)
if ($dataWasCreated) {
  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}
$existingHarnessManaged = $false
$existingDataManaged = $false
$existingNodeManaged = $false
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
  if (-not $Force) { throw "Configuration already exists. Re-run with -Force to replace it: $configPath" }
  try {
    $existingConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$existingConfig.SchemaVersion -eq 2) {
      $existingHarnessManaged = [bool]$existingConfig.HarnessManaged -and [string]::Equals(
        [System.IO.Path]::GetFullPath([string]$existingConfig.HarnessDir).TrimEnd('\'),
        $HarnessDir,
        [System.StringComparison]::OrdinalIgnoreCase
      )
      $existingDataManaged = [bool]$existingConfig.DataManaged -and [string]::Equals(
        [System.IO.Path]::GetFullPath([string]$existingConfig.DataDir).TrimEnd('\'),
        $DataDir,
        [System.StringComparison]::OrdinalIgnoreCase
      )
      $existingNodeManaged = [bool]$existingConfig.NodeManaged -and [string]::Equals(
        [System.IO.Path]::GetFullPath([string]$existingConfig.NodePath).TrimEnd('\'),
        $NodePath,
        [System.StringComparison]::OrdinalIgnoreCase
      )
    }
  } catch {
    Write-Warning "The existing launcher configuration is invalid; ownership flags could not be preserved and the file will be replaced: $configPath"
  }
}

$config = [ordered]@{
  SchemaVersion = 2
  HarnessDir = $HarnessDir
  DataDir = $DataDir
  NodePath = $NodePath
  Language = $Language
  HarnessManaged = [bool]($HarnessManaged -or $existingHarnessManaged)
  DataManaged = [bool]($DataManaged -or $dataWasCreated -or $existingDataManaged)
  NodeManaged = [bool]($NodeManaged -or $existingNodeManaged)
}
$configJson = ($config | ConvertTo-Json -Depth 4) + [Environment]::NewLine
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$temporaryConfig = $configPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
$backupConfig = $configPath + '.bak-' + [Guid]::NewGuid().ToString('N')
try {
  [System.IO.File]::WriteAllText($temporaryConfig, $configJson, $utf8NoBom)
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    [System.IO.File]::Replace($temporaryConfig, $configPath, $backupConfig)
    Remove-Item -LiteralPath $backupConfig -Force
  } else {
    [System.IO.File]::Move($temporaryConfig, $configPath)
  }
} finally {
  if (Test-Path -LiteralPath $temporaryConfig -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryConfig -Force
  }
  if (Test-Path -LiteralPath $backupConfig -PathType Leaf) {
    Remove-Item -LiteralPath $backupConfig -Force
  }
}

$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'
$startMenuDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'DSH Desktop'
$startMenuShortcut = Join-Path $startMenuDirectory 'DeepSeek Harness.lnk'
$createdShortcuts = New-Object 'System.Collections.Generic.List[string]'

if (-not [string]::IsNullOrWhiteSpace($ShortcutPath)) {
  $createdShortcuts.Add((Set-LauncherShortcut -Path $ShortcutPath -Target $entryExecutable -WorkingDirectory $HarnessDir -Replace:$Force))
}
if ($CreateDesktopShortcut) {
  $createdShortcuts.Add((Set-LauncherShortcut -Path $desktopShortcut -Target $entryExecutable -WorkingDirectory $HarnessDir -Replace:$Force))
}
if ($CreateStartMenuShortcut) {
  $createdShortcuts.Add((Set-LauncherShortcut -Path $startMenuShortcut -Target $entryExecutable -WorkingDirectory $HarnessDir -Replace:$Force))
}
if ($RemoveDesktopShortcut) {
  Remove-LauncherShortcut -Path $desktopShortcut -ExpectedTarget $entryExecutable
}
if ($RemoveStartMenuShortcut) {
  Remove-LauncherShortcut -Path $startMenuShortcut -ExpectedTarget $entryExecutable
  if ((Test-Path -LiteralPath $startMenuDirectory -PathType Container) -and
      @(Get-ChildItem -LiteralPath $startMenuDirectory -Force).Count -eq 0) {
    Remove-Item -LiteralPath $startMenuDirectory -Force
  }
}

Write-Output 'DSH Desktop configured.'
Write-Output ("Launcher: {0}" -f $PSScriptRoot)
Write-Output ("Entry EXE: {0}" -f $entryExecutable)
Write-Output ("Setup:     {0}" -f $setupExecutable)
Write-Output ("Uninstall: {0}" -f $uninstallExecutable)
Write-Output ("Harness:   {0}" -f $HarnessDir)
Write-Output ("Data:      {0}" -f $DataDir)
Write-Output ("Node.js:   {0} ({1})" -f $NodePath, $nodeVersion)
if ($createdShortcuts.Count -eq 0) {
  Write-Output 'Shortcuts: none (the app can be opened from its installation folder).'
} else {
  foreach ($createdShortcut in $createdShortcuts) {
    Write-Output ("Shortcut:  {0}" -f $createdShortcut)
  }
}
