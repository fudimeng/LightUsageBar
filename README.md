# LightUsageBar

An intentionally small native macOS menu-bar app for Claude Code and Codex subscription limits. It has no server, database, analytics, history graph, or third-party runtime dependencies.

## Requirements

- macOS 14 or later
- A logged-in `codex` CLI for Codex limits
- A logged-in `claude` CLI for Claude Code limits

## Download

Download the universal macOS ZIP from [GitHub Releases](https://github.com/fudimeng/LightUsageBar/releases/latest).
It supports Apple Silicon and Intel. Unzip it and move LightUsageBar.app to Applications.
The app appears in the menu bar, not the Dock.

This release is ad-hoc signed and **not notarized by Apple**. macOS may block an internet-downloaded copy.
If you trust the source, use System Settings → Privacy & Security → Open Anyway when available.
See [installation and distribution notes](DISTRIBUTION.md).

Each provider shows two menu-bar numbers: 5-hour remaining allowance above, weekly remaining allowance below.
The panel shows horizontal remaining-allowance bars and reset times to the minute with the local UTC offset.
Missing windows display “—”. Claude login expiration requires refreshing your Claude Code login.

## Build and run

```bash
./scripts/package-app.sh
open LightUsageBar.app
```

The app uses the menu bar only. It refreshes every five minutes and can be refreshed from its menu. The packaging script creates an ad-hoc-signed `LightUsageBar.app`; no Apple Developer account is needed for local use.

## Privacy model

- Codex is queried through its local `codex app-server --stdio` protocol.
- Claude's OAuth access token is read from the existing `Claude Code-credentials` Keychain entry and sent only to Anthropic's OAuth usage endpoint.
- No credential, usage value, or log is written to disk by this app.

The provider endpoints and CLI protocol can change. Errors are shown in the menu instead of being silently hidden.

## Build a universal distribution

```bash
zsh scripts/package-distribution.sh
```

This creates the application ZIP and SHA-256 checksum in `dist/`, with debug information removed and source paths remapped.
