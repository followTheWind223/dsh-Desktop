#Requires -Version 5.1

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PayloadRoot,
  [Parameter(Mandatory = $true)][string]$SetupExecutable,
  [string]$PortableDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-LocalAbsolutePath {
  param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Name)
  if ([string]::IsNullOrWhiteSpace($Value) -or -not [System.IO.Path]::IsPathRooted($Value)) { throw "$Name must be an absolute path." }
  $full = [System.IO.Path]::GetFullPath($Value)
  if ($full.StartsWith('\\', [System.StringComparison]::Ordinal)) { throw "$Name cannot be a network path." }
  return $full.TrimEnd('\')
}

function Quote-ProcessArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value.IndexOf('"') -ge 0) { throw 'A selected path contains an unsupported quote character.' }
  return '"' + $Value + '"'
}

function ConvertTo-PowerShellLiteral {
  param([Parameter(Mandatory = $true)][string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Test-SamePath {
  param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)
  return [string]::Equals(
    [System.IO.Path]::GetFullPath($Left).TrimEnd('\'),
    [System.IO.Path]::GetFullPath($Right).TrimEnd('\'),
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Copy-LauncherPayload {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$InstallerExecutable
  )

  $SourceRoot = Get-LocalAbsolutePath -Value $SourceRoot -Name 'PayloadRoot'
  $Destination = Get-LocalAbsolutePath -Value $Destination -Name 'LauncherDir'
  if (Test-SamePath -Left $SourceRoot -Right $Destination) { return }

  $files = @(
    'DSH-Desktop.exe',
    'Uninstall-DSH-Desktop.exe',
    'Microsoft.Web.WebView2.Core.dll',
    'Microsoft.Web.WebView2.WinForms.dll',
    'runtimes\win-x86\native\WebView2Loader.dll',
    'runtimes\win-x64\native\WebView2Loader.dll',
    'runtimes\win-arm64\native\WebView2Loader.dll',
    'Install.ps1',
    'Setup.ps1',
    'Setup-GUI.ps1',
    'Ensure-WebView2.ps1',
    'Uninstall.ps1',
    'VERSION',
    'LICENSE',
    'README.md',
    'SECURITY.md',
    'THIRD_PARTY_NOTICES.md',
    'assets\deepseek-harness.ico',
    'assets\deepseek-harness.svg'
  )
  foreach ($relative in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $relative) -PathType Leaf)) {
      throw "The installer payload is incomplete: $relative"
    }
  }
  if (-not (Test-Path -LiteralPath $InstallerExecutable -PathType Leaf)) { throw 'The setup executable is missing.' }

  if (Test-Path -LiteralPath $Destination -PathType Leaf) { throw "The application destination is a file: $Destination" }
  if (Test-Path -LiteralPath $Destination -PathType Container) {
    $items = @(Get-ChildItem -LiteralPath $Destination -Force)
    $isExistingLauncher =
      (Test-Path -LiteralPath (Join-Path $Destination 'VERSION') -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $Destination 'DSH-Desktop.exe') -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $Destination 'Install.ps1') -PathType Leaf)
    if ($items.Count -gt 0 -and -not $isExistingLauncher) {
      throw "Refusing to overwrite an unrelated non-empty application folder: $Destination"
    }
  } else {
    [void](New-Item -ItemType Directory -Path $Destination -Force)
  }

  foreach ($relative in $files) {
    $source = Join-Path $SourceRoot $relative
    $target = Join-Path $Destination $relative
    $targetParent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
      [void](New-Item -ItemType Directory -Path $targetParent -Force)
    }
    $temporaryTarget = $target + '.new-' + [Guid]::NewGuid().ToString('N')
    $backupTarget = $null
    try {
      Copy-Item -LiteralPath $source -Destination $temporaryTarget -Force
      if (Test-Path -LiteralPath $target -PathType Leaf) {
        $backupTarget = $target + '.bak-' + [Guid]::NewGuid().ToString('N')
        [System.IO.File]::Replace($temporaryTarget, $target, $backupTarget)
        Remove-Item -LiteralPath $backupTarget -Force
      } else {
        [System.IO.File]::Move($temporaryTarget, $target)
      }
    } finally {
      if (Test-Path -LiteralPath $temporaryTarget -PathType Leaf) { Remove-Item -LiteralPath $temporaryTarget -Force }
      if (-not [string]::IsNullOrWhiteSpace($backupTarget) -and (Test-Path -LiteralPath $backupTarget -PathType Leaf)) { Remove-Item -LiteralPath $backupTarget -Force }
    }
  }

  $setupTarget = Join-Path $Destination 'DSH-Setup.exe'
  if (-not (Test-SamePath -Left $InstallerExecutable -Right $setupTarget)) {
    $temporarySetup = $setupTarget + '.new-' + [Guid]::NewGuid().ToString('N')
    $backupSetup = $null
    try {
      Copy-Item -LiteralPath $InstallerExecutable -Destination $temporarySetup -Force
      if (Test-Path -LiteralPath $setupTarget -PathType Leaf) {
        $backupSetup = $setupTarget + '.bak-' + [Guid]::NewGuid().ToString('N')
        [System.IO.File]::Replace($temporarySetup, $setupTarget, $backupSetup)
        Remove-Item -LiteralPath $backupSetup -Force
      } else {
        [System.IO.File]::Move($temporarySetup, $setupTarget)
      }
    } finally {
      if (Test-Path -LiteralPath $temporarySetup -PathType Leaf) { Remove-Item -LiteralPath $temporarySetup -Force }
      if (-not [string]::IsNullOrWhiteSpace($backupSetup) -and (Test-Path -LiteralPath $backupSetup -PathType Leaf)) { Remove-Item -LiteralPath $backupSetup -Force }
    }
  }
}

function Invoke-EnvironmentInspection {
  param([Parameter(Mandatory = $true)][string]$RootPath)
  $scriptPath = Join-Path $PayloadRoot 'Setup.ps1'
  $powerShell = Join-Path $PSHOME 'powershell.exe'
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $powerShell
  $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (Quote-ProcessArgument $scriptPath) +
    ' -DestinationRoot ' + (Quote-ProcessArgument $RootPath) + ' -NonInteractive -Inspect'
  $startInfo.WorkingDirectory = $PayloadRoot
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::Start($startInfo)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw (($stderr + [Environment]::NewLine + $stdout).Trim()) }
  return $stdout | ConvertFrom-Json
}

$PayloadRoot = Get-LocalAbsolutePath -Value $PayloadRoot -Name 'PayloadRoot'
$SetupExecutable = Get-LocalAbsolutePath -Value $SetupExecutable -Name 'SetupExecutable'
if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot 'Setup.ps1') -PathType Leaf)) { throw 'Setup.ps1 is missing from the installer payload.' }

$isChineseSystem = [System.Globalization.CultureInfo]::CurrentUICulture.Name.StartsWith('zh', [System.StringComparison]::OrdinalIgnoreCase)
$script:useChinese = $isChineseSystem
$script:inspection = $null
$script:activeProcess = $null
$script:outputPath = $null
$script:errorPath = $null
$script:lastOutputLength = 0
$script:lastErrorLength = 0
$script:launcherDir = $null

function T([string]$Chinese, [string]$English) { if ($script:useChinese) { return $Chinese } return $English }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DSH Desktop Setup'
$form.ClientSize = New-Object System.Drawing.Size(780, 640)
$form.MinimumSize = New-Object System.Drawing.Size(796, 679)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 252)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Icon = New-Object System.Drawing.Icon((Join-Path $PayloadRoot 'assets\deepseek-harness.ico'))

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 92
$header.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Location = New-Object System.Drawing.Point(28, 18)
$title.AutoSize = $true
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$title.ForeColor = [System.Drawing.Color]::FromArgb(24, 34, 51)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Location = New-Object System.Drawing.Point(31, 57)
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(92, 104, 121)
$header.Controls.Add($subtitle)

$languageCombo = New-Object System.Windows.Forms.ComboBox
$languageCombo.DropDownStyle = 'DropDownList'
$languageCombo.Location = New-Object System.Drawing.Point(610, 28)
$languageCombo.Width = 140
[void]$languageCombo.Items.AddRange(@('自动 / Auto', '简体中文', 'English'))
$languageCombo.SelectedIndex = 0
$header.Controls.Add($languageCombo)

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.Padding = New-Object System.Windows.Forms.Padding(28, 18, 28, 18)
$form.Controls.Add($content)
$content.BringToFront()

$rootLabel = New-Object System.Windows.Forms.Label
$rootLabel.Location = New-Object System.Drawing.Point(30, 20)
$rootLabel.AutoSize = $true
$rootLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$content.Controls.Add($rootLabel)

$rootBox = New-Object System.Windows.Forms.TextBox
$rootBox.Location = New-Object System.Drawing.Point(30, 45)
$rootBox.Width = 585
$rootBox.Height = 28
$content.Controls.Add($rootBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Location = New-Object System.Drawing.Point(625, 43)
$browseButton.Size = New-Object System.Drawing.Size(92, 30)
$browseButton.FlatStyle = 'System'
$content.Controls.Add($browseButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = New-Object System.Drawing.Point(625, 82)
$refreshButton.Size = New-Object System.Drawing.Size(92, 30)
$content.Controls.Add($refreshButton)

$destinationHint = New-Object System.Windows.Forms.Label
$destinationHint.Location = New-Object System.Drawing.Point(31, 80)
$destinationHint.Size = New-Object System.Drawing.Size(575, 34)
$destinationHint.ForeColor = [System.Drawing.Color]::FromArgb(92, 104, 121)
$content.Controls.Add($destinationHint)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(30, 124)
$statusPanel.Size = New-Object System.Drawing.Size(687, 104)
$statusPanel.BackColor = [System.Drawing.Color]::White
$statusPanel.BorderStyle = 'FixedSingle'
$content.Controls.Add($statusPanel)

$statusTitle = New-Object System.Windows.Forms.Label
$statusTitle.Location = New-Object System.Drawing.Point(16, 12)
$statusTitle.AutoSize = $true
$statusTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$statusPanel.Controls.Add($statusTitle)

$statusBody = New-Object System.Windows.Forms.Label
$statusBody.Location = New-Object System.Drawing.Point(16, 37)
$statusBody.Size = New-Object System.Drawing.Size(650, 58)
$statusBody.ForeColor = [System.Drawing.Color]::FromArgb(68, 78, 94)
$statusPanel.Controls.Add($statusBody)

$nodeLabel = New-Object System.Windows.Forms.Label
$nodeLabel.Location = New-Object System.Drawing.Point(30, 244)
$nodeLabel.AutoSize = $true
$nodeLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$content.Controls.Add($nodeLabel)

$nodeCombo = New-Object System.Windows.Forms.ComboBox
$nodeCombo.DropDownStyle = 'DropDownList'
$nodeCombo.Location = New-Object System.Drawing.Point(30, 269)
$nodeCombo.Width = 390
[void]$nodeCombo.Items.AddRange(@('Auto', 'Download', 'Choose'))
$nodeCombo.SelectedIndex = 0
$content.Controls.Add($nodeCombo)

$nodePathBox = New-Object System.Windows.Forms.TextBox
$nodePathBox.Location = New-Object System.Drawing.Point(430, 269)
$nodePathBox.Width = 230
$nodePathBox.Enabled = $false
$content.Controls.Add($nodePathBox)

$nodeBrowseButton = New-Object System.Windows.Forms.Button
$nodeBrowseButton.Location = New-Object System.Drawing.Point(666, 267)
$nodeBrowseButton.Size = New-Object System.Drawing.Size(51, 29)
$nodeBrowseButton.Enabled = $false
$content.Controls.Add($nodeBrowseButton)

$desktopShortcut = New-Object System.Windows.Forms.CheckBox
$desktopShortcut.Location = New-Object System.Drawing.Point(30, 312)
$desktopShortcut.AutoSize = $true
$desktopShortcut.Checked = $true
$content.Controls.Add($desktopShortcut)

$startShortcut = New-Object System.Windows.Forms.CheckBox
$startShortcut.Location = New-Object System.Drawing.Point(260, 312)
$startShortcut.AutoSize = $true
$startShortcut.Checked = $true
$content.Controls.Add($startShortcut)

$launchAfter = New-Object System.Windows.Forms.CheckBox
$launchAfter.Location = New-Object System.Drawing.Point(500, 312)
$launchAfter.AutoSize = $true
$launchAfter.Checked = $true
$content.Controls.Add($launchAfter)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(30, 348)
$logBox.Size = New-Object System.Drawing.Size(687, 112)
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = [System.Drawing.Color]::FromArgb(251, 252, 254)
$logBox.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$content.Controls.Add($logBox)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(30, 475)
$progress.Size = New-Object System.Drawing.Size(520, 18)
$content.Controls.Add($progress)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Location = New-Object System.Drawing.Point(565, 468)
$installButton.Size = New-Object System.Drawing.Size(152, 34)
$installButton.BackColor = [System.Drawing.Color]::FromArgb(36, 99, 235)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.FlatStyle = 'Flat'
$installButton.FlatAppearance.BorderSize = 0
$content.Controls.Add($installButton)

$privacy = New-Object System.Windows.Forms.Label
$privacy.Location = New-Object System.Drawing.Point(30, 510)
$privacy.Size = New-Object System.Drawing.Size(687, 38)
$privacy.ForeColor = [System.Drawing.Color]::FromArgb(92, 104, 121)
$content.Controls.Add($privacy)

function Set-LocalizedText {
  $title.Text = T '安装 DeepSeek Harness 桌面端' 'Install DeepSeek Harness Desktop'
  $subtitle.Text = T '复用现有环境；缺少的组件才会下载。' 'Reuse what is already installed; download only what is missing.'
  $rootLabel.Text = T '安装区域' 'Installation location'
  $browseButton.Text = T '浏览…' 'Browse…'
  $refreshButton.Text = T '重新检测' 'Detect again'
  $statusTitle.Text = T '环境检测' 'Environment check'
  $nodeLabel.Text = T 'Node.js 选择' 'Node.js choice'
  $desktopShortcut.Text = T '创建桌面快捷方式' 'Create desktop shortcut'
  $startShortcut.Text = T '添加到开始菜单' 'Add to Start menu'
  $launchAfter.Text = T '安装后启动' 'Launch when finished'
  $nodeBrowseButton.Text = '…'
  $privacy.Text = T '不会修改系统 PATH，不会读取或保存 API Key。现有 Harness、Node 与用户数据默认不会被覆盖或删除。' 'Does not modify system PATH or read/save API keys. Existing Harness, Node, and user data are preserved by default.'
  $installButton.Text = T '安装 / 配置' 'Install / Configure'
  $nodeCombo.Items.Clear()
  [void]$nodeCombo.Items.Add((T '自动复用兼容版本（推荐）' 'Reuse a compatible version automatically (recommended)'))
  [void]$nodeCombo.Items.Add((T '下载官方便携版 Node.js' 'Download official portable Node.js'))
  [void]$nodeCombo.Items.Add((T '选择已有 node.exe' 'Choose an existing node.exe'))
  if ($nodeCombo.SelectedIndex -lt 0) { $nodeCombo.SelectedIndex = 0 }
  Update-DestinationHint
  Update-StatusText
}

function Get-SelectedRoot { return Get-LocalAbsolutePath -Value $rootBox.Text -Name 'DestinationRoot' }

function Get-LauncherDirectory {
  $root = Get-SelectedRoot
  if (-not [string]::IsNullOrWhiteSpace($PortableDir)) { return Get-LocalAbsolutePath -Value $PortableDir -Name 'PortableDir' }
  return Join-Path $root 'dsh-desktop'
}

function Update-DestinationHint {
  try {
    $launcher = Get-LauncherDirectory
    $destinationHint.Text = (T '桌面程序：{0}   Harness：{1}' 'Desktop app: {0}   Harness: {1}') -f $launcher, (Join-Path (Get-SelectedRoot) 'deepseek-harness')
  } catch {
    $destinationHint.Text = $_.Exception.Message
  }
}

function Update-StatusText {
  if ($null -eq $script:inspection) {
    $statusBody.Text = T '选择安装区域后点击“重新检测”。' 'Choose a location, then select “Detect again”.'
    return
  }
  $harnessText = switch ([string]$script:inspection.Harness.State) {
    'Ready' { T '已安装且可直接复用' 'ready and will be reused' }
    'Source' { T '已有可信源码，需要完成构建' 'trusted source found; build required' }
    'Missing' { T '未安装，将下载官方仓库' 'missing; official repository will be downloaded' }
    default { T ('不可使用：' + [string]$script:inspection.Harness.Reason) ('cannot be used: ' + [string]$script:inspection.Harness.Reason) }
  }
  $nodeText = if ($null -ne $script:inspection.CompatibleNode) {
    (T '复用 {0}（{1}）' 'reuse {0} ({1})') -f $script:inspection.CompatibleNode.Path, $script:inspection.CompatibleNode.Version
  } else { T '未找到兼容版本' 'no compatible version found' }
  $webViewText = if ($script:inspection.WebView2.Available) {
    (T '已就绪 {0}' 'ready {0}') -f $script:inspection.WebView2.Version
  } else { T '缺失，将安装微软官方运行库' 'missing; Microsoft runtime will be installed' }
  $statusBody.Text = (T "Harness：{0}`r`nNode.js：{1}`r`nWebView2：{2}" "Harness: {0}`r`nNode.js: {1}`r`nWebView2: {2}") -f $harnessText, $nodeText, $webViewText
}

function Refresh-Inspection {
  try {
    $refreshButton.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $script:inspection = Invoke-EnvironmentInspection -RootPath (Get-SelectedRoot)
    Update-StatusText
  } catch {
    $script:inspection = $null
    $statusBody.Text = (T '检测失败：' 'Detection failed: ') + $_.Exception.Message
  } finally {
    $refreshButton.Enabled = $true
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
  }
}

function Append-NewLogText {
  param([AllowNull()][string]$Path, [ref]$PreviousLength)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $stream = New-Object System.IO.FileStream(
    $Path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
  )
  try {
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally {
    $stream.Dispose()
  }
  if ($text.Length -le $PreviousLength.Value) { return }
  $newText = $text.Substring($PreviousLength.Value)
  $PreviousLength.Value = $text.Length
  $logBox.AppendText($newText.Replace("`n", "`r`n").Replace("`r`r`n", "`r`n"))
}

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 500
$pollTimer.Add_Tick({
  try {
  Append-NewLogText -Path $script:outputPath -PreviousLength ([ref]$script:lastOutputLength)
  Append-NewLogText -Path $script:errorPath -PreviousLength ([ref]$script:lastErrorLength)
  if ($null -eq $script:activeProcess -or -not $script:activeProcess.HasExited) { return }
  $pollTimer.Stop()
  Append-NewLogText -Path $script:outputPath -PreviousLength ([ref]$script:lastOutputLength)
  Append-NewLogText -Path $script:errorPath -PreviousLength ([ref]$script:lastErrorLength)
  $exitCode = $script:activeProcess.ExitCode
  $script:activeProcess.Dispose()
  $script:activeProcess = $null
  $progress.Style = 'Blocks'
  $progress.Value = if ($exitCode -eq 0) { 100 } else { 0 }
  $installButton.Enabled = $true
  $browseButton.Enabled = $true
  $refreshButton.Enabled = $true
  if ($exitCode -eq 0) {
    $logBox.AppendText((T "`r`n完成。`r`n" "`r`nCompleted.`r`n"))
    [System.Windows.Forms.MessageBox]::Show(
      (T "DSH Desktop 已配置完成。`r`n`r`n应用目录：$script:launcherDir" "DSH Desktop is ready.`r`n`r`nApplication folder: $script:launcherDir"),
      'DSH Desktop',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    if ($launchAfter.Checked) { Start-Process -FilePath (Join-Path $script:launcherDir 'DSH-Desktop.exe') -WorkingDirectory $script:launcherDir }
    $form.Close()
  } else {
    [System.Windows.Forms.MessageBox]::Show(
      (T '安装没有完成，请查看窗口中的日志。' 'Setup did not complete. Review the log in this window.'),
      'DSH Desktop',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
  }
  foreach ($temporary in @($script:outputPath, $script:errorPath)) {
    if (-not [string]::IsNullOrWhiteSpace($temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
  }
  } catch {
    $pollTimer.Stop()
    $progress.Style = 'Blocks'
    $progress.Value = 0
    $installButton.Enabled = $true
    $browseButton.Enabled = $true
    $refreshButton.Enabled = $true
    $logBox.AppendText("`r`nUI error: " + $_.Exception.Message + "`r`n")
  }
})

$browseButton.Add_Click({
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  try {
    $dialog.Description = T '选择用于存放桌面端、Harness、数据和可选便携 Node.js 的区域。' 'Choose where the desktop app, Harness, data, and optional portable Node.js will be stored.'
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $rootBox.Text -PathType Container) { $dialog.SelectedPath = $rootBox.Text }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
      $rootBox.Text = $dialog.SelectedPath
      Update-DestinationHint
      Refresh-Inspection
    }
  } finally { $dialog.Dispose() }
})

$refreshButton.Add_Click({ Update-DestinationHint; Refresh-Inspection })
$rootBox.Add_Leave({ Update-DestinationHint })
$languageCombo.Add_SelectedIndexChanged({
  $script:useChinese = if ($languageCombo.SelectedIndex -eq 1) { $true } elseif ($languageCombo.SelectedIndex -eq 2) { $false } else { $isChineseSystem }
  Set-LocalizedText
})
$nodeCombo.Add_SelectedIndexChanged({
  $choose = ($nodeCombo.SelectedIndex -eq 2)
  $nodePathBox.Enabled = $choose
  $nodeBrowseButton.Enabled = $choose
})
$nodeBrowseButton.Add_Click({
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  try {
    $dialog.Title = T '选择兼容的 node.exe' 'Choose a compatible node.exe'
    $dialog.Filter = 'Node.js executable (node.exe)|node.exe'
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $nodePathBox.Text = $dialog.FileName }
  } finally { $dialog.Dispose() }
})

$installButton.Add_Click({
  try {
    if ($null -eq $script:inspection) { Refresh-Inspection }
    if ($null -eq $script:inspection) { throw (T '请先完成环境检测。' 'Complete the environment check first.') }
    if ([string]$script:inspection.Harness.State -eq 'Invalid') { throw [string]$script:inspection.Harness.Reason }
    $root = Get-SelectedRoot
    $script:launcherDir = Get-LauncherDirectory
    if ($nodeCombo.SelectedIndex -eq 2) {
      if ([string]::IsNullOrWhiteSpace($nodePathBox.Text)) { throw (T '请选择 node.exe。' 'Choose node.exe.') }
      [void](Get-LocalAbsolutePath -Value $nodePathBox.Text -Name 'NodePath')
    }

    $installButton.Enabled = $false
    $browseButton.Enabled = $false
    $refreshButton.Enabled = $false
    $logBox.Clear()
    $logBox.AppendText((T "正在准备桌面端文件…`r`n" "Preparing desktop app files…`r`n"))
    [System.Windows.Forms.Application]::DoEvents()
    Copy-LauncherPayload -SourceRoot $PayloadRoot -Destination $script:launcherDir -InstallerExecutable $SetupExecutable

    $setupScript = Join-Path $script:launcherDir 'Setup.ps1'
    $arguments = @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setupScript,
      '-DestinationRoot', $root, '-NonInteractive', '-AcceptUpstreamScripts',
      '-ForceLauncherConfig', '-Language', $(if ($languageCombo.SelectedIndex -eq 1) { 'zh-CN' } elseif ($languageCombo.SelectedIndex -eq 2) { 'en-US' } else { 'auto' })
    )
    if ($nodeCombo.SelectedIndex -eq 1) { $arguments += '-DownloadNode' }
    if ($nodeCombo.SelectedIndex -eq 2) { $arguments += @('-NodePath', (Get-LocalAbsolutePath -Value $nodePathBox.Text -Name 'NodePath')) }
    if ($desktopShortcut.Checked) { $arguments += '-CreateDesktopShortcut' } else { $arguments += '-RemoveDesktopShortcut' }
    if ($startShortcut.Checked) { $arguments += '-CreateStartMenuShortcut' } else { $arguments += '-RemoveStartMenuShortcut' }

    $temporaryBase = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-setup-log-' + [Guid]::NewGuid().ToString('N'))
    $script:outputPath = $temporaryBase + '.out.txt'
    $script:errorPath = $temporaryBase + '.err.txt'
    $script:lastOutputLength = 0
    $script:lastErrorLength = 0
    $argumentLiterals = ($arguments | ForEach-Object { ConvertTo-PowerShellLiteral -Value ([string]$_) }) -join ', '
    $childCommand = '$process = Start-Process -FilePath ' + (ConvertTo-PowerShellLiteral -Value (Join-Path $PSHOME 'powershell.exe')) +
      ' -ArgumentList @(' + $argumentLiterals + ') -WorkingDirectory ' + (ConvertTo-PowerShellLiteral -Value $script:launcherDir) +
      ' -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput ' + (ConvertTo-PowerShellLiteral -Value $script:outputPath) +
      ' -RedirectStandardError ' + (ConvertTo-PowerShellLiteral -Value $script:errorPath) + '; exit $process.ExitCode'
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childCommand))
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $startInfo.Arguments = '-NoProfile -EncodedCommand ' + $encodedCommand
    $startInfo.WorkingDirectory = $script:launcherDir
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = 'Hidden'
    $startInfo.RedirectStandardOutput = $false
    $startInfo.RedirectStandardError = $false
    $script:activeProcess = New-Object System.Diagnostics.Process
    $script:activeProcess.StartInfo = $startInfo
    [void]$script:activeProcess.Start()
    $progress.Style = 'Marquee'
    $pollTimer.Start()
  } catch {
    $script:activeProcess = $null
    $installButton.Enabled = $true
    $browseButton.Enabled = $true
    $refreshButton.Enabled = $true
    [System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      'DSH Desktop',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
  }
})

$form.Add_FormClosing({
  if ($null -ne $script:activeProcess -and -not $script:activeProcess.HasExited) {
    $_.Cancel = $true
    [System.Windows.Forms.MessageBox]::Show(
      (T '安装正在进行，请等待完成。' 'Setup is still running. Please wait for it to finish.'),
      'DSH Desktop',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
  }
})

if (-not [string]::IsNullOrWhiteSpace($PortableDir)) {
  $portablePath = Get-LocalAbsolutePath -Value $PortableDir -Name 'PortableDir'
  $initialRoot = Split-Path -Parent $portablePath
} elseif (Test-Path -LiteralPath 'D:\' -PathType Container) {
  $initialRoot = 'D:\deepseek'
} else {
  $initialRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DSH Desktop'
}
$rootBox.Text = $initialRoot
Set-LocalizedText
$form.Add_Shown({ Refresh-Inspection })
[void]$form.ShowDialog()
