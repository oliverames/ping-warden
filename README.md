# Ping Warden

A macOS menu bar app that disables AWDL to eliminate network latency spikes during gaming and video calls.

*(Internally known as AWDLControl)*

<a href="https://www.buymeacoffee.com/oliverames" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/arial-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## The Problem

AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, and Handoff. It also causes:

- **100-300ms ping spikes** during gaming or video calls
- Wi-Fi performance degradation
- Intermittent connection drops

## The Solution

Ping Warden keeps AWDL disabled with **<1ms response time** and **0% CPU** when idle.

> **Trade-off**: While active, AirDrop/AirPlay/Handoff won't work. Toggle off when needed.

## What's New in v2.0

- **No more password prompts!** Uses modern SMAppService APIs for one-time system approval
- **Clean uninstall** - Just drag the app to Trash, macOS handles the rest
- **Helper bundled inside app** - Everything is self-contained
- **Simpler architecture** - XPC communication instead of launchctl scripts

## Features

- **Menu Bar Control** - Quick toggle from the menu bar antenna icon
- **Control Center Widget** (Beta) - Native macOS Control Center integration
- **Game Mode Auto-Detect** (Beta) - Automatically enables blocking when fullscreen games are detected
- **Launch at Login** - Start automatically with your Mac
- **Show/Hide Dock Icon** - Run as a background app or show in the Dock

## Installation

```bash
git clone https://github.com/oliverames/ping-warden.git
cd ping-warden
./build.sh
cp -r "AWDLControl/build/Release/Ping Warden.app" /Applications/
```

On first launch:
1. Click **Set Up Now** when prompted
2. Approve in **System Settings → Login Items** (one-time)
3. That's it! No password prompts after initial setup.

## Usage

### Menu Bar

Click the antenna icon in the menu bar:

| Icon | State |
|------|-------|
| Slashed antenna | AWDL blocked (monitoring active) |
| Normal antenna | AWDL available (monitoring off) |

### Settings

Access Settings from the menu bar to configure:

- **General**: Enable/disable blocking, Launch at Login
- **Advanced**: Control Center Widget (Beta), Game Mode Auto-Detect (Beta), Show Dock Icon, Diagnostics

### Control Center Widget (Beta)

Enable in Settings to add an AWDL toggle to the macOS Control Center. When enabled, the menu bar icon is hidden.

> **Note**: The Control Center widget requires the app to be code-signed with a Developer ID certificate. When building from source without code signing, this feature is disabled and the menu bar icon remains visible. To enable, open the project in Xcode, configure signing with your Apple Developer account, and rebuild.

### Game Mode Auto-Detect (Beta)

When enabled, Ping Warden automatically activates AWDL blocking when it detects a fullscreen application (game mode). Great for cloud gaming services like GeForce NOW, Xbox Cloud Gaming, or Steam.

## Requirements

- macOS 13.0+ (Ventura or later)
- Xcode 16.0+ (for building)

## How It Works

Ping Warden v2.0 uses a modern architecture:

1. **Helper daemon** bundled inside the app (Contents/MacOS/AWDLControlHelper)
2. **SMAppService** registers the helper as a LaunchDaemon with one-time system approval
3. **XPC communication** between the app and helper for control commands
4. **AF_ROUTE sockets** monitor the network stack and instantly bring awdl0 down when macOS enables it

The helper only runs while the app is running. When you quit Ping Warden, the helper exits and AWDL is automatically restored.

## Uninstall

Simply **drag Ping Warden.app to the Trash**. macOS automatically removes the helper registration.

## Credits

- [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller) - Original AWDL monitoring concept using AF_ROUTE sockets
- [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl) - SMAppService + XPC architecture inspiration

## License

MIT
