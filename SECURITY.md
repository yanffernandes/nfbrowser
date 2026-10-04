# Security

This document covers the repository-specific security expectations for NF Browser contributors and maintainers.

## Secrets and Sensitive Data

- Never commit `.env`, signing credentials, private keys, notarization credentials, or any other secret material.
- Do not paste secrets into issues, pull requests, screenshots, or logs shared publicly.
- Keep local release credentials in `.env` and use `.env.example` as the template for required variables.
- Treat generated logs and exported artifacts as potentially sensitive until reviewed.

## Updates

Automatic updates are disabled in NF Browser. Do not restore the upstream Ora appcast or signing key. NF Browser needs its own update feed and signing key before updates can be enabled.

## Release Credentials

The optional signed build script reads these local `.env` values:

- `TEAM_ID`
- `SIGNING_IDENTITY`
- `APP_SPECIFIC_PASSWORD_KEYCHAIN`
- `DEVELOPER_ID_PROFILE`

For the current release flow, see:

- `./scripts/build.sh`
- `./scripts/publish.sh`
- `./scripts/release.sh`

Contributors working on regular code or documentation changes should not need access to signing credentials. `./scripts/publish.sh` and `./scripts/release.sh` stop with a notice until NF Browser has its own release setup.

## Safe Working Practices

- Review `git status` and `git diff --cached` before every commit.
- Do not add private keys, provisioning profiles, or notarization credentials to the repository, even temporarily.
- Be careful when sharing crash logs, build logs, and environment output if they may include local paths, account identifiers, or signing details.
- Follow least-privilege access for Apple Developer and release infrastructure credentials.

## Embedded Agent Terminal

The embedded terminal launches the selected local CLI or an interactive shell as the signed-in macOS user. To make installed tools, user shell configuration, and local CLI sign-in available, the app's release configuration does not enable App Sandbox. A terminal process can access the files and network resources available to that user, subject to normal macOS permissions and prompts. Treat the selected agent CLI and its model/tool configuration as trusted local software.

NF Browser does not read or store provider credentials. Its browser-control bridge listens on loopback only while a terminal session is running and requires a random, session-scoped bearer token passed to that session. The bridge exposes the active tab's bounded page controls; it does not expose arbitrary JavaScript or file operations. Page content remains untrusted input, and the bundled skill's interaction rules are guidance rather than an operating-system security boundary.

The terminal panel discloses that CLI processes run with the user's macOS permissions. Product releases must retain this disclosure and document the sandbox change.

Apple requires App Sandbox for Mac App Store distribution. The embedded terminal is supported only in the current Developer ID distribution unless the process-host design changes or the feature is disabled for an App Store build. See [Apple's App Sandbox documentation](https://developer.apple.com/documentation/security/app-sandbox).

## Reporting Security Issues

If you discover a security issue or accidental secret exposure, do not open a public issue with exploit details or credential contents. Report it privately through [GitHub Security Advisories](https://github.com/yanffernandes/nfbrowser/security/advisories/new).
