# AWDLControl

A macOS menu bar app that disables AWDL to eliminate network latency spikes during gaming and video calls.

## The Problem

AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, and Handoff. It also causes:

- **100-300ms ping spikes** during gaming or video calls
- Wi-Fi performance degradation
- Intermittent connection drops

## The Solution

AWDLControl keeps AWDL disabled with **<1ms response time** and **0% CPU** when idle. Based on [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut.

> **Trade-off**: While active, AirDrop/AirPlay/Handoff won't work. Toggle off when needed.

## Features

- **Menu Bar Control** - Quick toggle from the menu bar antenna icon
- **Control Center Widget** (Beta) - Native macOS Control Center integration
- **Game Mode Auto-Detect** (Beta) - Automatically enables blocking when fullscreen games are detected
- **Launch at Login** - Start automatically with your Mac (reduces password prompts)
- **Show/Hide Dock Icon** - Run as a background app or show in the Dock

## Installation

```bash
git clone https://github.com/oliverames/Cloud-Gaming-Optimizer.git
cd Cloud-Gaming-Optimizer
./build.sh
cp -r AWDLControl/build/Release/AWDLControl.app /Applications/
```

On first launch, click **Set Up Now** and enter your password once to install the daemon.

## Usage

### Menu Bar

Click the antenna icon in the menu bar:

| Icon | State |
|------|-------|
| Slashed antenna | AWDL blocked (monitoring active) |
| Normal antenna | AWDL available (monitoring off) |

### Settings

Access Settings from the menu bar to configure:

- **General**: Launch at Login, Control Center Widget (Beta), Game Mode Auto-Detect (Beta), Show Dock Icon
- **Advanced**: Reinstall/test daemon, uninstall, view logs

### Control Center Widget (Beta)

Enable in Settings to add an AWDL toggle to the macOS Control Center. When enabled, the menu bar icon is hidden.

### Game Mode Auto-Detect (Beta)

When enabled, AWDLControl automatically activates AWDL blocking when it detects a fullscreen application (game mode). Great for cloud gaming services like GeForce NOW, Xbox Cloud Gaming, or Steam.

## Requirements

- macOS 26.0+ (Tahoe)
- Xcode 16.0+ (for building)

## How It Works

A lightweight C daemon monitors the network stack via AF_ROUTE sockets. When macOS enables AWDL, the daemon instantly brings it back down using ioctl(). The Swift app provides the UI and manages the daemon via launchctl.

## Reducing Password Prompts

The daemon requires administrator privileges to start/stop. To minimize password prompts:

1. **Enable Launch at Login** - The daemon starts automatically at boot, so you rarely need to toggle it manually
2. **Keep it running** - If you leave blocking enabled, no password is needed until you toggle

## Uninstall

From the app: **Settings > Advanced > Uninstall Everything**

Or manually:
```bash
sudo launchctl bootout system/com.awdlcontrol.daemon
sudo rm -f /usr/local/bin/awdl_monitor_daemon
sudo rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
rm -rf /Applications/AWDLControl.app
```

## License

MIT
