using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("DSH Desktop")]
[assembly: AssemblyDescription("Unofficial Windows desktop entry point for DeepSeek Harness")]
[assembly: AssemblyCompany("DSH Desktop contributors")]
[assembly: AssemblyProduct("DSH Desktop")]
[assembly: AssemblyCopyright("Copyright (c) 2026 DSH Desktop contributors")]
[assembly: AssemblyVersion("0.3.0.0")]
[assembly: AssemblyFileVersion("0.3.0.0")]

internal static class Program
{
    private const int SetupCancelledExitCode = 2;

    [STAThread]
    private static int Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            string baseDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            string configPath = Path.Combine(baseDirectory, "launcher.config.json");
            string setupScript = Path.Combine(baseDirectory, "Setup.ps1");
            string launcherScript = Path.Combine(baseDirectory, "DeepSeek-Harness-Desktop.ps1");

            RequireFile(launcherScript, "The launcher script is missing.");

            if (!File.Exists(configPath))
            {
                RequireFile(setupScript, "The setup script is missing.");
                int setupExitCode = RunPowerShell(setupScript, false, true);
                if (setupExitCode == SetupCancelledExitCode)
                {
                    return 0;
                }
                if (setupExitCode != 0)
                {
                    return setupExitCode;
                }
                if (!File.Exists(configPath))
                {
                    ShowError("Setup completed without creating launcher.config.json.");
                    return 1;
                }
            }

            RunPowerShell(launcherScript, true, false);
            return 0;
        }
        catch (Exception exception)
        {
            ShowError(exception.Message);
            return 1;
        }
    }

    private static int RunPowerShell(string scriptPath, bool hidden, bool waitForExit)
    {
        string powerShellPath = Path.Combine(
            Environment.SystemDirectory,
            @"WindowsPowerShell\v1.0\powershell.exe"
        );
        RequireFile(powerShellPath, "Windows PowerShell 5.1 was not found.");

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powerShellPath;
        startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA "
            + (hidden ? "-WindowStyle Hidden " : "")
            + "-File " + Quote(scriptPath);
        startInfo.WorkingDirectory = Path.GetDirectoryName(scriptPath);
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = hidden;
        startInfo.WindowStyle = hidden ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal;

        Process process = Process.Start(startInfo);
        if (process == null)
        {
            throw new InvalidOperationException("Unable to start Windows PowerShell.");
        }
        if (!waitForExit)
        {
            process.Dispose();
            return 0;
        }

        using (process)
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string Quote(string value)
    {
        if (value.IndexOf('"') >= 0)
        {
            throw new InvalidOperationException("A launcher path contains an unsupported quote character.");
        }
        return "\"" + value + "\"";
    }

    private static void RequireFile(string path, string message)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException(message, path);
        }
    }

    private static void ShowError(string message)
    {
        MessageBox.Show(
            message,
            "DSH Desktop",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error
        );
    }
}
