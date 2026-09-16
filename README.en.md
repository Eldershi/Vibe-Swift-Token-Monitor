<p align="center">
  <img src="docs/assets/app-icon.png" width="128" height="128" alt="Vibe Swift Token Monitor app icon">
</p>

# Vibe Swift Token Monitor

**[简体中文](README.md) · English**

A native macOS monitor for Codex usage, account quotas, and activity history. Includes an independent background collector—no separate Node.js installation or Electron app required.

## Download

### [⬇ Download latest: 0.6.0 · Apple Silicon](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.6.0/Token-Monitor-Native-0.6.0-41-arm64.zip)

**macOS 26+ · Apple Silicon · Build 41**

[Release notes](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/latest) · [SHA-256 checksums](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.6.0/SHA256SUMS)

Currently focused on Codex; other tools are experimental. This project is at an early validation stage, is not notarized, and is not yet recommended for general use. Testing has been performed on macOS 27.

## Features

- **Usage and quotas:** model and device details for the past 24 hours, past 30 days, and latest 24 months, plus quotas from configured accounts.
- **Dynamic activity history:** hourly, daily, and monthly trends switch with the selected range; heatmaps and records distinguish missing data from reported zeroes.
- **Donuts and colors:** rounded model, device, and quota charts with hover expansion, recommended palettes, and colors saved per item.
- **Quota attribution:** estimates each device and model's share of quota used in the current window from recorded tokens and pricing weights.
- **Customizable interface:** fixed 320 pt content width, section visibility and order, menu bar metrics, and theme colors. Supports Simplified Chinese and English.
- **Independent collection and Hub:** collection continues after closing the interface; connect to an existing Hub for multi-device totals.
- **Updates with confirmation:** checks GitHub for stable releases. Automatic checking is off by default; downloading and installation require confirmation.

Costs are **API-equivalent estimates**, not subscription bills. This is not an official OpenAI application.

## Get started

1. Download and unzip, then move the app to your Applications folder. Quit the old interface and keep a backup before upgrading.
2. Open the app, allow background activity if prompted, and wait for the first scan.
3. Choose local collection or configure an existing Hub in Settings → Data. If quota access expires, sign in again using the original tool.

Versions 0.5.1 and earlier require a manual download to upgrade. From 0.5.2 onward, use Settings → About to check for future updates. The app name and installation identity retain the original Beta channel for data and background-service compatibility.

[Usage and uninstalling](docs/USAGE.md#english) · [Build from source](docs/BUILDING.md) · [Report an issue](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/issues)

## Credits and licensing

An independently maintained native macOS derivative, reusing parts of the MIT-licensed backend from [Javis603/token-monitor](https://github.com/Javis603/token-monitor) v0.56.0, plus Node.js, Tokscale, and Sparkle. It does not bundle the Electron interface and is not an official upstream client.

[Third-party notices](TokenMonitorNative/THIRD_PARTY_NOTICES.md) · [Backend provenance](TokenMonitorNative/Backend/UPSTREAM.md)

Upstream copyright notices and licenses are retained. No unified open-source license has yet been assigned to this repository's new code.
