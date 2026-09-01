#Requires -Version 5.1

[CmdletBinding()]
param(
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-OfficialDownload {
  param([Parameter(Mandatory = $true)][uri]$Uri, [Parameter(Mandatory = $true)][string]$OutFile)
  if ($Uri.Scheme -ne 'https' -or $Uri.Host -notin @('dot.net', 'github.com')) {
    throw "Refusing an unapproved build-tool URL: $Uri"
  }
  $temporary = $OutFile + '.download-' + [Guid]::NewGuid().ToString('N')
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $Uri.AbsoluteUri -OutFile $temporary
    if (-not (Test-Path -LiteralPath $temporary -PathType Leaf) -or (Get-Item -LiteralPath $temporary).Length -eq 0) {
      throw "The download did not produce a file: $Uri"
    }
    Move-Item -LiteralPath $temporary -Destination $OutFile -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}

$toolsRoot = Join-Path $PSScriptRoot 'artifacts\tools'
$dotnetRoot = Join-Path $toolsRoot 'dotnet'
$dotnetPath = Join-Path $dotnetRoot 'dotnet.exe'
$innoRoot = Join-Path $toolsRoot 'Inno Setup 6'
$innoPath = Join-Path $innoRoot 'ISCC.exe'
[void](New-Item -ItemType Directory -Path $toolsRoot -Force)

if ($Force -or -not (Test-Path -LiteralPath $dotnetPath -PathType Leaf) -or
    (& $dotnetPath --list-sdks 2>$null) -notmatch '^8\.') {
  $dotnetInstall = Join-Path $toolsRoot 'dotnet-install.ps1'
  Invoke-OfficialDownload -Uri ([uri]'https://dot.net/v1/dotnet-install.ps1') -OutFile $dotnetInstall
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $dotnetInstall `
    -Channel 8.0 -Quality GA -InstallDir $dotnetRoot -NoPath
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dotnetPath -PathType Leaf)) {
    throw '.NET SDK 8 installation failed.'
  }
}

if ($Force -or -not (Test-Path -LiteralPath $innoPath -PathType Leaf)) {
  $innoInstaller = Join-Path $toolsRoot 'innosetup-6.7.3.exe'
  Invoke-OfficialDownload `
    -Uri ([uri]'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe') `
    -OutFile $innoInstaller
  $signature = Get-AuthenticodeSignature -LiteralPath $innoInstaller
  if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
      $null -eq $signature.SignerCertificate -or
      $signature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Pyrsys B\.V\.(,|$)') {
    throw 'The Inno Setup installer does not have the expected valid Pyrsys B.V. signature.'
  }
  & $innoInstaller @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS',
    ('/DIR=' + $innoRoot)
  )
  if (-not (Test-Path -LiteralPath $innoPath -PathType Leaf)) {
    throw 'Inno Setup installation failed.'
  }
}

Write-Output "DotNetPath:        $dotnetPath"
Write-Output "InnoCompilerPath: $innoPath"
