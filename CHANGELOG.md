# Changelog

All notable changes to this project will be documented in this file.

## 0.5.0 - 2026-09-01

- Replaced the source-clone/PowerShell SFX flow with a standard single-file Inno Setup installer.
- Bundled the locked official `@deepseek-ai/dsh@0.1.2-alpha.3` production package and private Node.js `v24.20.0` runtime, so end users no longer need Git, Node.js, pnpm, or a source build.
- Added runtime provenance locks, Node.js SHA-256 verification, reviewed lifecycle-script allowlisting, production dependency auditing, and a generated runtime manifest.
- Added Chinese/English installation, user-selected destination, optional desktop shortcut, Start menu/uninstall entries, repair/upgrade support, and source-checkout overwrite protection.
- Bundled the Microsoft-signed WebView2 Evergreen Bootstrapper and fixed WebView2 detection across HKLM/HKCU 32-bit and 64-bit registry views.
- Made uninstall remove DSH Desktop, bundled Harness, and bundled Node.js together while preserving user data by default and offering an explicit interactive data-removal choice.
- Added real install, Harness launch, loopback listener, process cleanup, repair, and uninstall regression validation for the x64 package.

## 0.4.5 - 2026-08-30

- Removed two missed launcher source-package markers (`App.config` and `app.manifest`) during full uninstall.
- Removed the verified outer installation container when installer-managed app, Harness, and data share that container and it becomes empty.
- Preserved Git source checkouts, reparse points, drive roots, reused components, and installation folders containing any unrelated files.
- Added a full-uninstall regression fixture covering managed Harness, data, legacy source markers, launcher files, and the outer folder.

## 0.4.4 - 2026-08-30

- Fixed uninstall detection when the uninstaller is launched from a different extracted package or source checkout than the configured desktop app.
- Added a per-user Windows install record and safe fallback discovery through owned desktop and Start menu shortcuts.
- Redirected cleanup to the verified installed uninstaller so component ownership and path checks remain bound to the correct installation.

## 0.4.3 - 2026-08-30

- Fixed first-run setup failing with “Illegal characters in path” when `DSH-Desktop.exe` forwarded a portable directory ending in a backslash.
- Correctly escaped trailing backslashes in quoted Windows process arguments across the desktop launcher, setup entry point, and uninstaller.
- Added release regression checks for paths containing spaces, Chinese characters, and drive roots.

## 0.4.2 - 2026-08-30

- Allowed users to explicitly remove a verified existing Harness during uninstall, even when it was reused rather than downloaded by DSH Desktop.
- Added a path-specific secondary confirmation for Harness deletion, with a stronger warning when the directory may contain user changes.
- Hardened Harness cleanup with exact directory-name, package-identity, required-marker, launcher-overlap, and reparse-point checks; Harness remains preserved by default.
- Preserved DSH Desktop Git source checkouts during uninstall so local development repositories are not mistaken for installed payloads.

## 0.4.1 - 2026-08-28

- Enabled Per-Monitor V2 DPI awareness for the native desktop host so WebView2 renders at the monitor's native scale instead of being bitmap-stretched by Windows.
- Added Windows 10 compatibility metadata and DPI-based WinForms auto-scaling for correct behavior across monitors with different scale factors.
- Added release validation that prevents builds from shipping without the high-DPI runtime configuration and embedded compatibility manifest.

## 0.4.0 - 2026-08-28

- Replaced the Edge app-mode launcher with a native .NET Framework WinForms + WebView2 desktop host.
- Added a bilingual graphical installer with user-selected install location, Node.js strategy, optional shortcuts, and launch-after-install.
- Added reuse-first detection for existing official Harness checkouts, compatible Node.js runtimes, data directories, and WebView2.
- Added repair detection for Harness directories moved with broken pnpm links.
- Added a standalone setup EXE with an embedded, path-validated payload and a complete portable ZIP distribution.
- Added Microsoft-signed WebView2 Evergreen Runtime bootstrap when the runtime is missing.
- Added ownership-aware uninstall choices for installer-managed Harness, portable Node.js, and data; data remains opt-in with secondary confirmation.
- Added a process Job Object, strict loopback navigation policy, token-redacted diagnostics, and ephemeral WebView2 user-data cleanup.

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
