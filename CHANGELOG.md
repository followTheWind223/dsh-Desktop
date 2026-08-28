# Changelog

All notable changes to this project will be documented in this file.

## 0.3.0 - 2026-08-28

- Added an interactive choice between an existing Node.js runtime and an official portable LTS download.
- Added SHA-256 verification, archive path validation, x64/ARM64 selection, and process-local Node configuration.
- Added `Uninstall-DSH-Desktop.exe` for confirmed one-click removal of known launcher files.
- Preserved Harness source, session data, portable Node.js, Edge, environment variables, and unrecognized user files during uninstall.
- Added an automated GitHub Release workflow with clean Windows builds, release validation, ZIP packaging, and SHA-256 checksums.

## 0.2.0 - 2026-08-28

- Added `DSH-Desktop.exe` as the unified first-run setup and daily launch entry point.
- Added an interactive folder picker so users choose where Harness and its data are installed.
- Added official-repository cloning, pinned pnpm selection, frozen-lockfile installation, build verification, and dependency-audit warnings.
- Added non-interactive setup parameters for controlled automation without changing global environment variables.

## 0.1.0 - 2026-08-28

- Initial open-source release.
- Added a Windows PowerShell desktop launcher for a built DeepSeek Harness checkout.
- Added a Microsoft Edge app-mode window with an isolated per-run profile.
- Added loopback URL validation, token redaction, owned-process cleanup, and single-instance protection.
- Added safe installer/uninstaller scripts and a multi-size icon derived from the upstream favicon.
