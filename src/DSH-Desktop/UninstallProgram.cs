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
[assembly: AssemblyVersion("0.4.1.0")]
[assembly: AssemblyFileVersion("0.4.1.0")]

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
    public bool RemoveData { get; set; }
    public bool RemoveNode { get; set; }
}

internal sealed class UninstallForm : Form
{
    private readonly bool chinese;
    private readonly CheckBox removeHarness;
    private readonly CheckBox removeData;
    private readonly CheckBox removeNode;

    public UninstallChoices Choices { get; private set; }

    public UninstallForm(string launcherDirectory, UninstallConfiguration configuration)
    {
        chinese = CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        Choices = new UninstallChoices();
        Text = T("卸载 DSH Desktop", "Uninstall DSH Desktop");
        ClientSize = new Size(570, 390);
        MinimumSize = new Size(586, 429);
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

        removeHarness = CreateOption(
            T("同时删除由本安装器下载的 Harness", "Also remove Harness downloaded by this installer"),
            56,
            false,
            configuration != null && configuration.HarnessManaged
        );
        options.Controls.Add(removeHarness);

        removeNode = CreateOption(
            T("同时删除由本安装器下载的便携 Node.js", "Also remove portable Node.js downloaded by this installer"),
            94,
            false,
            configuration != null && configuration.NodeManaged
        );
        options.Controls.Add(removeNode);

        removeData = CreateOption(
            T("同时永久删除用户数据（默认保留）", "Also permanently delete user data (kept by default)"),
            132,
            false,
            configuration != null && configuration.DataManaged
        );
        removeData.ForeColor = Color.FromArgb(183, 54, 54);
        options.Controls.Add(removeData);

        Label hint = new Label
        {
            Text = T("只有本安装器创建且在配置中标记的组件才允许勾选。未知文件不会被删除。", "Only components created and recorded by this installer can be selected. Unknown files are never deleted."),
            Location = new Point(31, 303),
            Size = new Size(500, 38),
            ForeColor = Color.FromArgb(92, 104, 121)
        };
        Controls.Add(hint);

        Button cancel = new Button
        {
            Text = T("取消", "Cancel"),
            DialogResult = DialogResult.Cancel,
            Location = new Point(350, 344),
            Size = new Size(90, 32)
        };
        Controls.Add(cancel);
        CancelButton = cancel;

        Button uninstall = new Button
        {
            Text = T("卸载", "Uninstall"),
            Location = new Point(450, 344),
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
        Choices.RemoveData = removeData.Checked;
        Choices.RemoveNode = removeNode.Checked;
        DialogResult = DialogResult.OK;
        Close();
    }

    private string T(string chineseText, string englishText)
    {
        return chinese ? chineseText : englishText;
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
        if (choices.RemoveHarness) { arguments += " -RemoveManagedHarness"; }
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
