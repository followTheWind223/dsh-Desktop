using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("DSH Desktop Setup")]
[assembly: AssemblyDescription("Graphical installer and maintenance entry for DSH Desktop")]
[assembly: AssemblyCompany("DSH Desktop contributors")]
[assembly: AssemblyProduct("DSH Desktop")]
[assembly: AssemblyCopyright("Copyright (c) 2026 DSH Desktop contributors")]
[assembly: AssemblyVersion("0.4.1.0")]
[assembly: AssemblyFileVersion("0.4.1.0")]

internal static class SetupProgram
{
    private const string PayloadResourceName = "DSHDesktop.Payload.zip";
    private const long MaximumExpandedBytes = 256L * 1024L * 1024L;
    private const int MaximumEntries = 1000;

    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        string temporaryDirectory = null;
        try
        {
            string executablePath = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
            string baseDirectory = Path.GetDirectoryName(executablePath);
            string adjacentGui = Path.Combine(baseDirectory, "Setup-GUI.ps1");
            string payloadRoot;
            string portableDirectory = null;

            if (File.Exists(adjacentGui) && File.Exists(Path.Combine(baseDirectory, "VERSION")))
            {
                payloadRoot = baseDirectory;
                portableDirectory = baseDirectory;
            }
            else
            {
                temporaryDirectory = Path.Combine(
                    Path.GetTempPath(),
                    "dsh-desktop-setup-" + Guid.NewGuid().ToString("N")
                );
                Directory.CreateDirectory(temporaryDirectory);
                ExtractEmbeddedPayload(temporaryDirectory);
                payloadRoot = temporaryDirectory;
            }

            string requestedPortableDirectory = ReadPortableDirectoryArgument(args);
            if (!string.IsNullOrWhiteSpace(requestedPortableDirectory))
            {
                string requestedFullPath = Path.GetFullPath(requestedPortableDirectory).TrimEnd(Path.DirectorySeparatorChar);
                string baseFullPath = baseDirectory.TrimEnd(Path.DirectorySeparatorChar);
                if (!string.Equals(requestedFullPath, baseFullPath, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("The requested portable directory does not match this setup executable.");
                }
                portableDirectory = baseDirectory;
            }

            return RunSetupGui(payloadRoot, executablePath, portableDirectory);
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "DSH Desktop Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }
        finally
        {
            if (!string.IsNullOrWhiteSpace(temporaryDirectory))
            {
                DeleteTemporaryDirectory(temporaryDirectory);
            }
        }
    }

    private static void ExtractEmbeddedPayload(string destination)
    {
        Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResourceName);
        if (resource == null)
        {
            throw new InvalidOperationException("The embedded installer payload is missing.");
        }

        using (resource)
        using (ZipArchive archive = new ZipArchive(resource, ZipArchiveMode.Read, false))
        {
            if (archive.Entries.Count == 0 || archive.Entries.Count > MaximumEntries)
            {
                throw new InvalidDataException("The embedded installer payload has an invalid entry count.");
            }

            string destinationPrefix = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            long expandedBytes = 0;
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                expandedBytes = checked(expandedBytes + entry.Length);
                if (expandedBytes > MaximumExpandedBytes)
                {
                    throw new InvalidDataException("The embedded installer payload exceeds its size limit.");
                }

                string target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
                if (!target.StartsWith(destinationPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("The embedded installer payload contains an unsafe path.");
                }
                if (string.IsNullOrEmpty(entry.Name))
                {
                    Directory.CreateDirectory(target);
                    continue;
                }

                string parent = Path.GetDirectoryName(target);
                Directory.CreateDirectory(parent);
                using (Stream input = entry.Open())
                using (FileStream output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    input.CopyTo(output);
                }
            }
        }

        if (!File.Exists(Path.Combine(destination, "Setup-GUI.ps1")) ||
            !File.Exists(Path.Combine(destination, "Setup.ps1")) ||
            !File.Exists(Path.Combine(destination, "DSH-Desktop.exe")))
        {
            throw new InvalidDataException("The embedded installer payload is incomplete.");
        }
    }

    private static int RunSetupGui(string payloadRoot, string setupExecutable, string portableDirectory)
    {
        string powerShellPath = Path.Combine(
            Environment.SystemDirectory,
            @"WindowsPowerShell\v1.0\powershell.exe"
        );
        if (!File.Exists(powerShellPath))
        {
            throw new FileNotFoundException("Windows PowerShell 5.1 was not found.", powerShellPath);
        }

        string guiScript = Path.Combine(payloadRoot, "Setup-GUI.ps1");
        ProcessStartInfo startInfo = new ProcessStartInfo
        {
            FileName = powerShellPath,
            Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File " + Quote(guiScript)
                + " -PayloadRoot " + Quote(payloadRoot)
                + " -SetupExecutable " + Quote(setupExecutable)
                + (string.IsNullOrWhiteSpace(portableDirectory) ? string.Empty : " -PortableDir " + Quote(portableDirectory)),
            WorkingDirectory = payloadRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        using (Process process = Process.Start(startInfo))
        {
            if (process == null)
            {
                throw new InvalidOperationException("Unable to start the graphical installer.");
            }
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string ReadPortableDirectoryArgument(string[] args)
    {
        for (int index = 0; index < args.Length; index++)
        {
            if (!string.Equals(args[index], "--portable-dir", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (index + 1 >= args.Length || string.IsNullOrWhiteSpace(args[index + 1]))
            {
                throw new ArgumentException("--portable-dir requires a directory path.");
            }
            return args[index + 1];
        }
        return null;
    }

    private static string Quote(string value)
    {
        if (value.IndexOf('"') >= 0)
        {
            throw new InvalidOperationException("A setup path contains an unsupported quote character.");
        }
        return "\"" + value + "\"";
    }

    private static void DeleteTemporaryDirectory(string path)
    {
        string fullPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
        string tempPrefix = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!fullPath.StartsWith(tempPrefix, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(fullPath).StartsWith("dsh-desktop-setup-", StringComparison.Ordinal))
        {
            return;
        }

        for (int attempt = 0; attempt < 4; attempt++)
        {
            try
            {
                if (Directory.Exists(fullPath))
                {
                    Directory.Delete(fullPath, true);
                }
                return;
            }
            catch (IOException)
            {
                Thread.Sleep(250 * (attempt + 1));
            }
            catch (UnauthorizedAccessException)
            {
                Thread.Sleep(250 * (attempt + 1));
            }
        }
    }
}
