using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DSHDesktop
{
    internal sealed class MainForm : Form
    {
        private readonly LauncherConfiguration _configuration;
        private readonly Localizer _localizer;
        private readonly Panel _startupPanel;
        private readonly Label _statusLabel;
        private readonly WebView2 _webView;
        private readonly CancellationTokenSource _cancellation = new CancellationTokenSource();
        private BackendHost _backend;
        private Uri _trustedOrigin;
        private string _userDataFolder;
        private bool _closing;

        public MainForm(LauncherConfiguration configuration, Localizer localizer)
        {
            _configuration = configuration;
            _localizer = localizer;

            Text = "DeepSeek Harness";
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(1200, 800);
            MinimumSize = new Size(900, 600);
            BackColor = Color.FromArgb(246, 247, 249);
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

            _webView = new WebView2
            {
                Dock = DockStyle.Fill,
                Visible = false,
                DefaultBackgroundColor = Color.FromArgb(246, 247, 249)
            };
            Controls.Add(_webView);

            _startupPanel = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = Color.FromArgb(246, 247, 249)
            };
            Label title = new Label
            {
                AutoSize = false,
                Dock = DockStyle.Top,
                Height = 90,
                Padding = new Padding(0, 34, 0, 0),
                TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font("Segoe UI", 20F, FontStyle.Bold),
                ForeColor = Color.FromArgb(28, 32, 39),
                Text = "DeepSeek Harness"
            };
            ProgressBar progress = new ProgressBar
            {
                Style = ProgressBarStyle.Marquee,
                MarqueeAnimationSpeed = 28,
                Width = 300,
                Height = 5,
                Left = (ClientSize.Width - 300) / 2,
                Top = 365,
                Anchor = AnchorStyles.None
            };
            _statusLabel = new Label
            {
                AutoSize = false,
                Width = 600,
                Height = 64,
                Left = (ClientSize.Width - 600) / 2,
                Top = 395,
                Anchor = AnchorStyles.None,
                TextAlign = ContentAlignment.TopCenter,
                Font = new Font("Segoe UI", 10.5F),
                ForeColor = Color.FromArgb(83, 90, 102),
                Text = _localizer.Text("正在启动本地服务…", "Starting the local service…")
            };
            _startupPanel.Controls.Add(title);
            _startupPanel.Controls.Add(progress);
            _startupPanel.Controls.Add(_statusLabel);
            Controls.Add(_startupPanel);
            _startupPanel.BringToFront();

            Shown += OnShown;
            FormClosing += OnFormClosing;
            FormClosed += OnFormClosed;
        }

        private async void OnShown(object sender, EventArgs eventArgs)
        {
            try
            {
                _backend = new BackendHost(_configuration, _localizer);
                Uri launchUri = await _backend.StartAsync(_cancellation.Token);
                if (_closing)
                {
                    return;
                }

                _statusLabel.Text = _localizer.Text(
                    "正在准备桌面窗口…",
                    "Preparing the desktop window…"
                );
                _trustedOrigin = new Uri(launchUri.GetLeftPart(UriPartial.Authority));
                await InitializeWebViewAsync(launchUri);
                if (_closing)
                {
                    return;
                }

                _startupPanel.Visible = false;
                _webView.Visible = true;
                _webView.Focus();
            }
            catch (OperationCanceledException)
            {
                if (!_closing)
                {
                    ShowStartupError(_localizer.Text("启动已取消。", "Startup was cancelled."));
                }
            }
            catch (Exception exception)
            {
                if (!_closing)
                {
                    ShowStartupError(DiagnosticText.Redact(exception.Message));
                }
            }
        }

        private async Task InitializeWebViewAsync(Uri launchUri)
        {
            string stateDirectory = Path.Combine(_configuration.DataDir, "desktop-launcher");
            Directory.CreateDirectory(stateDirectory);
            CleanupStaleProfiles(stateDirectory);
            _userDataFolder = Path.Combine(
                stateDirectory,
                "webview2-profile-" + Process.GetCurrentProcess().Id
            );
            Directory.CreateDirectory(_userDataFolder);

            CoreWebView2EnvironmentOptions options = new CoreWebView2EnvironmentOptions(
                null,
                _localizer.WebViewLanguage,
                null
            );
            CoreWebView2Environment environment = await CoreWebView2Environment.CreateAsync(
                null,
                _userDataFolder,
                options
            );
            await _webView.EnsureCoreWebView2Async(environment);

            CoreWebView2Settings settings = _webView.CoreWebView2.Settings;
            settings.AreDefaultContextMenusEnabled = false;
            settings.AreDevToolsEnabled = false;
            settings.AreBrowserAcceleratorKeysEnabled = false;
            settings.IsStatusBarEnabled = false;
            settings.IsZoomControlEnabled = false;
            settings.IsPasswordAutosaveEnabled = false;
            settings.IsGeneralAutofillEnabled = false;

            _webView.CoreWebView2.NavigationStarting += OnNavigationStarting;
            _webView.CoreWebView2.FrameNavigationStarting += OnFrameNavigationStarting;
            _webView.CoreWebView2.NewWindowRequested += OnNewWindowRequested;
            _webView.CoreWebView2.PermissionRequested += delegate(object s, CoreWebView2PermissionRequestedEventArgs e)
            {
                e.State = CoreWebView2PermissionState.Deny;
            };
            _webView.CoreWebView2.ProcessFailed += delegate
            {
                if (!_closing)
                {
                    BeginInvoke((Action)delegate
                    {
                        ShowStartupError(_localizer.Text(
                            "WebView2 进程意外退出，请关闭窗口后重试。",
                            "The WebView2 process exited unexpectedly. Close the window and try again."
                        ));
                    });
                }
            };

            _webView.CoreWebView2.Navigate(launchUri.AbsoluteUri);
        }

        private void OnNavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs eventArgs)
        {
            Uri uri;
            if (!Uri.TryCreate(eventArgs.Uri, UriKind.Absolute, out uri) || !IsTrustedWebUri(uri))
            {
                eventArgs.Cancel = true;
            }
        }

        private void OnFrameNavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs eventArgs)
        {
            Uri uri;
            if (!Uri.TryCreate(eventArgs.Uri, UriKind.Absolute, out uri) || !IsTrustedWebUri(uri))
            {
                eventArgs.Cancel = true;
            }
        }

        private void OnNewWindowRequested(object sender, CoreWebView2NewWindowRequestedEventArgs eventArgs)
        {
            eventArgs.Handled = true;
            Uri uri;
            if (!Uri.TryCreate(eventArgs.Uri, UriKind.Absolute, out uri))
            {
                return;
            }
            if (IsTrustedWebUri(uri))
            {
                _webView.CoreWebView2.Navigate(uri.AbsoluteUri);
                return;
            }
            if (uri.Scheme == Uri.UriSchemeHttps && string.IsNullOrEmpty(uri.UserInfo))
            {
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = uri.AbsoluteUri,
                        UseShellExecute = true
                    });
                }
                catch { }
            }
        }

        private bool IsTrustedWebUri(Uri uri)
        {
            return uri != null && _trustedOrigin != null &&
                uri.Scheme == Uri.UriSchemeHttp &&
                uri.Host == "127.0.0.1" &&
                uri.Port == _trustedOrigin.Port;
        }

        private void ShowStartupError(string message)
        {
            _statusLabel.ForeColor = Color.FromArgb(176, 46, 46);
            _statusLabel.Text = message;
            MessageBox.Show(
                this,
                message,
                _localizer.Text("DSH Desktop 启动失败", "DSH Desktop failed to start"),
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }

        private void OnFormClosing(object sender, FormClosingEventArgs eventArgs)
        {
            _closing = true;
            _cancellation.Cancel();
            if (_webView.CoreWebView2 != null)
            {
                _webView.CoreWebView2.Stop();
            }
        }

        private void OnFormClosed(object sender, FormClosedEventArgs eventArgs)
        {
            _webView.Dispose();
            if (_backend != null)
            {
                _backend.Dispose();
                _backend = null;
            }
            _cancellation.Dispose();
            TryDeleteProfile(_userDataFolder);
        }

        private static void CleanupStaleProfiles(string stateDirectory)
        {
            try
            {
                foreach (string directory in Directory.GetDirectories(stateDirectory, "webview2-profile-*"))
                {
                    TryDeleteProfile(directory);
                }
            }
            catch { }
        }

        private static void TryDeleteProfile(string directory)
        {
            if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
            {
                return;
            }
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    Directory.Delete(directory, true);
                    return;
                }
                catch
                {
                    Thread.Sleep(200);
                }
            }
        }
    }
}
