using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace DSHDesktop
{
    internal sealed class BackendHost : IDisposable
    {
        private static readonly Regex LaunchUrlPattern = new Regex(
            @"(?<url>http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_-]{20,256})",
            RegexOptions.Compiled
        );

        private readonly LauncherConfiguration _configuration;
        private readonly Localizer _localizer;
        private readonly object _diagnosticLock = new object();
        private readonly List<string> _diagnostics = new List<string>();
        private Process _process;
        private NativeJob _job;
        private bool _disposed;

        public BackendHost(LauncherConfiguration configuration, Localizer localizer)
        {
            _configuration = configuration;
            _localizer = localizer;
        }

        public async Task<Uri> StartAsync(CancellationToken cancellationToken)
        {
            ThrowIfDisposed();
            await ValidateNodeAsync(cancellationToken).ConfigureAwait(false);

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = _configuration.NodePath,
                Arguments = "--import tsx/esm apps/cli/src/bin.ts web --no-open --host 127.0.0.1 --port 0",
                WorkingDirectory = _configuration.HarnessDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true
            };
            string nodeDirectory = Path.GetDirectoryName(_configuration.NodePath);
            startInfo.EnvironmentVariables["PATH"] = nodeDirectory + ";" +
                startInfo.EnvironmentVariables["PATH"];
            startInfo.EnvironmentVariables["DSH_HOME"] = _configuration.DataDir;
            startInfo.EnvironmentVariables["NO_COLOR"] = "1";

            TaskCompletionSource<Uri> launchSource = new TaskCompletionSource<Uri>();
            TaskCompletionSource<int> exitSource = new TaskCompletionSource<int>();
            _process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            _process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args)
            {
                if (args.Data == null)
                {
                    return;
                }
                Match match = LaunchUrlPattern.Match(args.Data);
                if (match.Success)
                {
                    Uri candidate;
                    if (Uri.TryCreate(match.Groups["url"].Value, UriKind.Absolute, out candidate) &&
                        IsTrustedLaunchUri(candidate))
                    {
                        launchSource.TrySetResult(candidate);
                    }
                    else
                    {
                        launchSource.TrySetException(new InvalidOperationException(
                            _localizer.Text(
                                "Harness 返回了不受信任的启动地址。",
                                "Harness returned an untrusted launch address."
                            )
                        ));
                    }
                    return;
                }
                AddDiagnostic(args.Data);
            };
            _process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args)
            {
                if (args.Data != null)
                {
                    AddDiagnostic(args.Data);
                }
            };
            _process.Exited += delegate
            {
                exitSource.TrySetResult(_process.ExitCode);
            };

            if (!_process.Start())
            {
                throw new InvalidOperationException(_localizer.Text(
                    "无法启动 DeepSeek Harness 后端。",
                    "Unable to start the DeepSeek Harness backend."
                ));
            }

            try
            {
                _job = new NativeJob();
                _job.Assign(_process);
            }
            catch
            {
                StopProcessFallback();
                throw;
            }

            _process.BeginOutputReadLine();
            _process.BeginErrorReadLine();

            Task timeoutTask = Task.Delay(TimeSpan.FromSeconds(75), cancellationToken);
            Task completed = await Task.WhenAny(launchSource.Task, exitSource.Task, timeoutTask)
                .ConfigureAwait(false);

            if (completed == launchSource.Task)
            {
                return await launchSource.Task.ConfigureAwait(false);
            }
            cancellationToken.ThrowIfCancellationRequested();

            string details = GetDiagnostics();
            if (completed == exitSource.Task)
            {
                throw new InvalidOperationException(_localizer.Text(
                    "DeepSeek Harness 后端提前退出。",
                    "The DeepSeek Harness backend exited before startup completed."
                ) + details);
            }
            throw new TimeoutException(_localizer.Text(
                "等待 DeepSeek Harness 启动超时。",
                "Timed out while waiting for DeepSeek Harness to start."
            ) + details);
        }

        public static bool IsTrustedLaunchUri(Uri uri)
        {
            return uri != null &&
                uri.Scheme == Uri.UriSchemeHttp &&
                uri.Host == "127.0.0.1" &&
                uri.Port >= 1 && uri.Port <= 65535 &&
                uri.AbsolutePath == "/" &&
                Regex.IsMatch(uri.Query, @"^\?token=[A-Za-z0-9_-]{20,256}$");
        }

        private async Task ValidateNodeAsync(CancellationToken cancellationToken)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = _configuration.NodePath,
                Arguments = "--version",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (Process versionProcess = Process.Start(startInfo))
            {
                if (versionProcess == null)
                {
                    throw new InvalidOperationException("Unable to inspect Node.js.");
                }
                Task<string> outputTask = versionProcess.StandardOutput.ReadToEndAsync();
                Task waitTask = Task.Run(delegate { versionProcess.WaitForExit(); }, cancellationToken);
                Task completed = await Task.WhenAny(waitTask, Task.Delay(10000, cancellationToken))
                    .ConfigureAwait(false);
                if (completed != waitTask)
                {
                    try { versionProcess.Kill(); } catch { }
                    throw new TimeoutException("Node.js version check timed out.");
                }
                string output = (await outputTask.ConfigureAwait(false)).Trim();
                Match match = Regex.Match(output, @"^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$");
                int major;
                int minor;
                if (!match.Success ||
                    !int.TryParse(match.Groups["major"].Value, out major) ||
                    !int.TryParse(match.Groups["minor"].Value, out minor) ||
                    !((major == 22 && minor >= 19) || major >= 24))
                {
                    throw new InvalidOperationException(_localizer.Text(
                        "Node.js 版本不兼容。需要 ^22.19.0 或 >=24.0.0。当前版本：" + output,
                        "The Node.js version is incompatible. Required: ^22.19.0 or >=24.0.0. Current: " + output
                    ));
                }
            }
        }

        private void AddDiagnostic(string value)
        {
            string safe = DiagnosticText.Redact(value);
            if (string.IsNullOrWhiteSpace(safe))
            {
                return;
            }
            lock (_diagnosticLock)
            {
                if (_diagnostics.Count < 8)
                {
                    _diagnostics.Add(safe);
                }
            }
        }

        private string GetDiagnostics()
        {
            lock (_diagnosticLock)
            {
                return _diagnostics.Count == 0
                    ? string.Empty
                    : Environment.NewLine + Environment.NewLine + string.Join(Environment.NewLine, _diagnostics);
            }
        }

        private void StopProcessFallback()
        {
            if (_process != null)
            {
                try
                {
                    if (!_process.HasExited)
                    {
                        _process.Kill();
                        _process.WaitForExit(5000);
                    }
                }
                catch { }
            }
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException("BackendHost");
            }
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            if (_job != null)
            {
                _job.Dispose();
                _job = null;
            }
            StopProcessFallback();
            if (_process != null)
            {
                _process.Dispose();
                _process = null;
            }
        }
    }
}
