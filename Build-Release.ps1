#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$Tag,
  [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
  throw 'VERSION must contain a semantic version such as 0.3.0.'
}
$expectedTag = 'v' + $version
if ([string]::IsNullOrWhiteSpace($Tag)) {
  $Tag = $expectedTag
}
if ($Tag -notmatch '^v\d+\.\d+\.\d+$' -or
    -not [string]::Equals($Tag, $expectedTag, [System.StringComparison]::Ordinal)) {
  throw "Release tag '$Tag' must exactly match VERSION ('$expectedTag')."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $PSScriptRoot 'artifacts'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
  $OutputDirectory = Join-Path $PSScriptRoot $OutputDirectory
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$driveRoot = [System.IO.Path]::GetPathRoot($outputRoot).TrimEnd('\')
if ([string]::Equals($outputRoot, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals($outputRoot, $driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Unsafe release output directory: $outputRoot"
}
[void](New-Item -ItemType Directory -Path $outputRoot -Force)

$packageName = 'DSH-Desktop-' + $Tag
$stagingRoot = Join-Path $outputRoot ('.staging-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot $packageName
$zipPath = Join-Path $outputRoot ($packageName + '-windows.zip')
$zipChecksumPath = $zipPath + '.sha256'

$releaseFiles = @(
  '.gitattributes',
  '.gitignore',
  '.github\workflows\release.yml',
  'Build-Exe.ps1',
  'Build-Release.ps1',
  'CHANGELOG.md',
  'CONTRIBUTING.md',
  'DeepSeek-Harness-Desktop.ps1',
  'Install.ps1',
  'launcher.config.example.json',
  'LICENSE',
  'README.md',
  'SECURITY.md',
  'Setup.ps1',
  'Test-Release.ps1',
  'THIRD_PARTY_NOTICES.md',
  'Uninstall.ps1',
  'VERSION',
  'assets\deepseek-harness.ico',
  'assets\deepseek-harness.svg',
  'src\DSH-Desktop\Program.cs',
  'src\DSH-Desktop\UninstallProgram.cs'
)

try {
  [void](New-Item -ItemType Directory -Path $packageRoot -Force)
  foreach ($relativePath in $releaseFiles) {
    $sourcePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
      throw "Required release input is missing: $relativePath"
    }
    $destinationPath = Join-Path $packageRoot $relativePath
    $destinationParent = Split-Path -Parent $destinationPath
    [void](New-Item -ItemType Directory -Path $destinationParent -Force)
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
  }

  $launcherPath = Join-Path $packageRoot 'DSH-Desktop.exe'
  $uninstallerPath = Join-Path $packageRoot 'Uninstall-DSH-Desktop.exe'
  & (Join-Path $PSScriptRoot 'Build-Exe.ps1') -OutputPath $launcherPath -UninstallOutputPath $uninstallerPath
  & (Join-Path $PSScriptRoot 'Test-Release.ps1') -LauncherPath $launcherPath -UninstallerPath $uninstallerPath

  $executableChecksums = @(
    ('{0} *DSH-Desktop.exe' -f (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()),
    ('{0} *Uninstall-DSH-Desktop.exe' -f (Get-FileHash -LiteralPath $uninstallerPath -Algorithm SHA256).Hash.ToLowerInvariant())
  )
  [System.IO.File]::WriteAllLines(
    (Join-Path $packageRoot 'SHA256SUMS.txt'),
    $executableChecksums,
    (New-Object System.Text.UTF8Encoding($false))
  )

  Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
  $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  [System.IO.File]::WriteAllText(
    $zipChecksumPath,
    ($zipHash + ' *' + [System.IO.Path]::GetFileName($zipPath) + [Environment]::NewLine),
    (New-Object System.Text.UTF8Encoding($false))
  )

  Write-Output "Release package: $zipPath"
  Write-Output "ZIP SHA-256:    $zipHash"
  Write-Output "Checksum file:  $zipChecksumPath"
} finally {
  $resolvedStagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
  $outputPrefix = $outputRoot + '\'
  if ((Test-Path -LiteralPath $resolvedStagingRoot -PathType Container) -and
      $resolvedStagingRoot.StartsWith($outputPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
      [System.IO.Path]::GetFileName($resolvedStagingRoot).StartsWith('.staging-', [System.StringComparison]::Ordinal)) {
    Remove-Item -LiteralPath $resolvedStagingRoot -Recurse -Force
  }
}
