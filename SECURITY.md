# Security Policy

## Supported versions

Only the latest DSH Desktop release is supported. DeepSeek Harness is a separate upstream developer-preview project.

## Release supply chain

- The end-user installer does not clone a repository or run a package manager.
- The build uses the exact Harness npm version and integrity recorded in `runtime/runtime.lock.json` and `runtime/package-lock.json`.
- Node.js archives are downloaded only from `https://nodejs.org/dist/` and must match committed SHA-256 values.
- Dependency lifecycle scripts are disabled during installation, then only the exact reviewed scripts for `@deepseek-ai/dsh-subprocess-local`, `koffi`, and `node-pty` are rebuilt.
- Production dependencies are audited without automatic remediation.
- The WebView2 Evergreen Bootstrapper must have a valid Microsoft Corporation Authenticode signature.
- The Inno Setup compiler used by project scripts must have a valid Pyrsys B.V. Authenticode signature.
- A generated runtime manifest records the DSH Desktop version, architecture, upstream Harness commit/package identity, Node archive hash, entry hashes, and WebView2 publisher.

## Runtime boundaries

- The bundled Node.js runtime is private to the installation and is never added to PATH.
- Harness is forced to `127.0.0.1` on a random port.
- The launcher accepts only a strict loopback URL with a bounded token format.
- Diagnostics redact local trust tokens and common API-key formats.
- WebView2 disables developer tools, password saving, autofill, permission grants, default context menus, and untrusted in-window navigation.
- The Node process tree is assigned to a Windows Job Object with `KILL_ON_JOB_CLOSE`.
- `launcher.config.json` contains paths, language, and ownership flags only. It must never contain credentials.

## Installer and uninstall boundaries

- The user chooses the destination; source checkouts are rejected to avoid overwriting project files.
- Installation is per-user by default and does not require elevation.
- The fixed Inno Setup AppId supports repair and in-place upgrades.
- Uninstall always removes the DSH Desktop program and its bundled Harness/Node runtime.
- User data is preserved by default. Interactive deletion requires an explicit Yes response; silent uninstall always preserves it.
- Recursive data deletion is limited to the exact `{app}\data` path and refuses reparse points.

## Known limitations

Unsigned builds can trigger browser, antivirus, or SmartScreen reputation warnings. A self-signed certificate does not establish public trust. Until the SignPath integration is approved, verify Release SHA-256 checksums or build from reviewed source.

The runtime necessarily executes the bundled upstream Harness and its production dependencies. Review `runtime/runtime.lock.json`, the generated runtime manifest, and upstream safety documentation before sensitive use.

Another process running as the same Windows user can inspect or interfere with local process memory and loopback traffic. Do not handle sensitive sessions alongside untrusted software in the same account.

## Reporting a vulnerability

Use the repository's [private vulnerability reporting page](https://github.com/followTheWind223/dsh-Desktop/security/advisories/new). Do not include real API keys, trust URLs, private prompts, or session data in public issues.
