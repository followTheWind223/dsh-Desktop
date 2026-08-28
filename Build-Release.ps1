#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$Tag,
  [string]$OutputDirectory,
  [string]$DotNetPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a semantic version such as 0.4.0.' }
$expectedTag = 'v' + $version
if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = $expectedTag }
if (-not [string]::Equals($Tag, $expectedTag, [System.StringComparison]::Ordinal)) {
  throw "Release tag '$Tag' must exactly match VERSION ('$expectedTag')."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $PSScriptRoot 'artifacts' }
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $PSScriptRoot $OutputDirectory }
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
$zipPath = Join-Path $outputRoot ($packageName + '-windows-portable.zip')
$setupArtifact = Join-Path $outputRoot ('DSH-Desktop-Setup-' + $Tag + '.exe')
$checksumPath = Join-Path $outputRoot ('SHA256SUMS-' + $Tag + '.txt')

$payloadFiles = @(
  'Install.ps1', 'Setup.ps1', 'Setup-GUI.ps1', 'Ensure-WebView2.ps1', 'Uninstall.ps1',
  'CHANGELOG.md', 'LICENSE', 'README.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'VERSION',
  'assets\deepseek-harness.ico', 'assets\deepseek-harness.svg'
)

try {
  [void](New-Item -ItemType Directory -Path $packageRoot -Force)
  foreach ($relative in $payloadFiles) {
    $source = Join-Path $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required release input is missing: $relative" }
    $destination = Join-Path $packageRoot $relative
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }

  $buildParameters = @{ OutputDirectory = $packageRoot }
  if (-not [string]::IsNullOrWhiteSpace($DotNetPath)) { $buildParameters.DotNetPath = $DotNetPath }
  & (Join-Path $PSScriptRoot 'Build-Exe.ps1') @buildParameters
  & (Join-Path $PSScriptRoot 'Build-Setup.ps1') -PayloadDirectory $packageRoot -OutputPath (Join-Path $packageRoot 'DSH-Setup.exe')

  $runtimeChecksums = foreach ($relative in @(
      'DSH-Desktop.exe', 'DSH-Setup.exe', 'Uninstall-DSH-Desktop.exe',
      'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll'
    )) {
    $path = Join-Path $packageRoot $relative
    '{0} *{1}' -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(), $relative.Replace('\', '/')
  }
  [System.IO.File]::WriteAllLines(
    (Join-Path $packageRoot 'SHA256SUMS.txt'),
    $runtimeChecksums,
    (New-Object System.Text.UTF8Encoding($false))
  )

  & (Join-Path $PSScriptRoot 'Test-Release.ps1') -PackageRoot $packageRoot
  Copy-Item -LiteralPath (Join-Path $packageRoot 'DSH-Setup.exe') -Destination $setupArtifact -Force
  Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force

  $artifactChecksums = foreach ($path in @($setupArtifact, $zipPath)) {
    '{0} *{1}' -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(), [System.IO.Path]::GetFileName($path)
  }
  [System.IO.File]::WriteAllLines($checksumPath, $artifactChecksums, (New-Object System.Text.UTF8Encoding($false)))

  Write-Output "Standalone setup: $setupArtifact"
  Write-Output "Portable package: $zipPath"
  Write-Output "Checksums:        $checksumPath"
} finally {
  $resolvedStaging = [System.IO.Path]::GetFullPath($stagingRoot)
  if ((Test-Path -LiteralPath $resolvedStaging -PathType Container) -and
      $resolvedStaging.StartsWith($outputRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -and
      [System.IO.Path]::GetFileName($resolvedStaging).StartsWith('.staging-', [System.StringComparison]::Ordinal)) {
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
  }
}
