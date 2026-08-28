using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Uninstall DSH Desktop")]
[assembly: AssemblyDescription("Safe one-click uninstaller for DSH Desktop launcher files")]
[assembly: AssemblyCompany("DSH Desktop contributors")]
[assembly: AssemblyProduct("DSH Desktop")]
[assembly: AssemblyCopyright("Copyright (c) 2026 DSH Desktop contributors")]
[assembly: AssemblyVersion("0.3.0.0")]
[assembly: AssemblyFileVersion("0.3.0.0")]

internal static class UninstallProgram
{
    [STAThread]
    private static int Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            string launcherDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            string uninstallScript = Path.Combine(launcherDirectory, "Uninstall.ps1");
            RequireFile(uninstallScript, "Uninstall.ps1 is missing.");

            DialogResult answer = MessageBox.Show(
                "Remove the DSH Desktop launcher?\n\n"
                + "Folder: " + launcherDirectory + "\n\n"
                + "This removes the desktop shortcut, local launcher configuration, and known launcher scripts/executables. "
                + "DeepSeek Harness source, session data, portable Node.js, Edge, and environment variables are kept. "
                + "Unrecognized files are never deleted.",
                "Uninstall DSH Desktop",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2
            );
            if (answer != DialogResult.Yes)
            {
                return 0;
            }

            StartCleanup(uninstallScript, Process.GetCurrentProcess().Id);
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "DSH Desktop uninstall failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }
    }

    private static void StartCleanup(string scriptPath, int processId)
    {
        string powerShellPath = Path.Combine(
            Environment.SystemDirectory,
            @"WindowsPowerShell\v1.0\powershell.exe"
        );
        RequireFile(powerShellPath, "Windows PowerShell 5.1 was not found.");

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powerShellPath;
        startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "
            + Quote(scriptPath)
            + " -RemoveConfig -RemoveLauncherFiles -WaitForProcessId "
            + processId.ToString(System.Globalization.CultureInfo.InvariantCulture)
            + " -ShowCompletion";
        startInfo.WorkingDirectory = Path.GetTempPath();
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;

        Process process = Process.Start(startInfo);
        if (process == null)
        {
            throw new InvalidOperationException("Unable to start the uninstall cleanup process.");
        }
        process.Dispose();
    }

    private static string Quote(string value)
    {
        if (value.IndexOf('"') >= 0)
        {
            throw new InvalidOperationException("The launcher path contains an unsupported quote character.");
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
}
