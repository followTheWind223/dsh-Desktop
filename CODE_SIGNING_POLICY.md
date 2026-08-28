# Code signing policy

For approved signed releases: Free code signing provided by [SignPath.io](https://signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

Releases published before the SignPath integration is approved remain unsigned and are identified as such in the release documentation.

## Scope

Only binaries maintained and built by the DSH Desktop project are eligible for signing:

- `DSH-Desktop.exe`
- `DSH-Setup.exe`
- `Uninstall-DSH-Desktop.exe`

The project does not sign DeepSeek Harness, Microsoft WebView2 components, Node.js, or any other third-party binary. Those components retain their upstream identity and signatures, when present.

## Team roles

- Authors, committers, and reviewers: [followTheWind223](https://github.com/followTheWind223)
- Signing approver: [followTheWind223](https://github.com/followTheWind223)

Changes submitted by other contributors must be reviewed by the maintainer before they are merged. Every production signing request requires manual approval by the signing approver.

## Release requirements

Signed releases must:

1. Be built from a version tag in the public GitHub repository by a GitHub-hosted Windows runner.
2. Use the committed build scripts and locked dependencies.
3. Submit the unsigned project binaries to SignPath through the verified GitHub build integration.
4. Embed already signed application and uninstaller binaries before the outer setup executable is signed.
5. Verify every Authenticode signature and timestamp before packaging.
6. Generate SHA-256 release checksums only after signing is complete.
7. Stop the release if build, signing, signature verification, or release validation fails.

See the project [Privacy policy](PRIVACY.md) and [Security policy](SECURITY.md) for related requirements.
