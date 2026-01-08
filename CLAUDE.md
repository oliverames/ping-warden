# CLAUDE.md

Development guide for AWDLControl - a macOS menu bar app that disables AWDL to eliminate network latency spikes during gaming and video calls.

## Quick Start

```bash
./build.sh
cp -r AWDLControl/build/Release/AWDLControl.app /Applications/
```

## Project Overview

AWDLControl keeps AWDL (Apple Wireless Direct Link) disabled with <1ms response time and 0% CPU when idle. AWDL powers AirDrop/AirPlay/Handoff but causes 100-300ms ping spikes.

**Trade-off**: While active, AirDrop/AirPlay/Handoff won't work.

Based on [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut.

## Features

- **Menu Bar Control**: Quick access from the system menu bar
- **Control Center Widget** (Beta): Modern Control Center integration
- **Game Mode Auto-Detect** (Beta): Automatically enables AWDL blocking when a fullscreen game is detected
- **Launch at Login**: Start automatically when you log in
- **Show/Hide Dock Icon**: Choose your preferred app visibility

## Architecture

| Component | Language | Purpose |
|-----------|----------|---------|
| `awdl_monitor_daemon` | C | AF_ROUTE socket monitoring, ioctl() interface control |
| `AWDLControl.app` | Swift/SwiftUI | Menu bar UI, settings, daemon lifecycle management |
| `AWDLControlWidget` | Swift/WidgetKit | Control Center widget for quick toggle |
| `GameModeDetector` | Swift | Monitors for fullscreen apps to detect Game Mode |

### Why This Architecture?

- **C daemon**: Swift cannot efficiently use AF_ROUTE sockets. The daemon uses `poll()` with infinite timeout for true 0% CPU when idle.
- **Swift app**: Manages daemon via `launchctl`, provides native macOS UI.
- **Widget**: Uses App Groups (`group.com.awdlcontrol.app`) to share state with main app.

### How It Works

1. Daemon creates AF_ROUTE socket to receive kernel routing messages
2. On `RTM_IFINFO` for `awdl0`, checks if interface is UP
3. If UP, immediately clears `IFF_UP` flag via `ioctl(SIOCSIFFLAGS)`
4. Response time: <1ms (kernel-level event-driven)

## Directory Structure

```
AWDLControl/
├── AWDLControl.xcodeproj/      # Xcode project
├── AWDLControl/                 # Main app target
│   ├── AWDLControlApp.swift    # App entry, menu bar, AppDelegate
│   ├── AWDLMonitor.swift       # Daemon lifecycle (install/start/stop)
│   ├── AWDLPreferences.swift   # Shared state via App Groups
│   ├── Info.plist              # App metadata, version
│   ├── Resources/
│   │   ├── install_daemon.sh   # Privileged installation script
│   │   └── com.awdlcontrol.daemon.plist  # LaunchDaemon config
│   └── Assets.xcassets/        # App icons
├── AWDLControlWidget/          # Control Center widget
│   ├── AWDLControlWidget.swift # Widget UI
│   ├── AWDLToggleIntent.swift  # Toggle action intent
│   └── AWDLPreferences.swift   # Shared preferences (duplicated)
└── AWDLMonitorDaemon/          # C daemon
    ├── awdl_monitor_daemon.c   # Main daemon source
    ├── Makefile                # Build config
    └── com.awdlcontrol.daemon.plist  # LaunchDaemon template
```

## Build

### Full Build (Recommended)

```bash
./build.sh
```

This:
1. Builds C daemon with `make`
2. Builds Swift app + widget with `xcodebuild`
3. Bundles daemon binary into app's Resources

### Component Builds

```bash
# C daemon only
cd AWDLControl/AWDLMonitorDaemon
make clean && make

# Swift app only (assumes daemon already built)
xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -configuration Release \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO
```

### Build Output

- App: `AWDLControl/build/Release/AWDLControl.app`
- Daemon binary: `AWDLControl/AWDLMonitorDaemon/awdl_monitor_daemon`

## Key Files

| File | Purpose |
|------|---------|
| `AWDLMonitorDaemon/awdl_monitor_daemon.c` | Core daemon - AF_ROUTE monitoring, ioctl control |
| `AWDLControl/AWDLControlApp.swift` | Menu bar UI, first-launch setup, all menu actions |
| `AWDLControl/AWDLMonitor.swift` | Daemon install/start/stop/health-check via launchctl |
| `AWDLControl/AWDLPreferences.swift` | App Groups shared state between app and widget |
| `AWDLControl/Resources/install_daemon.sh` | Privileged install (called via osascript) |

## Version Synchronization

**CRITICAL**: These three locations must have matching versions:

| Location | Variable/Key |
|----------|-------------|
| `AWDLMonitorDaemon/awdl_monitor_daemon.c` | `#define DAEMON_VERSION "1.0.0"` |
| `AWDLControl/AWDLMonitor.swift` | `static let expectedDaemonVersion = "1.0.0"` |
| `AWDLControl/Info.plist` | `CFBundleShortVersionString`, `CFBundleVersion` |

The app checks version compatibility before starting the daemon and prompts for update if mismatched.

## Testing

### Check Daemon Status

```bash
# Is daemon process running?
pgrep -x awdl_monitor_daemon

# Is AWDL interface down?
ifconfig awdl0 | grep flags    # Should show DOWN, not UP

# Get daemon version
/usr/local/bin/awdl_monitor_daemon --version
```

### Response Time Test (from app menu)

The "Test Daemon" menu item runs:
```bash
for i in 1 2 3 4 5; do
    ifconfig awdl0 up
    sleep 0.001
    ifconfig awdl0 | grep -q "UP" && echo "FAILED" || echo "PASSED"
done
```

### LaunchDaemon Status

```bash
# Check if daemon is loaded
sudo launchctl list | grep awdlcontrol

# Manual load/unload
sudo launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
sudo launchctl bootout system/com.awdlcontrol.daemon
```

## Logging

### App Logs (Console.app)

```bash
# Stream app logs
log stream --predicate 'subsystem == "com.awdlcontrol.app"'

# Filter by category
log stream --predicate 'subsystem == "com.awdlcontrol.app" AND category == "Monitor"'
```

Categories:
- `App` - App lifecycle, UI events
- `Monitor` - Daemon control operations
- `Settings` - Settings changes
- `GameMode` - Game Mode detection events
- `Performance` - Signpost intervals for timing

### Daemon Logs (syslog)

```bash
# Recent daemon logs
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h

# Stream daemon logs
log stream --predicate 'process == "awdl_monitor_daemon"'
```

## Installation Paths

| Component | Path |
|-----------|------|
| Daemon binary | `/usr/local/bin/awdl_monitor_daemon` (setuid root) |
| LaunchDaemon plist | `/Library/LaunchDaemons/com.awdlcontrol.daemon.plist` |
| App | `/Applications/AWDLControl.app` |

## Uninstall

From menu bar: **Uninstall Everything**

Or manually:
```bash
sudo launchctl bootout system/com.awdlcontrol.daemon
sudo rm -f /usr/local/bin/awdl_monitor_daemon
sudo rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
rm -rf /Applications/AWDLControl.app
```

## CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`):
- Runs on: `macos-14` with Xcode 16
- Builds C daemon and Swift app
- Verifies build artifacts exist

## Code Patterns

### Privileged Operations

All privileged operations use osascript with `administrator privileges`:
```swift
let appleScript = """
do shell script "..." with administrator privileges
"""
```

### State Synchronization

App and widget share state via App Groups:
```swift
UserDefaults(suiteName: "group.com.awdlcontrol.app")
```

Changes trigger `NSNotification`:
```swift
NotificationCenter.default.post(name: .awdlMonitoringStateChanged, object: nil)
```

### Daemon Health Check

`AWDLMonitor.performHealthCheck()` verifies:
1. Daemon binary exists
2. Version matches expected
3. Process is running
4. AWDL interface is actually DOWN

## Requirements

- macOS 26.0+ (Tahoe)
- Xcode 26.0+ (for building)

## Common Issues

### Daemon not starting
- Check Console.app for errors
- Verify `/usr/local/bin/awdl_monitor_daemon` has setuid bit: `ls -la` should show `-rwsr-xr-x`

### Version mismatch warning
- Rebuild and reinstall: `./build.sh` then "Reinstall Daemon" from menu

### AWDL still showing UP
- Verify daemon is running: `pgrep -x awdl_monitor_daemon`
- Check daemon logs for errors
