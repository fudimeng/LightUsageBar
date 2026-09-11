# LightUsageBar 0.1.0

A lightweight native macOS menu bar app for Claude Code and Codex subscription limits.

## Download and install

Download `LightUsageBar-0.1.0-macos-universal.zip` from the release assets, unzip it,
and drag `LightUsageBar.app` to Applications. Launch it to find it in the menu bar.
Requires macOS 14 or later; supports both Apple Silicon and Intel.
A SHA-256 checksum file is provided alongside the ZIP.

## Features

- Two menu bar values per provider: 5-hour remaining allowance above, weekly remaining allowance below.
- Horizontal allowance bars and reset times displayed to the minute with the local UTC offset.
- Automatic refresh every five minutes and manual refresh from the menu.
- Missing allowance windows display “—”.

## Account setup

Codex requires an installed, signed-in Codex CLI. The app searches `/opt/homebrew/bin`,
`/usr/local/bin`, and standard system executable directories.
Claude requires valid Claude Code credentials in macOS Keychain; the first launch may request Keychain access.
If the login expires, open Claude Code or run `/login`, then refresh the app.
Each user supplies their own account. No account credentials are included in the download.
The current allowance panel uses Chinese labels.

## Signing status

This build is ad-hoc signed and **not notarized by Apple**. macOS may block a copy downloaded from the internet.
If you trust the source, use System Settings → Privacy & Security → Open Anyway when available.
If that option is unavailable or device policy prevents it, wait for a Developer ID-signed and notarized release.

## Build and license

Run `zsh scripts/package-distribution.sh` from the project directory to create a ZIP and checksum in `dist/`.
Licensed under the MIT License. The LICENSE file is included as a separate release asset.
