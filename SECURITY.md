# Security Policy

## Supported versions

Only the latest release of this launcher is supported. DeepSeek Harness itself is a separate upstream project and currently identifies as a developer preview.

## Threat model

The launcher assumes the following local components are trusted:

- this launcher directory and its `launcher.config.json` file;
- the configured DeepSeek Harness source checkout and installed dependencies;
- the configured `node.exe` and `msedge.exe` binaries;
- the current Windows user account.

First-run setup additionally trusts the official DeepSeek Harness GitHub repository, the exact commit cloned from it, the package-manager version declared by that commit, its lockfile, and the registries referenced by that lockfile.

It is designed to reduce accidental exposure to the network and accidental termination of unrelated processes. It does not defend against malware or another process already running with the same user's privileges.

## Security boundaries

- Setup uses a hard-coded HTTPS URL for the official DeepSeek Harness repository and verifies the cloned `origin` and 40-character commit hash.
- User-selected installation roots must be absolute local-drive paths. Network paths and existing Harness destinations are rejected.
- Non-interactive full installation requires `-AcceptUpstreamScripts`; interactive installation displays the exact repository and target paths before cloning or running dependencies.
- Setup accepts only a strict `pnpm@<semver>` package-manager declaration, uses `--frozen-lockfile`, and relies on the upstream workspace's strict dependency-build allowlist.
- Setup runs the native pnpm audit and warns on high-severity findings. It never runs forced remediation or changes the upstream lockfile.
- The Harness server is forced to `127.0.0.1` on a random port.
- Only a strict loopback trust URL is accepted from Harness output.
- Trust tokens and API keys are never written by the launcher to disk.
- Diagnostic text is truncated and redacts the trust token and common `sk-...` keys.
- The temporary Edge profile is created under `<DataDir>\desktop-launcher` and removed only after validating its exact parent and per-process name.
- The launcher stops only the Node process it created after confirming the executable path, plus that process's descendants.
- Edge cleanup matches the unique per-run `--user-data-dir` argument.
- Installer inputs must be absolute paths. Existing configuration and shortcuts are not replaced without `-Force`.
- The uninstaller validates shortcut ownership and never removes Harness source, session data, runtimes, or environment variables.

## Known limitations

`DSH-Desktop.exe` is reproducibly buildable from the included C# source but is not Authenticode-signed. Windows SmartScreen may identify it as an unknown publisher. Review the source and run `Build-Exe.ps1` locally if this is unacceptable.

The default setup follows the current upstream default branch, which can change. Higher-assurance deployments should pass a reviewed branch or tag through `-HarnessRef`, record the resulting commit printed by setup, and review upstream changes before updating.

Dependency auditing can report upstream advisories. Setup displays a warning but does not modify DeepSeek Harness dependencies or claim that reported code is unreachable. Review the audit output and the upstream project's response before sensitive use.

The local trust URL is briefly visible in the command line of the Edge process. A different process with the same Windows user's privileges may be able to inspect it. Do not run untrusted software in the same account while handling sensitive sessions.

The launcher runs code from the configured Harness checkout and its `node_modules`. Review updates, use the official upstream repository, and pin a known commit for higher-assurance deployments.

## Reporting a vulnerability

Do not include real API keys, trust URLs, private prompts, or session data in a report. Prefer the repository's [private vulnerability reporting page](https://github.com/followTheWind223/dsh-Desktop/security/advisories/new). If that feature is unavailable, open a minimal issue requesting private contact without disclosing exploit details or sensitive data.
