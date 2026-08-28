#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework

function Show-LauncherMessage {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][System.Windows.MessageBoxImage]$Icon
  )

  [System.Windows.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.MessageBoxButton]::OK,
    $Icon
  ) | Out-Null
}

function Protect-DiagnosticText {
  param([AllowEmptyString()][string]$Text)

  if ([string]::IsNullOrEmpty($Text)) { return '' }
  $redacted = [regex]::Replace($Text, '(?i)(\?token=)[^\s]+', '$1<redacted>')
  $redacted = [regex]::Replace($redacted, '(?i)\b(sk-[A-Za-z0-9_-]{16,})\b', '<redacted-api-key>')
  if ($redacted.Length -gt 1200) { return $redacted.Substring(0, 1200) + '...' }
  return $redacted
}

function Get-RequiredConfigPath {
  param(
    [Parameter(Mandatory = $true)][psobject]$Config,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet('Container', 'Leaf')][string]$PathType
  )

  $property = $Config.PSObject.Properties[$Name]
  if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
    throw "The launcher configuration is missing '$Name'."
  }

  $configuredPath = [string]$property.Value
  if (-not [System.IO.Path]::IsPathRooted($configuredPath)) {
    throw "The launcher configuration path '$Name' must be absolute."
  }

  $fullPath = [System.IO.Path]::GetFullPath($configuredPath)
  if (-not (Test-Path -LiteralPath $fullPath -PathType $PathType)) {
    throw "The configured path '$Name' does not exist or has the wrong type: $fullPath"
  }
  return $fullPath
}

function Assert-CompatibleNodeVersion {
  param([Parameter(Mandatory = $true)][string]$NodePath)

  $versionText = (& $NodePath --version 2>&1 | Select-Object -First 1)
  $match = [regex]::Match([string]$versionText, '^v(?<major>\d+)\.(?<minor>\d+)\.')
  if (-not $match.Success) {
    throw "Unable to read the configured Node.js version from: $NodePath"
  }

  $major = [int]$match.Groups['major'].Value
  $minor = [int]$match.Groups['minor'].Value
  $supported = ($major -eq 22 -and $minor -ge 19) -or $major -ge 24
  if (-not $supported) {
    throw "DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0. Configured version: $versionText"
  }
}

function Get-LauncherEdgeProcesses {
  param([Parameter(Mandatory = $true)][string]$ProfileDir)

  $needle = '--user-data-dir=' + $ProfileDir
  return @(
    Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $commandLine = [string]$_.CommandLine
        -not [string]::IsNullOrEmpty($commandLine) -and
          $commandLine.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
      }
  )
}

function Get-ProcessTreeIds {
  param([Parameter(Mandatory = $true)][int]$RootProcessId)

  $seen = New-Object 'System.Collections.Generic.HashSet[int]'
  $queue = New-Object 'System.Collections.Generic.Queue[int]'
  $ordered = New-Object 'System.Collections.Generic.List[int]'
  [void]$seen.Add($RootProcessId)
  $queue.Enqueue($RootProcessId)

  while ($queue.Count -gt 0) {
    $parentId = $queue.Dequeue()
    $children = @(
      Get-CimInstance Win32_Process -Filter ("ParentProcessId = {0}" -f $parentId) -ErrorAction SilentlyContinue
    )
    foreach ($child in $children) {
      $childId = [int]$child.ProcessId
      if ($seen.Add($childId)) {
        $queue.Enqueue($childId)
        $ordered.Add($childId)
      }
    }
  }

  $ordered.Reverse()
  $ordered.Add($RootProcessId)
  return $ordered.ToArray()
}

function Stop-OwnedBackend {
  param(
    [AllowNull()][System.Diagnostics.Process]$Process,
    [AllowNull()][string]$ExpectedExecutable
  )

  if ($null -eq $Process -or [string]::IsNullOrWhiteSpace($ExpectedExecutable)) { return }
  try { $Process.Refresh() } catch { return }
  if ($Process.HasExited) { return }

  $actualExecutable = $null
  try { $actualExecutable = $Process.MainModule.FileName } catch { return }
  if (-not [string]::Equals(
      [System.IO.Path]::GetFullPath($actualExecutable),
      [System.IO.Path]::GetFullPath($ExpectedExecutable),
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    return
  }

  foreach ($processId in (Get-ProcessTreeIds -RootProcessId $Process.Id)) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
  }
}

function Stop-OwnedEdgeProcesses {
  param([AllowNull()][string]$ProfileDir)

  if ([string]::IsNullOrWhiteSpace($ProfileDir)) { return }
  foreach ($edgeProcess in (Get-LauncherEdgeProcesses -ProfileDir $ProfileDir)) {
    Stop-Process -Id ([int]$edgeProcess.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

function Remove-OwnedEdgeProfile {
  param(
    [AllowNull()][string]$ProfileDir,
    [AllowNull()][string]$StateDir
  )

  if ([string]::IsNullOrWhiteSpace($ProfileDir) -or [string]::IsNullOrWhiteSpace($StateDir)) { return }
  if (-not (Test-Path -LiteralPath $ProfileDir -PathType Container)) { return }

  $resolvedProfile = [System.IO.Path]::GetFullPath($ProfileDir)
  $resolvedState = [System.IO.Path]::GetFullPath($StateDir).TrimEnd('\') + '\'
  $expectedLeaf = 'edge-profile-' + $PID
  if (-not $resolvedProfile.StartsWith($resolvedState, [System.StringComparison]::OrdinalIgnoreCase)) { return }
  if (-not [string]::Equals(
      (Split-Path -Leaf $resolvedProfile),
      $expectedLeaf,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    return
  }
  Remove-Item -LiteralPath $resolvedProfile -Recurse -Force -ErrorAction SilentlyContinue
}

$mutex = $null
$ownsMutex = $false
$backend = $null
$stderrTask = $null
$launchFailure = $null
$nodePath = $null
$launcherStateDir = $null
$edgeProfileDir = $null

try {
  $configPath = Join-Path $PSScriptRoot 'launcher.config.json'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Launcher configuration not found. Run Install.ps1 first: $configPath"
  }

  try {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  } catch {
    throw "Launcher configuration is not valid JSON: $configPath"
  }

  $installDir = Get-RequiredConfigPath -Config $config -Name 'HarnessDir' -PathType Container
  $dataDir = Get-RequiredConfigPath -Config $config -Name 'DataDir' -PathType Container
  $nodePath = Get-RequiredConfigPath -Config $config -Name 'NodePath' -PathType Leaf
  $edgePath = Get-RequiredConfigPath -Config $config -Name 'EdgePath' -PathType Leaf
  if (-not [string]::Equals((Split-Path -Leaf $nodePath), 'node.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The configured NodePath must point to node.exe: $nodePath"
  }
  if (-not [string]::Equals((Split-Path -Leaf $edgePath), 'msedge.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The configured EdgePath must point to msedge.exe: $edgePath"
  }
  $nodeDir = Split-Path -Parent $nodePath
  $entryPath = Join-Path $installDir 'apps\cli\src\bin.ts'
  $webBuildPath = Join-Path $installDir 'apps\web\dist\index.html'
  $tsxPath = Join-Path $installDir 'node_modules\tsx'
  foreach ($requiredPath in @($entryPath, $webBuildPath, $tsxPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "The Harness source checkout is not installed and built: $requiredPath"
    }
  }
  Assert-CompatibleNodeVersion -NodePath $nodePath

  $launcherStateDir = Join-Path $dataDir 'desktop-launcher'
  $edgeProfileDir = Join-Path $launcherStateDir ("edge-profile-{0}" -f $PID)

  $createdNew = $false
  $mutex = [System.Threading.Mutex]::new(
    $true,
    # Keep the legacy name so an in-place upgrade cannot run beside an older launcher.
    'Local\DeepSeekHarnessOfficialDesktopLauncher',
    [ref]$createdNew
  )
  if (-not $createdNew) {
    Show-LauncherMessage -Title 'DeepSeek Harness' -Message 'The DeepSeek Harness desktop window is already running.' -Icon Information
    return
  }
  $ownsMutex = $true

  New-Item -ItemType Directory -Path $launcherStateDir -Force | Out-Null
  New-Item -ItemType Directory -Path $edgeProfileDir -Force | Out-Null

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $nodePath
  $startInfo.Arguments = '--import tsx/esm apps/cli/src/bin.ts web --no-open --host 127.0.0.1 --port 0'
  $startInfo.WorkingDirectory = $installDir
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.EnvironmentVariables['PATH'] = $nodeDir + ';' + $startInfo.EnvironmentVariables['PATH']
  $startInfo.EnvironmentVariables['DSH_HOME'] = $dataDir
  $startInfo.EnvironmentVariables['NO_COLOR'] = '1'

  $backend = New-Object System.Diagnostics.Process
  $backend.StartInfo = $startInfo
  if (-not $backend.Start()) { throw 'Unable to start the DeepSeek Harness backend process.' }

  $stderrTask = $backend.StandardError.ReadLineAsync()
  $stdoutTask = $backend.StandardOutput.ReadLineAsync()
  $startupDeadline = [DateTime]::UtcNow.AddSeconds(75)
  $launchUrl = $null
  $diagnostics = New-Object 'System.Collections.Generic.List[string]'

  while ([DateTime]::UtcNow -lt $startupDeadline) {
    if ($stdoutTask.Wait(150)) {
      $line = $stdoutTask.Result
      if ($null -eq $line) { break }

      $urlMatch = [regex]::Match(
        $line,
        '(?<url>http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_-]{20,256})'
      )
      if ($urlMatch.Success) {
        $candidate = [Uri]$urlMatch.Groups['url'].Value
        $isTrustedUrl =
          $candidate.Scheme -eq 'http' -and
          $candidate.Host -eq '127.0.0.1' -and
          $candidate.Port -ge 1 -and
          $candidate.Port -le 65535 -and
          $candidate.AbsolutePath -eq '/' -and
          $candidate.Query -match '^\?token=[A-Za-z0-9_-]{20,256}$'
        if (-not $isTrustedUrl) { throw 'Harness returned an untrusted launch URL.' }
        $launchUrl = $candidate.AbsoluteUri
        $stdoutTask = $backend.StandardOutput.ReadLineAsync()
        break
      }

      if ($diagnostics.Count -lt 8) {
        $safeLine = Protect-DiagnosticText -Text $line
        if (-not [string]::IsNullOrWhiteSpace($safeLine)) { $diagnostics.Add($safeLine) }
      }
      $stdoutTask = $backend.StandardOutput.ReadLineAsync()
    }

    while ($null -ne $stderrTask -and $stderrTask.IsCompleted) {
      $errorLine = $stderrTask.Result
      if ($null -eq $errorLine) {
        $stderrTask = $null
      } else {
        if ($diagnostics.Count -lt 8) {
          $safeErrorLine = Protect-DiagnosticText -Text $errorLine
          if (-not [string]::IsNullOrWhiteSpace($safeErrorLine)) { $diagnostics.Add($safeErrorLine) }
        }
        $stderrTask = $backend.StandardError.ReadLineAsync()
      }
    }

    $backend.Refresh()
    if ($backend.HasExited) { break }
  }

  if ($null -eq $launchUrl) {
    $backend.Refresh()
    $detail = ($diagnostics -join [Environment]::NewLine)
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'The backend did not produce a loopback URL before the startup timeout.' }
    throw "DeepSeek Harness failed to start.`n`n$detail"
  }

  $edgeArguments = '"--app={0}" "--user-data-dir={1}" --no-first-run --no-default-browser-check --disable-background-mode --disable-sync --disable-extensions' -f $launchUrl, $edgeProfileDir
  $edgeStarter = Start-Process -FilePath $edgePath -ArgumentList $edgeArguments -PassThru

  $windowSeen = $false
  $noWindowSince = $null
  $windowDeadline = [DateTime]::UtcNow.AddSeconds(35)
  while ($true) {
    Start-Sleep -Milliseconds 350

    while ($null -ne $stdoutTask -and $stdoutTask.IsCompleted) {
      $discardedOutput = $stdoutTask.Result
      if ($null -eq $discardedOutput) {
        $stdoutTask = $null
      } else {
        $stdoutTask = $backend.StandardOutput.ReadLineAsync()
      }
    }
    while ($null -ne $stderrTask -and $stderrTask.IsCompleted) {
      $discardedError = $stderrTask.Result
      if ($null -eq $discardedError) {
        $stderrTask = $null
      } else {
        $stderrTask = $backend.StandardError.ReadLineAsync()
      }
    }

    $backend.Refresh()
    if ($backend.HasExited) {
      throw 'The DeepSeek Harness backend exited unexpectedly.'
    }

    $edgeProcesses = @(Get-LauncherEdgeProcesses -ProfileDir $edgeProfileDir)
    $windowPresent = $false
    foreach ($edgeProcess in $edgeProcesses) {
      $nativeProcess = Get-Process -Id ([int]$edgeProcess.ProcessId) -ErrorAction SilentlyContinue
      if ($null -ne $nativeProcess -and $nativeProcess.MainWindowHandle -ne [IntPtr]::Zero) {
        $windowPresent = $true
        break
      }
    }

    if ($windowPresent) {
      $windowSeen = $true
      $noWindowSince = $null
      continue
    }

    if ($windowSeen) {
      if ($null -eq $noWindowSince) { $noWindowSince = [DateTime]::UtcNow }
      if (([DateTime]::UtcNow - $noWindowSince).TotalSeconds -ge 1.5) { break }
      continue
    }

    if ([DateTime]::UtcNow -ge $windowDeadline) {
      throw 'The Edge application window did not appear before the startup timeout.'
    }
    if ($edgeStarter.HasExited -and $edgeProcesses.Count -eq 0) {
      throw 'Edge exited immediately after launch.'
    }
  }
} catch {
  $launchFailure = Protect-DiagnosticText -Text $_.Exception.Message
} finally {
  Stop-OwnedEdgeProcesses -ProfileDir $edgeProfileDir
  Stop-OwnedBackend -Process $backend -ExpectedExecutable $nodePath
  Remove-OwnedEdgeProfile -ProfileDir $edgeProfileDir -StateDir $launcherStateDir
  if ($ownsMutex -and $null -ne $mutex) {
    try { $mutex.ReleaseMutex() } catch { }
  }
  if ($null -ne $mutex) { $mutex.Dispose() }
}

if (-not [string]::IsNullOrWhiteSpace($launchFailure)) {
  Show-LauncherMessage -Title 'DeepSeek Harness launch failed' -Message $launchFailure -Icon Error
  exit 1
}
