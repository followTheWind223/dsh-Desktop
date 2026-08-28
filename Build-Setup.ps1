#Requires -Version 5.1

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PayloadDirectory,
  [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$payloadRoot = [System.IO.Path]::GetFullPath($PayloadDirectory).TrimEnd('\')
if (-not (Test-Path -LiteralPath $payloadRoot -PathType Container)) { throw "PayloadDirectory does not exist: $payloadRoot" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot 'DSH-Setup.exe' }
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot $OutputPath }
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { throw "Output directory does not exist: $outputParent" }

$embeddedPayload = @(
  'DSH-Desktop.exe', 'DSH-Desktop.exe.config', 'Uninstall-DSH-Desktop.exe',
  'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll',
  'runtimes\win-x86\native\WebView2Loader.dll',
  'runtimes\win-x64\native\WebView2Loader.dll',
  'runtimes\win-arm64\native\WebView2Loader.dll',
  'Setup-GUI.ps1', 'Setup.ps1', 'Install.ps1', 'Ensure-WebView2.ps1', 'Uninstall.ps1',
  'CHANGELOG.md', 'LICENSE', 'README.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'VERSION',
  'assets\deepseek-harness.ico', 'assets\deepseek-harness.svg'
)
foreach ($relative in $embeddedPayload) {
  if (-not (Test-Path -LiteralPath (Join-Path $payloadRoot $relative) -PathType Leaf)) { throw "Installer payload is missing: $relative" }
}

$sourcePath = Join-Path $PSScriptRoot 'src\DSH-Setup\SetupProgram.cs'
$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
foreach ($required in @($sourcePath, $iconPath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Build input is missing: $required" }
}

$temporaryArchive = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-payload-' + [Guid]::NewGuid().ToString('N') + '.zip')
try {
  $archive = [System.IO.Compression.ZipFile]::Open($temporaryArchive, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($relativePath in $embeddedPayload) {
      $file = Get-Item -LiteralPath (Join-Path $payloadRoot $relativePath)
      $relative = $relativePath.Replace('\', '/')
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,
        $file.FullName,
        $relative,
        [System.IO.Compression.CompressionLevel]::Optimal
      )
    }
  } finally {
    $archive.Dispose()
  }

  $compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
  )
  $compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($compiler)) { throw 'The .NET Framework C# compiler was not found.' }

  $arguments = @(
    '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
    ('/win32icon:' + $iconPath),
    '/reference:System.dll',
    '/reference:System.Windows.Forms.dll',
    '/reference:System.IO.Compression.dll',
    '/reference:System.IO.Compression.FileSystem.dll',
    ('/resource:' + $temporaryArchive + ',DSHDesktop.Payload.zip'),
    ('/out:' + $OutputPath),
    $sourcePath
  )
  & $compiler @arguments
  if ($LASTEXITCODE -ne 0) { throw "DSH-Setup.exe compilation failed with exit code $LASTEXITCODE." }
  Write-Output "Built setup: $OutputPath"
  Write-Output ("SHA256:     {0}" -f (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant())
} finally {
  if (Test-Path -LiteralPath $temporaryArchive -PathType Leaf) { Remove-Item -LiteralPath $temporaryArchive -Force }
}
