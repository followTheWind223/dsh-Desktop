#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$OutputDirectory,
  [string]$DotNetPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = $PSScriptRoot }
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $PSScriptRoot $OutputDirectory }
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $outputRoot -Force) }

if ([string]::IsNullOrWhiteSpace($DotNetPath)) {
  $dotnetCommand = Get-Command dotnet.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $dotnetCommand) { $DotNetPath = $dotnetCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($DotNetPath) -or -not (Test-Path -LiteralPath $DotNetPath -PathType Leaf)) {
  throw '.NET SDK 8 was not found. Install the SDK or pass -DotNetPath.'
}

$projectPath = Join-Path $PSScriptRoot 'src\DSH-Desktop\DSH-Desktop.csproj'
$uninstallerSource = Join-Path $PSScriptRoot 'src\DSH-Desktop\UninstallProgram.cs'
$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
foreach ($required in @($projectPath, $uninstallerSource, $iconPath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required build input is missing: $required" }
}

& $DotNetPath restore $projectPath --locked-mode
if ($LASTEXITCODE -ne 0) { throw 'Locked .NET dependency restore failed.' }
& $DotNetPath build $projectPath --configuration Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'DSH-Desktop build failed.' }

$buildRoot = Join-Path $PSScriptRoot 'src\DSH-Desktop\bin\Release\net48'
$managedFiles = @(
  'DSH-Desktop.exe',
  'DSH-Desktop.exe.config',
  'Microsoft.Web.WebView2.Core.dll',
  'Microsoft.Web.WebView2.WinForms.dll'
)
foreach ($relative in $managedFiles) {
  $source = Join-Path $buildRoot $relative
  if ($relative -eq 'DSH-Desktop.exe.config' -and -not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Build output is missing: $relative" }
  Copy-Item -LiteralPath $source -Destination (Join-Path $outputRoot $relative) -Force
}
foreach ($architecture in @('win-x86', 'win-x64', 'win-arm64')) {
  $relative = "runtimes\$architecture\native\WebView2Loader.dll"
  $source = Join-Path $buildRoot $relative
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Build output is missing: $relative" }
  $destination = Join-Path $outputRoot $relative
  [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
  Copy-Item -LiteralPath $source -Destination $destination -Force
}

$compilerCandidates = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) { throw 'The .NET Framework C# compiler was not found.' }
$uninstallerOutput = Join-Path $outputRoot 'Uninstall-DSH-Desktop.exe'
& $compiler @(
  '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
  ('/win32icon:' + $iconPath), '/reference:System.dll', '/reference:System.Drawing.dll',
  '/reference:System.Windows.Forms.dll', '/reference:System.Web.Extensions.dll',
  ('/out:' + $uninstallerOutput), $uninstallerSource
)
if ($LASTEXITCODE -ne 0) { throw 'Uninstaller compilation failed.' }

foreach ($name in @('DSH-Desktop.exe', 'Uninstall-DSH-Desktop.exe')) {
  $path = Join-Path $outputRoot $name
  Write-Output ("Built:  {0}" -f $path)
  Write-Output ("SHA256: {0}" -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())
}
Write-Warning 'The executables are not code-signed. Windows SmartScreen may display a warning.'
