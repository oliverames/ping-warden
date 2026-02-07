# Ping Warden

Ping Warden prevents AWDL-driven latency spikes on macOS for gaming and other real-time workloads.

## Version 2.1.0 Highlights

- Latency spike timeline with AWDL intervention event markers.
- Diagnostics export from Settings (`Advanced -> Export Diagnostics`).
- Menu bar quick actions: `Pause Blocking (10 Minutes)` and `Resume Blocking`.
- Expanded target presets and baseline latency auto-select.
- Game Mode auto-detect now restores the exact prior user state.
- Control Center checks remain gated to macOS 26+ APIs.
- Widget toggles are hardened for start/stop when the main app is not running.
- Improved monitor state consistency, reconnection handling, and observer safety.

## Features

- Kernel-adjacent AWDL suppression strategy with helper daemon.
- No repeated privilege prompts after initial setup approval.
- Real-time dashboard:
  - Current ping, average, min/max, jitter, packet loss.
  - Ping history chart and latency quality coloring.
  - Intervention counter and timeline view.
- Targeting:
  - Local gateway, major DNS resolvers, gaming APIs, GeForce NOW zones.
  - Automatic nearest-target selection by baseline probe.
- Automation:
  - Launch at login.
  - Game Mode auto-detect (beta, requires Screen Recording permission).
  - Control Center widget mode (beta, macOS 26+ and proper signing required).

## Setup

1. Launch Ping Warden.
2. Click `Set Up Now`.
3. Approve helper registration in System Settings when prompted.
4. Enable/disable AWDL blocking from the menu bar or Settings.

## Dashboard Notes

- Baseline auto-select runs short TCP probes across presets and picks the lowest robust average latency.
- Timeline records:
  - Ping spikes above dynamic threshold.
  - AWDL intervention deltas from helper counters.

## Diagnostics

- `Advanced -> Export Diagnostics` writes a timestamped support snapshot to Desktop.
- `Advanced -> Open Console` opens logs quickly for deeper inspection.

## System Requirements

- macOS 13.0 or later.
- Apple Silicon or Intel.
- Optional:
  - Game Mode auto-detect: Screen Recording permission.
  - Control Center widget: macOS 26+ Control Widget API support.

## Credits

- [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller)
- [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl)

## License

MIT License. Copyright (c) 2025-2026 Oliver Ames.
