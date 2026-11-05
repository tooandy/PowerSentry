# Changelog

## [0.1.0] - 2026-11-05

### Added
- Initial public release of PowerSentry for macOS.
- Menu-bar-only power monitor with live battery percentage and discharge power.
- Battery runtime estimate to 20%, personal power baseline learning, and sustained anomaly detection.
- Per-process CPU and memory sampling, plus per-process network throughput.
- Sleep / wake history and current power assertion inspection.
- Seven days of local telemetry and incidents stored in SQLite.
- Local notifications and explicit user approval before sending SIGTERM to a process.
- English and Simplified Chinese interface localization, following the macOS preferred language.
- GitHub Actions CI, Apple Silicon app packaging, SHA-256 checksums, and tag-triggered GitHub Releases.

### Security and privacy
- All telemetry remains on the local Mac; no cloud service, analytics, or outbound telemetry is included.
- PowerSentry never automatically terminates a process and never escalates to SIGKILL.
- Public release builds use an ad-hoc signature and are not notarized by Apple.
