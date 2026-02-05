# Ping Warden

**Eliminate network latency spikes on macOS by controlling AWDL (Apple Wireless Direct Link)**

Perfect for gaming, video calls, and any latency-sensitive applications.

<a href="https://www.buymeacoffee.com/oliverames" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/arial-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## Download

**[Download Ping Warden v2.0.3](https://github.com/oliverames/ping-warden/releases/latest)** (macOS 13.0+)

The app is **code-signed and notarized by Apple**, so it will open without any security warnings.

## Installation

1. Download the DMG from the link above
2. Open the DMG file
3. Drag **Ping Warden** to **Applications**
4. Launch from Applications or Spotlight

That's it! No terminal commands or workarounds needed.

## Features

- **<1ms response time** - Kernel-level AWDL monitoring
- **Zero performance impact** - 0% CPU when idle
- **No password prompts** - One-time system approval
- **Game Mode detection** - Auto-enable for fullscreen games (Beta)
- **Control Center widget** - Quick toggle from Control Center (Beta)
- **Launch at login** - Set it and forget it

## What does it do?

AWDL (Apple Wireless Direct Link) is used by AirDrop, Handoff, and other continuity features. However, it can cause **100-300ms ping spikes** every few seconds, which is devastating for:

- **Gaming** (especially competitive online games)
- **Video calls** (Zoom, Teams, Discord)
- **Live streaming**
- **Remote desktop** (VNC, RDP)

Ping Warden monitors the AWDL interface and keeps it disabled when you need low latency. When you quit the app, AWDL is automatically restored.

## Documentation

For detailed documentation, troubleshooting, and technical information, see:

- [Full Documentation](AWDLControl/README.md)
- [Quick Start Guide](AWDLControl/QUICKSTART.md)
- [Troubleshooting](AWDLControl/TROUBLESHOOTING.md)

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## Credits

This project builds on excellent prior work:

- **[jamestut/awdlkiller](https://github.com/jamestut/awdlkiller)** - AF_ROUTE monitoring concept
- **[james-howard/AWDLControl](https://github.com/james-howard/AWDLControl)** - SMAppService + XPC architecture

## License

MIT License - see [LICENSE](LICENSE) file for details

Copyright (c) 2025-2026 Oliver Ames
