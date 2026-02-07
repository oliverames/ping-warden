# Ping Warden

Ping Warden prevents AWDL-driven latency spikes on macOS for gaming and other real-time workloads.

## Version 2.1.1 Highlights

- Dashboard visual hierarchy and card spacing were refined for better scanability.
- Ping history now includes a `1 min` range and explicit chart zoom context.
- Timeframe changes zoom the chart window without clearing measurement history.
- Connection settings were reorganized into aligned rows for cleaner control layout.
- Added optional live metrics in the menu dropdown (current ping + interventions).
- General `HOW IT WORKS` section now fills available width consistently.

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
