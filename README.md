# PowerSentry

**[English](README.md) | [简体中文](README.zh-CN.md)**

[![CI](https://github.com/tooandy/PowerSentry/actions/workflows/ci.yml/badge.svg)](https://github.com/tooandy/PowerSentry/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/tooandy/PowerSentry)](https://github.com/tooandy/PowerSentry/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**A local-only macOS power diagnostics and anomaly-monitoring app.**

PowerSentry lives in the macOS menu bar and helps explain battery drain by observing battery telemetry, process resource usage, network throughput, and sleep/wake activity. It learns a personal power baseline and reports sustained anomalies without automatically terminating processes or uploading telemetry.

> **Current release target:** Apple Silicon (arm64), macOS 14 or later. The app UI supports nine languages and follows the macOS preferred language. Public builds are ad-hoc signed and are not notarized by Apple.

## Features

- **Menu-bar monitor:** battery percentage, live discharge power, and an estimated time to 20% battery.
- **Personal power baseline:** learns from stable, low-load battery samples.
- **Anomaly detection:** sustained system power, per-process high CPU, heavy downloads, and frequent DarkWake events.
- **Process diagnostics:** per-process CPU and memory rankings.
- **Network diagnostics:** per-process download and upload throughput from macOS nettop counters.
- **Sleep and wake diagnostics:** recent power events and active power assertions from pmset.
- **Local history:** SQLite telemetry and incidents, with samples retained for the latest seven days.
- **Local notifications:** macOS notifications for newly detected incidents.
- **Nine-language UI:** English, Simplified/Traditional Chinese, Spanish, Korean, Japanese, German, French, and Dutch, selected automatically from macOS language preferences.
- **Menu-bar-only lifecycle:** no Dock icon or Cmd+Tab entry; closing the dashboard leaves monitoring active.

## Download and install

1. Open [GitHub Releases](https://github.com/tooandy/PowerSentry/releases).
2. Download the latest PowerSentry-*-arm64.dmg or PowerSentry-*-arm64.zip.
3. Move PowerSentry.app to /Applications or ~/Applications.
4. Public releases are **not signed with an Apple Developer ID and are not notarized**. If Gatekeeper blocks the first launch, use Finder's **Control-click → Open** flow or review the app-specific option in **System Settings → Privacy & Security**. The wording varies by macOS version.

PowerSentry does not ask you to disable Gatekeeper globally. Only install builds you trust; the source and build workflows are public for inspection.

## Language

PowerSentry supports all nine languages below:

- English (en)
- Simplified Chinese (zh-Hans)
- Traditional Chinese (zh-Hant)
- Spanish (es)
- Korean (ko)
- Japanese (ja)
- German (de)
- French (fr)
- Dutch (nl)

The app follows the macOS preferred language. Unsupported languages fall back to English. Change the preferred language in **System Settings → General → Language & Region**, then relaunch PowerSentry.

## Privacy and safety

- **Local-only storage:** the database is stored at ~/Library/Application Support/PowerSentry/powersentry.sqlite.
- **No telemetry upload:** the app does not include a cloud service, analytics, remote listener, or outbound telemetry.
- **Network counters only:** nettop is used to read per-process byte counters; PowerSentry does not capture packet payloads, message contents, or individual remote endpoints.
- **Explicit process approval:** PowerSentry never kills a process automatically. If you choose to terminate a high-CPU process, the app revalidates the PID, process start time, executable path, and current CPU usage, then sends SIGTERM only. It never escalates to SIGKILL.
- **No administrator helper:** the app does not install a privileged helper or modify system sleep, VPN, or login-item settings.
- **Notifications:** macOS notification permission is requested for local anomaly alerts.

Process and power information is collected using macOS system interfaces and command-line telemetry. Some process details may be restricted by macOS or by the permissions available to the current user.

## Sampling and detection

| Signal | Collection / rule |
|---|---|
| Battery and process CPU/memory | Approximately every 10 seconds |
| Persisted telemetry | Every 30 seconds; top 20 processes and top 12 network processes |
| Per-process network throughput | Approximately every 30 seconds |
| Power assertions and sleep/wake events | Approximately every 60 seconds |
| System power anomaly | Above max(2.2 × baseline, baseline + 2 W) for about 2 minutes |
| Per-process CPU anomaly | At least 85% for about 2 minutes |
| Per-process download anomaly | At least 1 MB/s across two independent network samples |
| DarkWake anomaly | At least 10 events in 10 minutes |

The baseline starts with a conservative default and learns from stable, low-load battery samples. Runtime estimates are approximate and should not be treated as battery-health measurements.

## Build from source

Requirements:

- macOS 14 or later
- Apple Swift toolchain / Xcode Command Line Tools
- Swift 5.10 or later
- Apple Silicon for the current release packaging workflow

    git clone https://github.com/tooandy/PowerSentry.git
    cd PowerSentry

    # Run the built-in logic tests
    ./scripts/self-test.sh

    # Build the app bundle, bundle both languages, and ad-hoc sign it
    ./scripts/build-app.sh

    # Launch the app
    open dist/PowerSentry.app

For a command-line telemetry check:

    swift run PowerSentry --diagnose

The build does not require an Apple Developer membership, Developer ID certificate, signing secret, or notarization credentials.

## CI and releases

GitHub Actions is configured for:

- **Pull requests and pushes to main:** validate app metadata and localization tables, compile the app, run self-tests, verify the app bundle and ad-hoc signature, and upload a short-lived CI artifact.
- **Version tags (v*):** verify that the tag matches CFBundleShortVersionString, build and test the app, package a ZIP and DMG, generate SHA256SUMS, and publish a GitHub Release using the checked-in bilingual release notes.

To publish a new version:

1. Update CFBundleShortVersionString in Resources/Info.plist.
2. Update CHANGELOG.md and add .github/release-notes/vX.Y.Z.md with English and Simplified Chinese notes (the application UI supports all nine languages).
3. Commit and push the changes to main.
4. Create and push the matching tag:

    git tag v0.2.0
    git push origin v0.2.0

The tag version must match the app's CFBundleShortVersionString. The release workflow publishes the ZIP, DMG, and checksums automatically.

## Current limitations

- Per-process network throughput is available, but individual remote endpoints are not attributed.
- A fully sleeping Mac pauses sampling until macOS wakes it.
- The personal baseline needs several minutes of normal usage to become useful; confidence improves with longer history.
- Login-at-startup is not registered.
- Release builds currently target Apple Silicon (arm64); Intel builds are not published.
- Ad-hoc signatures are not equivalent to Developer ID signatures. macOS may require a first-launch confirmation and may ask users to re-approve notification permissions after replacing an app build.

## License

MIT. See [LICENSE](LICENSE).
