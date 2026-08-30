#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$ShortcutPath,
  [switch]$RemoveDesktopShortcut,
  [switch]$RemoveStartMenuShortcut,
  [switch]$RemoveConfig,
  [switch]$RemoveLauncherFiles,
  [switch]$RemoveHarness,
  [switch]$ConfirmExistingHarnessRemoval,
  [switch]$RemoveManagedHarness,
  [switch]$RemoveManagedNode,
  [switch]$RemoveManagedData,
  [ValidateRange(0, 2147483647)][int]$WaitForProcessId = 0,
  [switch]$ShowCompletion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$removeHarnessRequested = [bool]($RemoveHarness -or $RemoveManagedHarness)

function Show-UninstallMessage {
  param([string]$Chinese, [string]$English, [System.Windows.Forms.MessageBoxIcon]$Icon)
  if (-not $ShowCompletion) { return }
  $isChinese = [System.Globalization.CultureInfo]::CurrentUICulture.Name.StartsWith('zh', [System.StringComparison]::OrdinalIgnoreCase)
  [System.Windows.Forms.MessageBox]::Show(
    $(if ($isChinese) { $Chinese } else { $English }),
    $(if ($isChinese) { 'DSH Desktop 卸载' } else { 'DSH Desktop Uninstall' }),
    [System.Windows.Forms.MessageBoxButtons]::OK,
    $Icon
  ) | Out-Null
}

function Get-SafeLocalPath {
  param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Name)
  if ([string]::IsNullOrWhiteSpace($Value) -or -not [System.IO.Path]::IsPathRooted($Value)) { throw "$Name is not an absolute path." }
  $full = [System.IO.Path]::GetFullPath($Value).TrimEnd('\')
  $drive = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
  if ($full.StartsWith('\\', [System.StringComparison]::Ordinal) -or
      [string]::Equals($full, $drive, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing an unsafe $Name path: $full"
  }
  return $full
}

function Assert-SeparateFromLauncher {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$LauncherRoot)
  $pathPrefix = $Path.TrimEnd('\') + '\'
  $launcherPrefix = $LauncherRoot.TrimEnd('\') + '\'
  if ([string]::Equals($Path, $LauncherRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      $Path.StartsWith($launcherPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
      $LauncherRoot.StartsWith($pathPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a component that overlaps the launcher directory: $Path"
  }
}

function Remove-OwnedDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedLeaf,
    [Parameter(Mandatory = $true)][string]$LauncherRoot,
    [string[]]$RequiredMarkers = @()
  )
  $full = Get-SafeLocalPath -Value $Path -Name $ExpectedLeaf
  Assert-SeparateFromLauncher -Path $full -LauncherRoot $LauncherRoot
  if (-not [string]::Equals((Split-Path -Leaf $full), $ExpectedLeaf, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a component with an unexpected directory name: $full"
  }
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { return }
  $directoryInfo = Get-Item -LiteralPath $full -Force
  if (($directoryInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Refusing to remove a component through a reparse point: $full"
  }
  foreach ($marker in $RequiredMarkers) {
    if (-not (Test-Path -LiteralPath (Join-Path $full $marker) -PathType Leaf)) { throw "Refusing component removal because a marker is missing: $marker" }
  }
  Remove-Item -LiteralPath $full -Recurse -Force
  Write-Output "Removed selected component: $full"
}

function Assert-HarnessIdentity {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Get-SafeLocalPath -Value $Path -Name 'HarnessDir'
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { return }
  $packagePath = Join-Path $full 'package.json'
  try {
    $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    throw 'Refusing Harness removal because package.json is invalid.'
  }
  if (-not [string]::Equals([string]$package.name, '@deepseek-ai/dsh-root', [System.StringComparison]::Ordinal)) {
    throw 'Refusing Harness removal because the package identity is not @deepseek-ai/dsh-root.'
  }
}

function Remove-OwnedNode {
  param([Parameter(Mandatory = $true)][string]$NodePath, [Parameter(Mandatory = $true)][string]$LauncherRoot)
  $nodeExecutable = Get-SafeLocalPath -Value $NodePath -Name 'NodePath'
  if (-not [string]::Equals((Split-Path -Leaf $nodeExecutable), 'node.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove an unexpected Node path: $nodeExecutable"
  }
  $versionDirectory = Split-Path -Parent $nodeExecutable
  $versionLeaf = Split-Path -Leaf $versionDirectory
  if ($versionLeaf -notmatch '^node-v\d+\.\d+\.\d+-win-(x64|arm64)$') {
    throw "Refusing to remove an unexpected portable Node directory: $versionDirectory"
  }
  $nodeRoot = Split-Path -Parent $versionDirectory
  if (-not [string]::Equals((Split-Path -Leaf $nodeRoot), 'nodejs', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove Node outside a nodejs directory: $versionDirectory"
  }
  Assert-SeparateFromLauncher -Path $versionDirectory -LauncherRoot $LauncherRoot
  if (Test-Path -LiteralPath $versionDirectory -PathType Container) {
    if (-not (Test-Path -LiteralPath $nodeExecutable -PathType Leaf)) { throw 'Refusing portable Node removal because node.exe is missing.' }
    Remove-Item -LiteralPath $versionDirectory -Recurse -Force
    Write-Output "Removed managed portable Node.js: $versionDirectory"
  }
  if ((Test-Path -LiteralPath $nodeRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $nodeRoot -Force).Count -eq 0) {
    Remove-Item -LiteralPath $nodeRoot -Force
  }
}

function Remove-OwnedShortcut {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ExpectedTarget)
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
  Write-Output "Removed shortcut: $Path"
}

function Remove-EmptyDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ((Test-Path -LiteralPath $Path -PathType Container) -and @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Get-ManagedInstallContainer {
  param(
    [Parameter(Mandatory = $true)][string]$LauncherRoot,
    [AllowNull()][object]$Configuration
  )

  if ($null -eq $Configuration -or
      -not [bool]$Configuration.HarnessManaged -or
      -not [bool]$Configuration.DataManaged) {
    return $null
  }

  try {
    $harness = Get-SafeLocalPath -Value ([string]$Configuration.HarnessDir) -Name 'HarnessDir'
    $data = Get-SafeLocalPath -Value ([string]$Configuration.DataDir) -Name 'DataDir'
    if (-not [string]::Equals((Split-Path -Leaf $harness), 'deepseek-harness', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals((Split-Path -Leaf $data), 'deepseek-harness-data', [System.StringComparison]::OrdinalIgnoreCase)) {
      return $null
    }

    $container = Get-SafeLocalPath -Value (Split-Path -Parent $LauncherRoot) -Name 'install container'
    foreach ($componentParent in @((Split-Path -Parent $harness), (Split-Path -Parent $data))) {
      $normalizedParent = Get-SafeLocalPath -Value $componentParent -Name 'component parent'
      if (-not [string]::Equals($normalizedParent, $container, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
      }
    }
    return $container
  } catch {
    Write-Warning "The outer installation folder will be preserved because its ownership could not be verified: $($_.Exception.Message)"
    return $null
  }
}

function Remove-EmptyInstallContainer {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return }
  $full = Get-SafeLocalPath -Value $Path -Name 'install container'
  $directoryInfo = Get-Item -LiteralPath $full -Force
  if (($directoryInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    Write-Warning "The outer installation folder is a reparse point and was preserved: $full"
    return
  }
  if (@(Get-ChildItem -LiteralPath $full -Force).Count -ne 0) {
    Write-Verbose "The outer installation folder contains other items and was preserved: $full"
    return
  }
  Remove-Item -LiteralPath $full -Force
  Write-Output "Removed empty installation folder: $full"
}

function Remove-KnownLauncherFiles {
  param([Parameter(Mandatory = $true)][string]$LauncherRoot)
  if (-not $RemoveConfig) { throw 'RemoveLauncherFiles requires RemoveConfig.' }
  if (Test-Path -LiteralPath (Join-Path $LauncherRoot '.git')) {
    Write-Verbose "Preserved DSH Desktop source checkout: $LauncherRoot"
    return -1
  }
  foreach ($marker in @('DSH-Desktop.exe', 'DSH-Setup.exe', 'Uninstall-DSH-Desktop.exe', 'VERSION')) {
    if (-not (Test-Path -LiteralPath (Join-Path $LauncherRoot $marker) -PathType Leaf)) {
      throw "Refusing launcher cleanup because a package marker is missing: $marker"
    }
  }
  $knownFiles = @(
    '.gitattributes', '.gitignore', '.github\workflows\release.yml',
    'Build-Exe.ps1', 'Build-Setup.ps1', 'Build-Release.ps1', 'Test-Release.ps1',
    'CHANGELOG.md', 'CODE_SIGNING_POLICY.md', 'CONTRIBUTING.md', 'DeepSeek-Harness-Desktop.ps1',
    'DSH-Desktop.exe', 'DSH-Desktop.exe.config', 'DSH-Setup.exe', 'Uninstall-DSH-Desktop.exe',
    'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll',
    'Install.ps1', 'Setup.ps1', 'Setup-GUI.ps1', 'Ensure-WebView2.ps1', 'Uninstall.ps1',
    'LICENSE', 'PRIVACY.md', 'README.md', 'SECURITY.md', 'SHA256SUMS.txt', 'THIRD_PARTY_NOTICES.md', 'VERSION',
    'launcher.config.example.json', 'launcher.config.json',
    'assets\deepseek-harness.ico', 'assets\deepseek-harness.svg',
    'runtimes\win-x86\native\WebView2Loader.dll',
    'runtimes\win-x64\native\WebView2Loader.dll',
    'runtimes\win-arm64\native\WebView2Loader.dll',
    'src\DSH-Desktop\App.config', 'src\DSH-Desktop\app.manifest',
    'src\DSH-Desktop\AppConfiguration.cs', 'src\DSH-Desktop\AssemblyInfo.cs',
    'src\DSH-Desktop\BackendHost.cs', 'src\DSH-Desktop\DiagnosticText.cs',
    'src\DSH-Desktop\DSH-Desktop.csproj', 'src\DSH-Desktop\Localizer.cs',
    'src\DSH-Desktop\MainForm.cs', 'src\DSH-Desktop\NativeJob.cs',
    'src\DSH-Desktop\packages.lock.json', 'src\DSH-Desktop\Program.cs',
    'src\DSH-Desktop\UninstallProgram.cs', 'src\DSH-Setup\SetupProgram.cs'
  )
  $rootPrefix = $LauncherRoot + '\'
  foreach ($relative in $knownFiles) {
    $knownPath = [System.IO.Path]::GetFullPath((Join-Path $LauncherRoot $relative))
    if (-not $knownPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe cleanup path: $relative" }
    if (Test-Path -LiteralPath $knownPath -PathType Leaf) { Remove-Item -LiteralPath $knownPath -Force }
  }
  foreach ($directory in @(
      'runtimes\win-x86\native', 'runtimes\win-x86', 'runtimes\win-x64\native', 'runtimes\win-x64',
      'runtimes\win-arm64\native', 'runtimes\win-arm64', 'runtimes', 'assets',
      '.github\workflows', '.github', 'src\DSH-Setup', 'src\DSH-Desktop', 'src'
    )) { Remove-EmptyDirectory -Path (Join-Path $LauncherRoot $directory) }
  $remaining = if (Test-Path -LiteralPath $LauncherRoot -PathType Container) { @(Get-ChildItem -LiteralPath $LauncherRoot -Force).Count } else { 0 }
  if ($remaining -eq 0 -and -not [string]::Equals((Get-Location).Path.TrimEnd('\'), $LauncherRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $LauncherRoot -Force
  }
  return $remaining
}

function Remove-InstallRecord {
  param([Parameter(Mandatory = $true)][string]$LauncherRoot)

  $registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DSH Desktop'
  if (-not (Test-Path -LiteralPath $registryPath)) { return }

  try {
    $record = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
    $registeredLocation = Get-SafeLocalPath -Value ([string]$record.InstallLocation) -Name 'registered install location'
    if (-not [string]::Equals($registeredLocation, $LauncherRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      Write-Warning "A DSH Desktop install record for another folder was left unchanged: $registeredLocation"
      return
    }
    Remove-Item -LiteralPath $registryPath -Force
    Write-Output "Removed per-user install record: $registryPath"
  } catch {
    Write-Warning "The per-user install record could not be removed safely: $($_.Exception.Message)"
  }
}

try {
  if ($RemoveLauncherFiles -and -not $RemoveConfig) { throw 'RemoveLauncherFiles requires RemoveConfig.' }
  $launcherRoot = Get-SafeLocalPath -Value $PSScriptRoot -Name 'launcher directory'
  $configPath = Join-Path $launcherRoot 'launcher.config.json'
  $config = $null
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$config.SchemaVersion -ne 2) { throw 'The launcher configuration schema is invalid.' }
  }
  if (($removeHarnessRequested -or $RemoveManagedNode -or $RemoveManagedData) -and $null -eq $config) {
    throw 'Selected components cannot be removed because launcher.config.json is missing.'
  }
  $installContainer = Get-ManagedInstallContainer -LauncherRoot $launcherRoot -Configuration $config

  if ($WaitForProcessId -gt 0) {
    if (-not $RemoveLauncherFiles) { throw 'WaitForProcessId is valid only with RemoveLauncherFiles.' }
    $expectedUninstaller = Join-Path $launcherRoot 'Uninstall-DSH-Desktop.exe'
    $process = Get-Process -Id $WaitForProcessId -ErrorAction SilentlyContinue
    if ($null -ne $process) {
      if (-not [string]::Equals($process.Path, $expectedUninstaller, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to wait for a process that is not this package uninstaller.'
      }
      Wait-Process -Id $WaitForProcessId -Timeout 30
    }
  }

  $entryExecutable = Join-Path $launcherRoot 'DSH-Desktop.exe'
  $desktopPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'
  $startMenuDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'DSH Desktop'
  $startMenuPath = Join-Path $startMenuDirectory 'DeepSeek Harness.lnk'
  if ($RemoveDesktopShortcut -or (-not $RemoveStartMenuShortcut -and [string]::IsNullOrWhiteSpace($ShortcutPath))) {
    Remove-OwnedShortcut -Path $desktopPath -ExpectedTarget $entryExecutable
  }
  if ($RemoveStartMenuShortcut) {
    Remove-OwnedShortcut -Path $startMenuPath -ExpectedTarget $entryExecutable
    Remove-EmptyDirectory -Path $startMenuDirectory
  }
  if (-not [string]::IsNullOrWhiteSpace($ShortcutPath)) {
    Remove-OwnedShortcut -Path (Get-SafeLocalPath -Value $ShortcutPath -Name 'ShortcutPath') -ExpectedTarget $entryExecutable
  }

  if ($removeHarnessRequested) {
    $harnessManaged = [bool]$config.HarnessManaged
    if ($RemoveManagedHarness -and -not $harnessManaged) {
      throw 'Harness is not marked as installer-managed; use the interactive uninstaller to confirm removal of an existing Harness.'
    }
    if (-not $harnessManaged -and -not $ConfirmExistingHarnessRemoval) {
      throw 'Removing an existing Harness requires explicit confirmation.'
    }
    Assert-HarnessIdentity -Path ([string]$config.HarnessDir)
    Remove-OwnedDirectory -Path ([string]$config.HarnessDir) -ExpectedLeaf 'deepseek-harness' -LauncherRoot $launcherRoot -RequiredMarkers @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'apps\cli\src\bin.ts')
  }
  if ($RemoveManagedNode) {
    if (-not [bool]$config.NodeManaged) { throw 'Node.js is not marked as installer-managed; it will not be removed.' }
    Remove-OwnedNode -NodePath ([string]$config.NodePath) -LauncherRoot $launcherRoot
  }
  if ($RemoveManagedData) {
    if (-not [bool]$config.DataManaged) { throw 'Data is not marked as installer-managed; it will not be removed.' }
    Remove-OwnedDirectory -Path ([string]$config.DataDir) -ExpectedLeaf 'deepseek-harness-data' -LauncherRoot $launcherRoot
  }

  if ($RemoveConfig -and (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Remove-Item -LiteralPath $configPath -Force
    Write-Output "Removed configuration: $configPath"
  }
  $remaining = $null
  if ($RemoveLauncherFiles) { $remaining = Remove-KnownLauncherFiles -LauncherRoot $launcherRoot }
  if ($RemoveConfig) { Remove-InstallRecord -LauncherRoot $launcherRoot }
  if ($RemoveLauncherFiles) { Remove-EmptyInstallContainer -Path $installContainer }

  $english = if ($RemoveLauncherFiles -and $remaining -eq -1) {
    'DSH Desktop configuration and shortcuts were removed. The Git source checkout was preserved.'
  } elseif ($RemoveLauncherFiles -and $remaining -eq 0) {
    'DSH Desktop was removed. Components that were not explicitly selected were preserved.'
  } elseif ($RemoveLauncherFiles) {
    "Known DSH Desktop files were removed. The folder was kept because it contains $remaining unrecognized item(s)."
  } else { 'Selected shortcuts and configuration were removed.' }
  $chinese = if ($RemoveLauncherFiles -and $remaining -eq -1) {
    '已删除 DSH Desktop 配置和快捷方式，并保留 Git 源码仓库。'
  } elseif ($RemoveLauncherFiles -and $remaining -eq 0) {
    'DSH Desktop 已卸载。未明确勾选的组件均已保留。'
  } elseif ($RemoveLauncherFiles) {
    "已删除已知桌面端文件。目录中仍有 $remaining 个未识别项目，因此保留了该目录。"
  } else { '已删除所选快捷方式和配置。' }
  Write-Output $english
  Show-UninstallMessage -Chinese $chinese -English $english -Icon Information
} catch {
  Write-Error $_.Exception.Message -ErrorAction Continue
  Show-UninstallMessage -Chinese ('卸载失败：' + $_.Exception.Message) -English ('Uninstall failed: ' + $_.Exception.Message) -Icon Error
  exit 1
}
