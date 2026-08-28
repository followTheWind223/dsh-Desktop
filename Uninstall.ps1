#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$ShortcutPath,
  [switch]$RemoveConfig,
  [switch]$RemoveLauncherFiles,
  [ValidateRange(0, 2147483647)][int]$WaitForProcessId = 0,
  [switch]$ShowCompletion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Show-UninstallMessage {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][System.Windows.Forms.MessageBoxIcon]$Icon
  )

  if (-not $ShowCompletion) { return }
  [System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    $Icon
  ) | Out-Null
}

function Remove-EmptyDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
  if (@(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Remove-KnownLauncherFiles {
  if (-not $RemoveConfig) {
    throw 'RemoveLauncherFiles requires RemoveConfig so local path configuration is not left behind.'
  }

  $launcherRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
  $driveRoot = [System.IO.Path]::GetPathRoot($launcherRoot)
  if ($launcherRoot.StartsWith('\\', [System.StringComparison]::Ordinal) -or
      [string]::Equals($launcherRoot, $driveRoot.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove launcher files from an unsafe directory: $launcherRoot"
  }

  foreach ($marker in @('DeepSeek-Harness-Desktop.ps1', 'DSH-Desktop.exe', 'Uninstall-DSH-Desktop.exe', 'VERSION')) {
    if (-not (Test-Path -LiteralPath (Join-Path $launcherRoot $marker) -PathType Leaf)) {
      throw "Refusing launcher cleanup because a package marker is missing: $marker"
    }
  }
  $versionText = (Get-Content -LiteralPath (Join-Path $launcherRoot 'VERSION') -Raw).Trim()
  if ($versionText -notmatch '^\d+\.\d+\.\d+$') {
    throw 'Refusing launcher cleanup because VERSION is invalid.'
  }

  $knownFiles = @(
    '.gitattributes',
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
    'Test-Release.ps1',
    'THIRD_PARTY_NOTICES.md',
    'Uninstall-DSH-Desktop.exe',
    'Uninstall.ps1',
    'VERSION',
    'launcher.config.example.json',
    'assets\deepseek-harness.ico',
    'assets\deepseek-harness.svg',
    'src\DSH-Desktop\Program.cs',
    'src\DSH-Desktop\UninstallProgram.cs'
  )
  foreach ($relativePath in $knownFiles) {
    $knownPath = [System.IO.Path]::GetFullPath((Join-Path $launcherRoot $relativePath))
    $rootPrefix = $launcherRoot + '\'
    if (-not $knownPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing an unsafe launcher cleanup path: $relativePath"
    }
    if (Test-Path -LiteralPath $knownPath -PathType Leaf) {
      Remove-Item -LiteralPath $knownPath -Force
    }
  }

  Remove-EmptyDirectory -Path (Join-Path $launcherRoot 'assets')
  Remove-EmptyDirectory -Path (Join-Path $launcherRoot 'src\DSH-Desktop')
  Remove-EmptyDirectory -Path (Join-Path $launcherRoot 'src')

  $remainingCount = if (Test-Path -LiteralPath $launcherRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $launcherRoot -Force).Count
  } else {
    0
  }
  if ($remainingCount -eq 0 -and
      -not [string]::Equals((Get-Location).Path.TrimEnd('\'), $launcherRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $launcherRoot -Force
  }
  return $remainingCount
}

try {
  if ($RemoveLauncherFiles -and -not $RemoveConfig) {
    throw 'RemoveLauncherFiles requires RemoveConfig so local path configuration is not left behind.'
  }
  if ($WaitForProcessId -gt 0) {
    if (-not $RemoveLauncherFiles) { throw 'WaitForProcessId is valid only with RemoveLauncherFiles.' }
    $uninstallerPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Uninstall-DSH-Desktop.exe'))
    $uninstallerProcess = Get-Process -Id $WaitForProcessId -ErrorAction SilentlyContinue
    if ($null -ne $uninstallerProcess) {
      if (-not [string]::Equals($uninstallerProcess.Path, $uninstallerPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to wait for a process that is not this package uninstaller.'
      }
      Wait-Process -Id $WaitForProcessId -Timeout 30
    }
  }

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
  $entryExecutable = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'DSH-Desktop.exe'))
  if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $expectedArgument = '-File "' + $launcherScript + '"'
    $isExeShortcut = $false
    if (-not [string]::IsNullOrWhiteSpace($shortcut.TargetPath)) {
      $isExeShortcut = [string]::Equals(
        [System.IO.Path]::GetFullPath($shortcut.TargetPath),
        $entryExecutable,
        [System.StringComparison]::OrdinalIgnoreCase
      )
    }
    $isLegacyShortcut = $shortcut.Arguments.IndexOf(
      $expectedArgument,
      [System.StringComparison]::OrdinalIgnoreCase
    ) -ge 0
    if (-not $isExeShortcut -and -not $isLegacyShortcut) {
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

  $remainingLauncherItems = $null
  if ($RemoveLauncherFiles) {
    $remainingLauncherItems = Remove-KnownLauncherFiles
  }

  $message = 'Harness source code, session data, portable Node.js, Edge, and environment variables were not changed.'
  if ($RemoveLauncherFiles) {
    if ($remainingLauncherItems -eq 0) {
      $message = "DSH Desktop launcher files were removed.`n`n$message"
    } else {
      $message = "Known DSH Desktop launcher files were removed. The launcher folder was kept because it contains $remainingLauncherItems unrecognized item(s).`n`n$message"
    }
  }
  Write-Output $message
  Show-UninstallMessage -Title 'DSH Desktop uninstalled' -Message $message -Icon Information
} catch {
  $message = $_.Exception.Message
  Write-Error $message -ErrorAction Continue
  Show-UninstallMessage -Title 'DSH Desktop uninstall failed' -Message $message -Icon Error
  exit 1
}
