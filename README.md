# Ping Warden

Eliminate network latency spikes on macOS by controlling AWDL (Apple Wireless Direct Link).

## Download

[Download Ping Warden v2.1.1](https://github.com/oliverames/ping-warden/releases/latest) (macOS 13.0+)

The app is Developer ID signed and notarized.

## What’s New in 2.1.1

- Dashboard card hierarchy and spacing tuned for cleaner information flow.
- Connection settings reorganized into aligned rows for better readability.
- Fixed General `HOW IT WORKS` section width so it fills the settings panel properly.
- Added a `1 min` ping history timeframe and clearer zoom feedback (`Zoom: last ...`).
- Timeframe switching now visibly zooms to the selected window without clearing data.
- Added optional live menu dropdown metrics (current ping + AWDL interventions).

## Core Features

- Sub-millisecond helper response to keep AWDL down before latency spikes land.
- No recurring password prompts (SMAppService + bundled helper).
- Dashboard with ping, jitter, packet loss, and intervention tracking.
- Launch at login and optional Game Mode automation.
- Control Center widget support on macOS 26+.

## Documentation

- [Full Documentation](AWDLControl/README.md)
- [Quick Start](AWDLControl/QUICKSTART.md)
- [Troubleshooting](AWDLControl/TROUBLESHOOTING.md)

## Credits

- [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller) for AF_ROUTE monitoring inspiration.
- [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl) for SMAppService + XPC architecture inspiration.

## License

MIT License. Copyright (c) 2025-2026 Oliver Ames.
