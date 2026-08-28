#Requires -Version 5.1

[CmdletBinding()]
param(
  [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$bootstrapperUri = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
$clientId = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'

function Get-WebView2Version {
  foreach ($location in @(
      "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$clientId",
      "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$clientId",
      "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$clientId"
    )) {
    if (-not (Test-Path -LiteralPath $location)) { continue }
    $version = [string](Get-ItemPropertyValue -LiteralPath $location -Name 'pv' -ErrorAction SilentlyContinue)
    if (-not [string]::IsNullOrWhiteSpace($version) -and $version -ne '0.0.0.0') { return $version }
  }
  return $null
}

$installedVersion = Get-WebView2Version
if (-not [string]::IsNullOrWhiteSpace($installedVersion)) {
  Write-Output "WebView2 Runtime is ready: $installedVersion"
  exit 0
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-webview2-' + [Guid]::NewGuid().ToString('N'))
$bootstrapperPath = Join-Path $temporaryDirectory 'MicrosoftEdgeWebview2Setup.exe'
try {
  [void](New-Item -ItemType Directory -Path $temporaryDirectory)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Write-Output 'Downloading the official Microsoft WebView2 Evergreen Bootstrapper...'
  Invoke-WebRequest -Uri $bootstrapperUri -OutFile $bootstrapperPath -UseBasicParsing

  $signature = Get-AuthenticodeSignature -LiteralPath $bootstrapperPath
  if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
      $null -eq $signature.SignerCertificate -or
      $signature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(,|$)') {
    throw 'The downloaded WebView2 Bootstrapper does not have a valid Microsoft code signature.'
  }

  Write-Output 'Installing the Microsoft WebView2 Runtime...'
  $process = Start-Process -FilePath $bootstrapperPath -ArgumentList @('/silent', '/install') -PassThru -Wait
  if ($process.ExitCode -ne 0) {
    throw "The WebView2 Bootstrapper failed with exit code $($process.ExitCode)."
  }
  $installedVersion = Get-WebView2Version
  if ([string]::IsNullOrWhiteSpace($installedVersion)) {
    throw 'WebView2 installation completed, but the Runtime could not be detected.'
  }
  Write-Output "WebView2 Runtime installed: $installedVersion"
} finally {
  if (Test-Path -LiteralPath $temporaryDirectory -PathType Container) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
