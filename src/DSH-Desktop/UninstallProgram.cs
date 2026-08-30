using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("Uninstall DSH Desktop")]
[assembly: AssemblyDescription("Safe one-click uninstaller for DSH Desktop")]
[assembly: AssemblyCompany("DSH Desktop contributors")]
[assembly: AssemblyProduct("DSH Desktop")]
[assembly: AssemblyCopyright("Copyright (c) 2026 DSH Desktop contributors")]
[assembly: AssemblyVersion("0.4.2.0")]
[assembly: AssemblyFileVersion("0.4.2.0")]

internal sealed class UninstallConfiguration
{
    public int SchemaVersion { get; set; }
    public string HarnessDir { get; set; }
    public string DataDir { get; set; }
    public string NodePath { get; set; }
    public bool HarnessManaged { get; set; }
    public bool DataManaged { get; set; }
    public bool NodeManaged { get; set; }
}

internal sealed class UninstallChoices
{
    public bool Confirmed { get; set; }
    public bool RemoveHarness { get; set; }
    public bool ConfirmExistingHarnessRemoval { get; set; }
    public bool RemoveData { get; set; }
    public bool RemoveNode { get; set; }
}

internal sealed class HarnessPackageMetadata
{
    public string name { get; set; }
}

internal sealed class UninstallForm : Form
{
    private readonly bool chinese;
    private readonly CheckBox removeHarness;
    private readonly CheckBox removeData;
    private readonly CheckBox removeNode;
    private readonly string harnessDirectory;
    private readonly bool harnessManaged;

    public UninstallChoices Choices { get; private set; }

    public UninstallForm(string launcherDirectory, UninstallConfiguration configuration)
    {
        chinese = CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        Choices = new UninstallChoices();
        Text = T("卸载 DSH Desktop", "Uninstall DSH Desktop");
        ClientSize = new Size(570, 420);
        MinimumSize = new Size(586, 459);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(247, 249, 252);
        Font = new Font("Segoe UI", 9F);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        MaximizeBox = false;

        Label title = new Label
        {
            Text = T("卸载 DeepSeek Harness 桌面端", "Uninstall DeepSeek Harness Desktop"),
            Location = new Point(28, 24),
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 17F),
            ForeColor = Color.FromArgb(24, 34, 51)
        };
        Controls.Add(title);

        Label path = new Label
        {
            Text = T("应用目录：", "Application folder: ") + launcherDirectory,
            Location = new Point(31, 67),
            Size = new Size(510, 36),
            ForeColor = Color.FromArgb(92, 104, 121)
        };
        Controls.Add(path);

        Panel options = new Panel
        {
            Location = new Point(30, 110),
            Size = new Size(510, 180),
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle
        };
        Controls.Add(options);

        CheckBox removeApp = CreateOption(
            T("删除桌面端程序、配置和快捷方式", "Remove the desktop app, configuration, and shortcuts"),
            18,
            true,
            false
        );
        options.Controls.Add(removeApp);

        string verifiedHarnessDirectory;
        bool harnessCanBeRemoved = TryGetHarnessDirectory(launcherDirectory, configuration, out verifiedHarnessDirectory);
        harnessDirectory = verifiedHarnessDirectory;
        harnessManaged = configuration != null && configuration.HarnessManaged;

        removeHarness = CreateOption(
            harnessManaged
                ? T("同时删除由 DSH Desktop 安装的 Harness", "Also remove Harness installed by DSH Desktop")
                : T("同时删除已有的 Harness（默认保留）", "Also remove the existing Harness (kept by default)"),
            56,
            false,
            harnessCanBeRemoved
        );
        options.Controls.Add(removeHarness);

        Label harnessPath = new Label
        {
            Text = harnessCanBeRemoved
                ? T("目录：", "Folder: ") + harnessDirectory
                : T("未找到可安全识别的 Harness 目录。", "No safely identifiable Harness folder was found."),
            Location = new Point(38, 78),
            Size = new Size(455, 32),
            Font = new Font("Segoe UI", 8F),
            ForeColor = harnessManaged ? Color.FromArgb(92, 104, 121) : Color.FromArgb(171, 105, 34)
        };
        options.Controls.Add(harnessPath);

        removeNode = CreateOption(
            T("同时删除由本安装器下载的便携 Node.js", "Also remove portable Node.js downloaded by this installer"),
            118,
            false,
            configuration != null && configuration.NodeManaged
        );
        options.Controls.Add(removeNode);

        removeData = CreateOption(
            T("同时永久删除用户数据（默认保留）", "Also permanently delete user data (kept by default)"),
            156,
            false,
            configuration != null && configuration.DataManaged
        );
        removeData.ForeColor = Color.FromArgb(183, 54, 54);
        options.Controls.Add(removeData);

        Label hint = new Label
        {
            Text = T("Harness 默认保留；勾选后会显示完整路径并再次确认。Node.js 和数据只允许删除安装器记录的组件。", "Harness is kept by default and requires path confirmation. Node.js and data can be removed only when recorded as installer-managed."),
            Location = new Point(31, 313),
            Size = new Size(500, 48),
            ForeColor = Color.FromArgb(92, 104, 121)
        };
        Controls.Add(hint);

        Button cancel = new Button
        {
            Text = T("取消", "Cancel"),
            DialogResult = DialogResult.Cancel,
            Location = new Point(350, 374),
            Size = new Size(90, 32)
        };
        Controls.Add(cancel);
        CancelButton = cancel;

        Button uninstall = new Button
        {
            Text = T("卸载", "Uninstall"),
            Location = new Point(450, 374),
            Size = new Size(90, 32),
            BackColor = Color.FromArgb(199, 57, 57),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat
        };
        uninstall.FlatAppearance.BorderSize = 0;
        uninstall.Click += ConfirmUninstall;
        Controls.Add(uninstall);
        AcceptButton = uninstall;
    }

    private CheckBox CreateOption(string text, int top, bool isChecked, bool enabled)
    {
        return new CheckBox
        {
            Text = text,
            Location = new Point(18, top),
            AutoSize = true,
            Checked = isChecked,
            Enabled = enabled
        };
    }

    private void ConfirmUninstall(object sender, EventArgs eventArgs)
    {
        if (removeHarness.Checked)
        {
            string warning = harnessManaged
                ? T(
                    "以下 Harness 目录将被永久删除且无法恢复：\n\n" + harnessDirectory + "\n\n确定继续吗？",
                    "The following Harness folder will be permanently deleted and cannot be recovered:\n\n" + harnessDirectory + "\n\nContinue?"
                )
                : T(
                    "这是安装前已存在或被复用的 Harness，可能包含你的代码修改。以下整个目录将被永久删除且无法恢复：\n\n" + harnessDirectory + "\n\n确定继续吗？",
                    "This Harness existed before setup or was reused and may contain your code changes. The entire folder below will be permanently deleted and cannot be recovered:\n\n" + harnessDirectory + "\n\nContinue?"
                );
            DialogResult harnessAnswer = MessageBox.Show(
                warning,
                T("确认删除 Harness", "Confirm Harness deletion"),
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2
            );
            if (harnessAnswer != DialogResult.Yes) { return; }
        }

        if (removeData.Checked)
        {
            DialogResult dataAnswer = MessageBox.Show(
                T("用户数据将被永久删除且无法恢复。确定继续吗？", "User data will be permanently deleted and cannot be recovered. Continue?"),
                T("确认删除数据", "Confirm data deletion"),
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2
            );
            if (dataAnswer != DialogResult.Yes) { return; }
        }

        Choices.Confirmed = true;
        Choices.RemoveHarness = removeHarness.Checked;
        Choices.ConfirmExistingHarnessRemoval = removeHarness.Checked && !harnessManaged;
        Choices.RemoveData = removeData.Checked;
        Choices.RemoveNode = removeNode.Checked;
        DialogResult = DialogResult.OK;
        Close();
    }

    private string T(string chineseText, string englishText)
    {
        return chinese ? chineseText : englishText;
    }

    private static bool TryGetHarnessDirectory(
        string launcherDirectory,
        UninstallConfiguration configuration,
        out string harnessDirectory)
    {
        harnessDirectory = null;
        if (configuration == null || string.IsNullOrWhiteSpace(configuration.HarnessDir)) { return false; }

        try
        {
            string candidate = Path.GetFullPath(configuration.HarnessDir)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string launcher = Path.GetFullPath(launcherDirectory)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string root = Path.GetPathRoot(candidate).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (candidate.StartsWith(@"\\", StringComparison.Ordinal) ||
                string.Equals(candidate, root, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(Path.GetFileName(candidate), "deepseek-harness", StringComparison.OrdinalIgnoreCase) ||
                PathsOverlap(candidate, launcher) ||
                !Directory.Exists(candidate))
            {
                return false;
            }

            FileAttributes attributes = File.GetAttributes(candidate);
            if ((attributes & FileAttributes.ReparsePoint) != 0) { return false; }

            foreach (string marker in new[] { "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", @"apps\cli\src\bin.ts" })
            {
                if (!File.Exists(Path.Combine(candidate, marker))) { return false; }
            }

            string packagePath = Path.Combine(candidate, "package.json");
            HarnessPackageMetadata package = new JavaScriptSerializer()
                .Deserialize<HarnessPackageMetadata>(File.ReadAllText(packagePath));
            if (package == null || !string.Equals(package.name, "@deepseek-ai/dsh-root", StringComparison.Ordinal))
            {
                return false;
            }

            harnessDirectory = candidate;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool PathsOverlap(string first, string second)
    {
        if (string.Equals(first, second, StringComparison.OrdinalIgnoreCase)) { return true; }
        string firstPrefix = first.TrimEnd('\\') + "\\";
        string secondPrefix = second.TrimEnd('\\') + "\\";
        return first.StartsWith(secondPrefix, StringComparison.OrdinalIgnoreCase) ||
            second.StartsWith(firstPrefix, StringComparison.OrdinalIgnoreCase);
    }
}

internal static class UninstallProgram
{
    [STAThread]
    private static int Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        bool chinese = CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase);

        try
        {
            string launcherDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            string uninstallScript = Path.Combine(launcherDirectory, "Uninstall.ps1");
            RequireFile(uninstallScript, "Uninstall.ps1 is missing.");
            UninstallConfiguration configuration = LoadConfiguration(Path.Combine(launcherDirectory, "launcher.config.json"));

            using (UninstallForm form = new UninstallForm(launcherDirectory, configuration))
            {
                form.ShowDialog();
                if (!form.Choices.Confirmed) { return 0; }
                StartCleanup(uninstallScript, Process.GetCurrentProcess().Id, form.Choices);
            }
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                chinese ? "DSH Desktop 卸载失败" : "DSH Desktop uninstall failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }
    }

    private static UninstallConfiguration LoadConfiguration(string path)
    {
        if (!File.Exists(path)) { return null; }
        string json = File.ReadAllText(path);
        UninstallConfiguration configuration = new JavaScriptSerializer().Deserialize<UninstallConfiguration>(json);
        if (configuration == null || configuration.SchemaVersion != 2)
        {
            throw new InvalidDataException("The launcher configuration is invalid.");
        }
        return configuration;
    }

    private static void StartCleanup(string scriptPath, int processId, UninstallChoices choices)
    {
        string powerShellPath = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
        RequireFile(powerShellPath, "Windows PowerShell 5.1 was not found.");
        string arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "
            + Quote(scriptPath)
            + " -RemoveConfig -RemoveLauncherFiles -RemoveDesktopShortcut -RemoveStartMenuShortcut -WaitForProcessId "
            + processId.ToString(CultureInfo.InvariantCulture)
            + " -ShowCompletion";
        if (choices.RemoveHarness)
        {
            arguments += " -RemoveHarness";
            if (choices.ConfirmExistingHarnessRemoval) { arguments += " -ConfirmExistingHarnessRemoval"; }
        }
        if (choices.RemoveNode) { arguments += " -RemoveManagedNode"; }
        if (choices.RemoveData) { arguments += " -RemoveManagedData"; }

        ProcessStartInfo startInfo = new ProcessStartInfo
        {
            FileName = powerShellPath,
            Arguments = arguments,
            WorkingDirectory = Path.GetTempPath(),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        Process process = Process.Start(startInfo);
        if (process == null) { throw new InvalidOperationException("Unable to start the uninstall cleanup process."); }
        process.Dispose();
    }

    private static string Quote(string value)
    {
        if (value.IndexOf('"') >= 0) { throw new InvalidOperationException("A launcher path contains an unsupported quote character."); }
        return "\"" + value + "\"";
    }

    private static void RequireFile(string path, string message)
    {
        if (!File.Exists(path)) { throw new FileNotFoundException(message, path); }
    }
}
