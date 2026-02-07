# Ping Warden

Ping Warden is a macOS app that keeps your connection stable by preventing AWDL-driven latency spikes.

AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, and Handoff, but it can introduce sudden ping spikes during cloud gaming, competitive play, and voice/video calls. Ping Warden gives you one-click control over that behavior.

[![Download](https://img.shields.io/badge/Download-Latest_Release-blue?style=for-the-badge)](https://github.com/oliverames/ping-warden/releases/latest)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-Support-orange?style=for-the-badge)](https://www.buymeacoffee.com/oliverames)

## Download

[Download Ping Warden v2.1.1](https://github.com/oliverames/ping-warden/releases/latest) (macOS 13.0+)

The app is Developer ID signed, notarized, and includes Sparkle for in-app updates.

## What Ping Warden Does

- Blocks AWDL while protection is enabled to reduce random latency spikes.
- Monitors connection quality with a live dashboard:
  - Current ping, average, best/worst, jitter, and packet loss.
  - Timeline of latency spikes and AWDL interventions.
  - Non-destructive timeframe zoom (1 min, 5 min, 15 min, 30 min, 1 hour).
- Supports menu bar workflows with optional live dropdown metrics.
- Lets you automate behavior with launch-at-login and Game Mode auto-detect.

## Why This Is Better Than `sudo ifconfig awdl0 down`

Running a one-off command can be useful for quick testing, but it is not operationally equivalent to Ping Warden.

- Persistence vs one-shot:
  - `sudo ifconfig awdl0 down` is a single state change.
  - macOS can bring AWDL back up at any time; Ping Warden keeps monitoring and re-applies protection automatically.
- Event-driven kernel-level behavior vs delayed manual reaction:
  - A shell command is manual and reactive.
  - Ping Warden’s helper listens to route/interface events and counters AWDL-UP transitions immediately (sub-millisecond class response), rather than letting AWDL stay up for seconds before an operator notices and runs a command.
- No repeated terminal/sudo workflow:
  - Manual control usually means frequent terminal use and repeated privileged operations.
  - Ping Warden uses one-time helper approval, then controlled background operation from UI/menu.
- Visibility and diagnostics:
  - Command-line toggling gives little built-in telemetry.
  - Ping Warden shows live ping quality, history, spikes, and AWDL intervention counts so behavior is observable.
- Safer day-to-day control:
  - Ping Warden has explicit enable/disable paths, pause/resume behaviors, startup handling, and diagnostics tooling.
  - You can intentionally restore default behavior from the app without remembering shell commands.
- Better for non-destructive tuning:
  - Dashboard timeframe switching zooms data windows without deleting history, making comparisons easier.

## Feature Highlights

- Fast helper response path for AWDL state changes.
- No recurring password prompts after one-time setup approval.
- Real-time ping chart with quality bands and event markers.
- Endpoint options:
  - Local gateway and major DNS targets.
  - Gaming endpoints and GeForce NOW discovery targets.
  - Auto-select nearest endpoint by baseline probes.
- Optional Control Center integration on supported systems.
- Sparkle update integration (`Check for Updates...`) in both:
  - Menu bar menu.
  - Frontmost app menu when settings/about windows are active.

## Implementation Details

Ping Warden uses a modern macOS architecture designed for reliability and low overhead.

- App + helper model:
  - Main app provides UI, preferences, dashboard, diagnostics, and automation.
  - Bundled helper performs privileged AWDL control and monitoring work.
- Service registration:
  - Uses `SMAppService` for one-time system approval and stable background lifecycle.
- Communication:
  - XPC boundary between app and helper for commands, status, and counters.
- Monitoring approach:
  - Route/interface change monitoring with rapid AWDL state correction.
- Update pipeline:
  - Sparkle + signed appcast feed + EdDSA signature validation.

## Quick Start

### 1) Install

1. Download the latest DMG from [Releases](https://github.com/oliverames/ping-warden/releases/latest).
2. Drag `Ping Warden.app` to `/Applications`.
3. Launch Ping Warden.

### 2) Complete One-Time Setup

1. Click `Set Up Now`.
2. Approve the helper in System Settings when prompted.
3. Return to Ping Warden and confirm status shows active monitoring when enabled.

### 3) Verify and Tune

1. Open `Settings -> Dashboard`.
2. Select a ping target and update interval.
3. Use timeframe controls to zoom into recent windows without clearing history.
4. Enable `Menu Dropdown Metrics` from `Settings -> General` if you want live ping/intervention values in the menu.

## Full Documentation

Core docs are in the `AWDLControl` directory.

- [Quick Start](AWDLControl/QUICKSTART.md)
  - Fast install/setup walkthrough.
- [Full Documentation](AWDLControl/README.md)
  - Architecture summary, feature coverage, and operational notes.
- [Troubleshooting](AWDLControl/TROUBLESHOOTING.md)
  - Setup failures, runtime diagnostics, reset/recovery workflows.

Additional references:

- [Release Notes](RELEASE_NOTES.md)
- [Project License](LICENSE)

## Troubleshooting

Common first checks:

1. Confirm helper is registered and status is not `Not Set Up`.
2. Run `Settings -> Advanced -> Test Helper Response`.
3. Open `Settings -> Advanced -> Export Diagnostics` and review the generated bundle.
4. If update detection looks wrong, use `Check for Updates...` from the app/menu bar and verify app version in About.

Useful docs and links:

- [Troubleshooting Guide](AWDLControl/TROUBLESHOOTING.md)
- [GitHub Issues](https://github.com/oliverames/ping-warden/issues)

## Build From Source

```bash
git clone https://github.com/oliverames/ping-warden.git
cd ping-warden/AWDLControl
open AWDLControl.xcodeproj
```

Build and run from Xcode with signing configured for all targets.

## Credits

- [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller) for AWDL monitoring inspiration.
- [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl) for SMAppService + XPC architecture inspiration.

## License

MIT License. Copyright (c) 2025-2026 Oliver Ames.
