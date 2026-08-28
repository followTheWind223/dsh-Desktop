# Privacy policy

Last updated: 2026-08-28

## Scope

This policy applies to the DSH Desktop launcher, installer, maintenance tools, and uninstaller. DSH Desktop is an unofficial desktop host for the separate open-source DeepSeek Harness project.

## Information handled by DSH Desktop

The DSH Desktop maintainers do not operate telemetry, analytics, advertising, account, or cloud-storage services for the application. DSH Desktop does not transmit information to systems operated by its maintainers.

The launcher stores only local configuration needed to start and maintain the application, including installation paths, interface language, and installer-ownership flags. It does not place API keys, passwords, login tokens, prompts, or conversations in `launcher.config.json`.

The desktop host creates a temporary WebView2 browser profile inside the selected local data directory and attempts to remove that profile when the application closes. DeepSeek Harness manages its own workspace, credentials, and conversation data separately in the user-selected data directory.

## Network access

Network access occurs only when requested by the user or required for a user-selected operation:

- The installer can download source code or release metadata from GitHub, a compatible portable Node.js archive from `nodejs.org`, and the Microsoft WebView2 bootstrapper when those components are missing.
- At runtime, DSH Desktop starts DeepSeek Harness on a loopback-only address (`127.0.0.1`). Harness and any model or API provider configured by the user can make their own network requests.
- External HTTPS links selected by the user are opened in the system browser.

Those third-party services can receive standard connection information such as an IP address according to their own policies. Relevant policies include the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement), [Microsoft Privacy Statement](https://privacy.microsoft.com/en-us/privacystatement), and, when the user chooses DeepSeek services, the [DeepSeek Privacy Policy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html).

## Control and deletion

Users choose the installation and data locations. The uninstaller removes the desktop application and its shortcuts by default while retaining Harness, Node.js, and user data. Installer-managed optional components can be selected for deletion, and deleting the data directory requires an additional confirmation. Unknown files are not intentionally removed.

## Contact

Privacy questions can be submitted through the repository's [GitHub Issues](https://github.com/followTheWind223/dsh-Desktop/issues). Do not include API keys, access tokens, conversation content, or other sensitive information in a public issue.
