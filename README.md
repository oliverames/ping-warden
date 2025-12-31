# AWDLControl

A macOS menu bar app that disables AWDL to eliminate network latency spikes.

## The Problem

AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, and Handoff. It also causes:

- **100-300ms ping spikes** during gaming or video calls
- Wi-Fi performance degradation
- Intermittent connection drops

## The Solution

AWDLControl keeps AWDL disabled with **<1ms response time** and **0% CPU** when idle. Based on [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut.

> **Trade-off**: While active, AirDrop/AirPlay/Handoff won't work. Toggle off from the menu bar when needed.

## Installation

```bash
git clone https://github.com/oliverames/Cloud-Gaming-Optimizer.git
cd Cloud-Gaming-Optimizer
./build.sh
cp -r AWDLControl/build/Release/AWDLControl.app /Applications/
```

On first launch, click **Set Up Now** and enter your password once to install the daemon.

## Usage

Click the antenna icon in the menu bar:

| Icon | State |
|------|-------|
| Slashed antenna | AWDL blocked (monitoring active) |
| Normal antenna | AWDL available (monitoring off) |

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16.0+ (for building)

## How It Works

A lightweight C daemon monitors the network stack via AF_ROUTE sockets. When macOS enables AWDL, the daemon instantly brings it back down using ioctl(). The Swift app provides the UI and manages the daemon via launchctl.

## Uninstall

From the menu bar: **Uninstall Everything**

Or manually:
```bash
sudo launchctl bootout system/com.awdlcontrol.daemon
sudo rm -f /usr/local/bin/awdl_monitor_daemon
sudo rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
rm -rf /Applications/AWDLControl.app
```

## License

MIT
