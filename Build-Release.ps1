#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$Tag,
  [ValidateSet('win-x64', 'win-arm64')][string]$Architecture = 'win-x64',
  [string]$OutputDirectory,
  [string]$DotNetPath,
  [string]$InnoCompilerPath,
  [switch]$SkipAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsolutePath {
  param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$BasePath)
  if (-not [System.IO.Path]::IsPathRooted($Value)) { $Value = Join-Path $BasePath $Value }
  return [System.IO.Path]::GetFullPath($Value).TrimEnd('\')
}

$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a semantic version such as 0.5.0.' }
$expectedTag = 'v' + $version
if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = $expectedTag }
if (-not [string]::Equals($Tag, $expectedTag, [System.StringComparison]::Ordinal)) {
  throw "Release tag '$Tag' must exactly match VERSION ('$expectedTag')."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $repoRoot 'artifacts\release' }
$outputRoot = Get-AbsolutePath -Value $OutputDirectory -BasePath $repoRoot
$artifactsRoot = Join-Path $repoRoot 'artifacts'
$driveRoot = [System.IO.Path]::GetPathRoot($outputRoot).TrimEnd('\')
if ([string]::Equals($outputRoot, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals($outputRoot, $driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Unsafe release output directory: $outputRoot"
}
[void](New-Item -ItemType Directory -Path $outputRoot -Force)

$bundleRoot = Join-Path $artifactsRoot ('bundled-runtime-' + $Architecture)
$runtimeParameters = @{
  Architecture = $Architecture
  OutputDirectory = $bundleRoot
  Force = $true
  SkipAudit = $SkipAudit
}
if (-not [string]::IsNullOrWhiteSpace($DotNetPath)) { $runtimeParameters.DotNetPath = $DotNetPath }
& (Join-Path $repoRoot 'Build-BundledRuntime.ps1') @runtimeParameters

$setupParameters = @{
  BundleDirectory = $bundleRoot
  Architecture = $Architecture
  OutputDirectory = $outputRoot
}
if (-not [string]::IsNullOrWhiteSpace($InnoCompilerPath)) { $setupParameters.InnoCompilerPath = $InnoCompilerPath }
& (Join-Path $repoRoot 'Build-BundledSetup.ps1') @setupParameters

$setupPath = Join-Path $outputRoot ("DSH-Desktop-Setup-{0}-{1}.exe" -f $Tag, $Architecture)
$manifestPath = Join-Path $outputRoot ("DSH-Desktop-runtime-manifest-{0}-{1}.json" -f $Tag, $Architecture)
$checksumPath = Join-Path $outputRoot ("SHA256SUMS-{0}-{1}.txt" -f $Tag, $Architecture)
Copy-Item -LiteralPath (Join-Path $bundleRoot 'runtime-manifest.json') -Destination $manifestPath -Force

$checksumLines = foreach ($path in @($setupPath, $manifestPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release artifact is missing: $path" }
  '{0} *{1}' -f (
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(),
    [System.IO.Path]::GetFileName($path)
  )
}
[System.IO.File]::WriteAllLines($checksumPath, $checksumLines, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Setup:     $setupPath"
Write-Output "Manifest:  $manifestPath"
Write-Output "Checksums: $checksumPath"
