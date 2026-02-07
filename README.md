# Ping Warden

Eliminate network latency spikes on macOS by controlling AWDL (Apple Wireless Direct Link).

## Download

[Download Ping Warden v2.1.0](https://github.com/oliverames/ping-warden/releases/latest) (macOS 13.0+)

The app is Developer ID signed and notarized.

## What’s New in 2.1.0

- Latency spike timeline with AWDL intervention markers.
- One-click diagnostics export from Settings to Desktop.
- Menu bar quick actions: pause blocking for 10 minutes and resume.
- Expanded target presets (DNS + gaming endpoints).
- Auto-select nearest endpoint using baseline latency scan.
- Game Mode auto-detect now restores the exact pre-activation state.
- Widget toggle path hardened for app-not-running starts.
- Control Center widget checks remain intentionally macOS 26+.
- Reconnect/backoff and monitor state notification hardening.
- Release/CI guardrails improved (version checks, appcast XML checks, smoke tests).

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
