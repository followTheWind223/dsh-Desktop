#Requires -Version 5.1

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$BundleDirectory,
  [ValidateSet('win-x64', 'win-arm64')][string]$Architecture = 'win-x64',
  [string]$OutputDirectory,
  [string]$InnoCompilerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsolutePath {
  param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$BasePath)
  if (-not [System.IO.Path]::IsPathRooted($Value)) { $Value = Join-Path $BasePath $Value }
  return [System.IO.Path]::GetFullPath($Value).TrimEnd('\')
}

$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$bundleRoot = Get-AbsolutePath -Value $BundleDirectory -BasePath $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $repoRoot 'artifacts\release' }
$outputRoot = Get-AbsolutePath -Value $OutputDirectory -BasePath $repoRoot
[void](New-Item -ItemType Directory -Path $outputRoot -Force)

& (Join-Path $repoRoot 'Test-BundledRuntime.ps1') -BundleDirectory $bundleRoot

$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a semantic version such as 0.5.0.' }
$manifest = Get-Content -LiteralPath (Join-Path $bundleRoot 'runtime-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$manifest.Architecture -ne $Architecture) {
  throw "The bundle architecture '$($manifest.Architecture)' does not match '$Architecture'."
}

if ([string]::IsNullOrWhiteSpace($InnoCompilerPath)) {
  $candidates = @(
    (Join-Path $repoRoot 'artifacts\tools\Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  )
  $InnoCompilerPath = $candidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($InnoCompilerPath) -or
    -not (Test-Path -LiteralPath $InnoCompilerPath -PathType Leaf)) {
  throw 'Inno Setup 6 compiler was not found. Install it or pass -InnoCompilerPath.'
}

$innoInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($InnoCompilerPath)
$innoSignature = Get-AuthenticodeSignature -LiteralPath $InnoCompilerPath
if ($innoInfo.FileDescription -ne 'Inno Setup Command-Line Compiler' -or
    $innoInfo.ProductName -ne 'Inno Setup' -or
    $innoSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
    $null -eq $innoSignature.SignerCertificate -or
    $innoSignature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Pyrsys B\.V\.(,|$)') {
  throw 'The configured compiler is not an Authenticode-verified Pyrsys B.V. Inno Setup compiler.'
}

$scriptPath = Join-Path $repoRoot 'installer\DSH-Desktop.iss'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Installer definition is missing: $scriptPath" }

& $InnoCompilerPath @(
  '/Qp',
  ('/DAppVersion=' + $version),
  ('/DBundleDir=' + $bundleRoot),
  ('/DOutputDir=' + $outputRoot),
  ('/DArchitecture=' + $Architecture),
  $scriptPath
)
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed with exit code $LASTEXITCODE." }

$setupPath = Join-Path $outputRoot ("DSH-Desktop-Setup-v{0}-{1}.exe" -f $version, $Architecture)
if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) { throw "Setup output is missing: $setupPath" }
$header = [System.IO.File]::ReadAllBytes($setupPath)[0..1]
if ($header[0] -ne 0x4D -or $header[1] -ne 0x5A) { throw 'The setup output is not a Windows executable.' }

$hash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Single-file setup: $setupPath"
Write-Output "SHA256:           $hash"
$signature = Get-AuthenticodeSignature -LiteralPath $setupPath
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
  Write-Warning 'The setup executable is not code-signed. It can run, but SmartScreen reputation warnings may remain until release signing is configured.'
}
