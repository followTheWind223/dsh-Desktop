# Security Policy

## Supported versions

Only the latest release of this launcher is supported. DeepSeek Harness itself is a separate upstream project and currently identifies as a developer preview.

## Threat model

The launcher assumes the following local components are trusted:

- this launcher directory and its `launcher.config.json` file;
- the configured DeepSeek Harness source checkout and installed dependencies;
- the configured `node.exe` and `msedge.exe` binaries;
- the current Windows user account.

It is designed to reduce accidental exposure to the network and accidental termination of unrelated processes. It does not defend against malware or another process already running with the same user's privileges.

## Security boundaries

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

The local trust URL is briefly visible in the command line of the Edge process. A different process with the same Windows user's privileges may be able to inspect it. Do not run untrusted software in the same account while handling sensitive sessions.

The launcher runs code from the configured Harness checkout and its `node_modules`. Review updates, use the official upstream repository, and pin a known commit for higher-assurance deployments.

## Reporting a vulnerability

Do not include real API keys, trust URLs, private prompts, or session data in a report. Prefer the repository's [private vulnerability reporting page](https://github.com/followTheWind223/dsh-Desktop/security/advisories/new). If that feature is unavailable, open a minimal issue requesting private contact without disclosing exploit details or sensitive data.
