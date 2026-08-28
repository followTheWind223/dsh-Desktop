#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'DSH-Desktop.exe'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot $OutputPath
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$sourcePath = Join-Path $PSScriptRoot 'src\DSH-Desktop\Program.cs'
$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
foreach ($requiredPath in @($sourcePath, $iconPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required build input is missing: $requiredPath"
  }
}

$compilerCandidates = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
  throw 'The .NET Framework C# compiler was not found.'
}

$outputParent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
  throw "The output directory does not exist: $outputParent"
}

$arguments = @(
  '/nologo',
  '/target:winexe',
  '/optimize+',
  '/platform:anycpu',
  ('/win32icon:' + $iconPath),
  '/reference:System.dll',
  '/reference:System.Windows.Forms.dll',
  ('/out:' + $OutputPath),
  $sourcePath
)
& $compiler @arguments
if ($LASTEXITCODE -ne 0) {
  throw "C# compilation failed with exit code $LASTEXITCODE."
}

$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output ("Built:  {0}" -f $OutputPath)
Write-Output ("SHA256: {0}" -f $hash)
Write-Warning 'The executable is not code-signed. Windows SmartScreen may display a warning.'
