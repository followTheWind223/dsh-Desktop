#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$OutputPath,
  [string]$UninstallOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BuildOutputPath {
  param(
    [AllowNull()][string]$Value,
    [Parameter(Mandatory = $true)][string]$DefaultName
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    $Value = Join-Path $PSScriptRoot $DefaultName
  } elseif (-not [System.IO.Path]::IsPathRooted($Value)) {
    $Value = Join-Path $PSScriptRoot $Value
  }
  $fullPath = [System.IO.Path]::GetFullPath($Value)
  $parent = Split-Path -Parent $fullPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "The output directory does not exist: $parent"
  }
  return $fullPath
}

function Build-WindowsExecutable {
  param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$IconPath,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  $arguments = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    ('/win32icon:' + $IconPath),
    '/reference:System.dll',
    '/reference:System.Windows.Forms.dll',
    ('/out:' + $DestinationPath),
    $SourcePath
  )
  & $Compiler @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "C# compilation failed with exit code $LASTEXITCODE for: $SourcePath"
  }

  $hash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Output ("Built:  {0}" -f $DestinationPath)
  Write-Output ("SHA256: {0}" -f $hash)
}

$OutputPath = Get-BuildOutputPath -Value $OutputPath -DefaultName 'DSH-Desktop.exe'
$UninstallOutputPath = Get-BuildOutputPath -Value $UninstallOutputPath -DefaultName 'Uninstall-DSH-Desktop.exe'
if ([string]::Equals($OutputPath, $UninstallOutputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'The launcher and uninstaller output paths must be different.'
}

$launcherSource = Join-Path $PSScriptRoot 'src\DSH-Desktop\Program.cs'
$uninstallerSource = Join-Path $PSScriptRoot 'src\DSH-Desktop\UninstallProgram.cs'
$iconPath = Join-Path $PSScriptRoot 'assets\deepseek-harness.ico'
foreach ($requiredPath in @($launcherSource, $uninstallerSource, $iconPath)) {
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

Build-WindowsExecutable -Compiler $compiler -SourcePath $launcherSource -IconPath $iconPath -DestinationPath $OutputPath
Build-WindowsExecutable -Compiler $compiler -SourcePath $uninstallerSource -IconPath $iconPath -DestinationPath $UninstallOutputPath
Write-Warning 'The executables are not code-signed. Windows SmartScreen may display a warning.'
