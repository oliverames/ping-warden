# Ping Warden

**Eliminate network latency spikes on macOS by controlling AWDL (Apple Wireless Direct Link)**

Perfect for gaming, video calls, and any latency-sensitive applications.

## Features

- ⚡ **<1ms response time** - Kernel-level AWDL monitoring
- 🎮 **Zero performance impact** - 0% CPU when idle
- 🔒 **No password prompts** - One-time system approval
- 🎯 **Game Mode detection** - Auto-enable for fullscreen games (Beta)
- 🎛️ **Control Center widget** - Quick toggle from Control Center (Beta)
- 🚀 **Launch at login** - Set it and forget it

## What does it do?

AWDL (Apple Wireless Direct Link) is used by AirDrop, Handoff, and other continuity features. However, it can cause **100-300ms ping spikes** every few seconds, which is devastating for:

- **Gaming** (especially competitive online games)
- **Video calls** (Zoom, Teams, Discord)
- **Live streaming**
- **Remote desktop** (VNC, RDP)

Ping Warden monitors the AWDL interface and keeps it disabled when you need low latency. When you quit the app, AWDL is automatically restored.

## Download

**[Download Ping Warden v2.0.3](https://github.com/oliverames/ping-warden/releases/latest)**

The app is **code-signed and notarized by Apple**, so it will open without any security warnings.

## Installation

1. **Download** the DMG from the link above
2. **Open** the DMG file
3. **Drag** `Ping Warden.app` to the **Applications** folder
4. **Launch** from Applications or Spotlight

That's it! No terminal commands or workarounds needed.

## First Launch Setup

1. **Launch** Ping Warden
2. Click **"Set Up Now"** in the welcome window
3. **Approve** the helper in System Settings → Login Items & Extensions → Login Items
4. The app is now ready to use!

The helper daemon runs only while the app is open and automatically cleans up when you quit.

## Usage

### Menu Bar

Click the antenna icon in the menu bar to:
- Toggle AWDL blocking on/off
- View current status
- Access Settings
- View diagnostics

**Icon states:**
- `📡` (with slash) - AWDL blocked (low latency mode)
- `📡` (no slash) - AWDL allowed (AirDrop/Handoff work)

### Settings

**General:**
- Enable/disable AWDL blocking
- Launch at login
- Show/hide Dock icon

**Automation:**
- **Game Mode Auto-Detect** (Beta) - Automatically enables blocking when fullscreen games are running
  - Requires Screen Recording permission
  - Only detects apps marked as games in their Info.plist
  
- **Control Center Widget** (Beta) - Adds a toggle to Control Center

**Advanced:**
- Test helper response time
- View logs in Console.app
- Re-register helper (if experiencing issues)
- Uninstall helper

## How It Works

Ping Warden uses a privileged helper daemon that:

1. **Monitors** the `awdl0` interface using AF_ROUTE socket (kernel-level)
2. **Detects** when macOS tries to bring AWDL up
3. **Responds** in <1ms to bring it back down
4. **Restores** AWDL to enabled state when you quit

**Why this approach?**
- ✅ No password prompts (SMAppService architecture)
- ✅ Extremely fast response (<1ms)
- ✅ Zero CPU usage when idle
- ✅ Automatic cleanup on exit
- ✅ Secure (helper only runs while app is open)

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

**Optional features:**
- Game Mode Auto-Detect: macOS 15.0+ (requires Screen Recording permission)

## Troubleshooting

### Helper not responding

1. Open Settings → Advanced
2. Click "Re-register Helper"
3. Approve in System Settings if prompted

### AWDL still causing lag

1. Check that monitoring is enabled (menu bar icon should show slash)
2. Open Settings → Advanced → "Test Helper Response"
3. Check Console.app for errors (filter by "awdlcontrol")

### Game Mode not working

1. Ensure you're on macOS 15.0+
2. Grant Screen Recording permission in System Settings → Privacy & Security
3. Only apps marked as games (LSApplicationCategoryType = games) will trigger detection

## Performance

Measured on M1 MacBook Pro:

| Metric | Value |
|--------|-------|
| Response time | <1ms |
| CPU usage (idle) | 0% |
| CPU usage (active) | <0.1% |
| Memory usage | ~8 MB |
| Network overhead | None |

## Known Issues

- Game Mode detection requires Screen Recording permission
- Some third-party networking tools may conflict with AWDL control

## Credits

This project builds on excellent prior work:

- **[jamestut/awdlkiller](https://github.com/jamestut/awdlkiller)** - AF_ROUTE monitoring concept
- **[james-howard/AWDLControl](https://github.com/james-howard/AWDLControl)** - SMAppService + XPC architecture

## License

MIT License - see LICENSE file for details

Copyright (c) 2025-2026 Oliver Ames

## Support

For issues, questions, or feature requests, please open an issue on GitHub.

---

**Note:** This app controls system-level networking. While it's designed to be safe and automatically restores AWDL when you quit, you may want to disable it if you need AirDrop or Handoff. Simply toggle it off in the menu bar or quit the app.
