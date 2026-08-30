using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace DSHDesktop
{
    internal static class Program
    {
        private const string LegacyMutexName = "Local\\DeepSeekHarnessOfficialDesktopLauncher";

        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string baseDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            string configPath = Path.Combine(baseDirectory, "launcher.config.json");
            Localizer localizer = Localizer.FromSystem();

            try
            {
                if (!File.Exists(configPath))
                {
                    return LaunchSetup(baseDirectory, localizer);
                }

                LauncherConfiguration configuration = LauncherConfiguration.Load(configPath);
                localizer = Localizer.Create(configuration.Language);
                configuration.Validate(localizer);

                bool createdNew;
                using (Mutex mutex = new Mutex(true, LegacyMutexName, out createdNew))
                {
                    if (!createdNew)
                    {
                        MessageBox.Show(
                            localizer.Text("DSH Desktop 已经在运行。", "DSH Desktop is already running."),
                            "DSH Desktop",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Information
                        );
                        return 0;
                    }

                    Application.Run(new MainForm(configuration, localizer));
                    GC.KeepAlive(mutex);
                }
                return 0;
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    DiagnosticText.Redact(exception.Message),
                    localizer.Text("DSH Desktop 启动失败", "DSH Desktop failed to start"),
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return 1;
            }
        }

        private static int LaunchSetup(string baseDirectory, Localizer localizer)
        {
            string setupExecutable = Path.Combine(baseDirectory, "DSH-Setup.exe");
            if (!File.Exists(setupExecutable))
            {
                MessageBox.Show(
                    localizer.Text(
                        "尚未配置 DSH Desktop，并且当前文件夹中缺少 DSH-Setup.exe。请重新解压完整安装包。",
                        "DSH Desktop is not configured and DSH-Setup.exe is missing. Extract the complete package and try again."
                    ),
                    "DSH Desktop",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
                return 1;
            }

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = setupExecutable,
                Arguments = "--portable-dir " + Quote(baseDirectory),
                WorkingDirectory = baseDirectory,
                UseShellExecute = true
            };
            Process.Start(startInfo);
            return 0;
        }

        private static string Quote(string value)
        {
            if (value.IndexOf('"') >= 0)
            {
                throw new InvalidOperationException("A path contains an unsupported quote character.");
            }
            int trailingBackslashes = 0;
            for (int index = value.Length - 1; index >= 0 && value[index] == '\\'; index--)
            {
                trailingBackslashes++;
            }
            return "\"" + value + new string('\\', trailingBackslashes) + "\"";
        }
    }
}
