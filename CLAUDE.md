# CLAUDE.md

Development guide for Claude Code when working with this repository.

## Project Overview

**AWDLControl** is a macOS menu bar app that keeps AWDL disabled using a hybrid C daemon + Swift UI architecture. Uses AF_ROUTE socket monitoring for <1ms response time with 0% CPU when idle.

**Requirements**: macOS 26.0+ (Tahoe), Xcode 16.0+

## Quick Build

```bash
./build.sh
```

This builds the C daemon, Swift app, widget, and bundles everything together.

## Architecture

### Components

| Component | Language | Purpose |
|-----------|----------|---------|
| `awdl_monitor_daemon` | C | AF_ROUTE socket monitoring, ioctl() control |
| `AWDLControl.app` | Swift/SwiftUI | Menu bar UI, daemon lifecycle management |
| `AWDLControlWidget` | Swift | Control Center widget |

### Critical Design Decision

The C daemon handles all monitoring because Swift cannot efficiently use AF_ROUTE sockets for sub-millisecond response. The Swift app only controls the daemon via `launchctl`.

### Key Files

**C Daemon**:
- `AWDLMonitorDaemon/awdl_monitor_daemon.c` - Core monitoring logic
- `AWDLMonitorDaemon/com.awdlcontrol.daemon.plist` - LaunchDaemon config

**Swift App**:
- `AWDLControl/AWDLControlApp.swift` - App entry point, menu bar UI
- `AWDLControl/AWDLMonitor.swift` - Daemon control (install, start, stop)
- `AWDLControl/AWDLPreferences.swift` - Shared state via App Groups

**Widget**:
- `AWDLControlWidget/AWDLControlWidget.swift` - Control Center widget
- `AWDLControlWidget/AWDLToggleIntent.swift` - Toggle action

## Installation Flow

On first launch:
1. App detects daemon not installed
2. Shows welcome dialog
3. User clicks "Set Up Now"
4. `installAndStartMonitoring()` runs install script with admin privileges
5. Daemon binary + plist copied to system locations
6. Daemon started via launchctl

## Common Tasks

### Modify Daemon

```bash
# Edit source
vim AWDLControl/AWDLMonitorDaemon/awdl_monitor_daemon.c

# Rebuild and reinstall
./build.sh
sudo ./AWDLControl/install_daemon.sh

# Restart daemon
sudo launchctl bootout system/com.awdlcontrol.daemon
sudo launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
```

### View Logs

```bash
# App logs (realtime)
log stream --predicate 'subsystem == "com.awdlcontrol.app"' --level debug

# Daemon logs
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h
```

### Test Daemon

```bash
# Check if running
pgrep -x awdl_monitor_daemon

# Check AWDL status (should show DOWN when daemon active)
ifconfig awdl0 | grep flags

# Test response time
sudo ifconfig awdl0 up && sleep 0.01 && ifconfig awdl0 | grep flags
```

## Version Sync

Keep versions in sync:
- `AWDLMonitorDaemon/awdl_monitor_daemon.c`: `DAEMON_VERSION "1.6.0"`
- `AWDLControl/AWDLMonitor.swift`: `expectedDaemonVersion = "1.6.0"`
- `AWDLControl/Info.plist`: `CFBundleVersion` and `CFBundleShortVersionString`

## Entitlements

- **App Groups**: `group.com.awdlcontrol.app` (widget/app state sharing)
- **Sandbox**: Disabled (needed for launchctl)
- **Daemon setuid**: Required for ioctl() network control

## Performance Targets

- Response time: <1ms
- CPU (idle): 0%
- CPU (active): <0.1%
- Memory: ~2MB daemon, ~40MB app
