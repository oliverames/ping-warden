# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWDLControl is a hybrid C daemon + Swift/SwiftUI app that provides macOS Control Center/menu bar toggle for controlling AWDL (Apple Wireless Direct Link). Uses AF_ROUTE socket monitoring (<1ms response, 0% CPU idle) based on awdlkiller's proven technology.

**Requirements**: macOS 15.0+ (Sequoia/Tahoe), Xcode 16.0+

## Build Commands

### Quick Build (Recommended)
```bash
# Build everything (C daemon + Swift app)
./build.sh
```

This script:
- Builds the C daemon with optimizations
- Builds the Swift app and widget (skips obsolete helper targets)
- Provides clear output and next steps
- Works without opening Xcode GUI

### Manual Build

#### Build C Daemon
```bash
cd AWDLControl/AWDLMonitorDaemon
make clean
make
cd ../..
```

#### Build Swift App
```bash
# Via command line (targets only what's needed):
xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -configuration Release

# Or open in Xcode:
open AWDLControl/AWDLControl.xcodeproj
# Then: Product → Build (⌘B)
```

### Install Daemon (Required for Functionality)
```bash
cd AWDLControl
sudo ./install_daemon.sh
```

This installs:
- `/usr/local/bin/awdl_monitor_daemon` (setuid root)
- `/Library/LaunchDaemons/com.awdlcontrol.daemon.plist`

## Testing

### Test Daemon Standalone
```bash
cd AWDLControl/AWDLMonitorDaemon
make clean && make
sudo ./awdl_monitor_daemon

# In another terminal, try to bring AWDL up:
sudo ifconfig awdl0 up

# Verify daemon brings it back down within 1ms:
ifconfig awdl0 | grep flags
# Should show DOWN (no UP flag)
```

### Test Response Time
```bash
# While daemon is running, measure response:
time (sudo ifconfig awdl0 up && sleep 0.001 && ifconfig awdl0 | grep UP)
# Should show AWDL is down (no output from grep = success)
```

### Check Daemon Status
```bash
# Is daemon running?
sudo launchctl list | grep awdlcontrol

# View daemon logs:
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h
# Or:
sudo tail -f /var/log/awdl_monitor_daemon.log

# Check AWDL interface status:
ifconfig awdl0 | grep flags
```

### Uninstall
```bash
cd AWDLControl
sudo ./uninstall_daemon.sh
```

## Architecture (Big Picture)

### Hybrid Design: C Daemon + Swift UI

**Critical architectural decision**: Swift cannot efficiently use AF_ROUTE sockets for sub-millisecond response times. Therefore, the project uses a **hybrid architecture** where the C daemon provides instant monitoring and the Swift app provides modern UI.

### Component Interaction Flow

```
User toggles Control Center widget
    ↓
AWDLToggleIntent.perform() [Swift]
    ↓
AWDLPreferences.isMonitoringEnabled = true [App Groups shared state]
    ↓
AWDLMonitor.startMonitoring() [Swift]
    ↓
launchctl load /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
    ↓
awdl_monitor_daemon starts [C]
    ↓
socket(AF_ROUTE, SOCK_RAW, 0) creates kernel notification channel
    ↓
poll() blocks until interface change [0% CPU]
    ↓
[macOS service tries to enable AWDL]
    ↓
Kernel sends RTM_IFINFO message
    ↓
poll() unblocks (<1ms)
    ↓
ioctl(SIOCSIFFLAGS) brings awdl0 down instantly
    ↓
Returns to poll() [0% CPU]
```

### Why This Architecture?

1. **Event-driven monitoring**: AF_ROUTE provides instant kernel notifications (no polling overhead)
2. **Direct control**: ioctl() syscall is ~1000x faster than spawning `ifconfig` processes
3. **Zero CPU idle**: poll() blocks in kernel space, consuming 0% CPU when no changes occur
4. **Modern UI**: Swift/SwiftUI provides ControlWidget for Control Center integration
5. **Based on proven code**: C daemon logic directly from awdlkiller (battle-tested)

### Key Files and Their Roles

**C Daemon (instant monitoring)**:
- `AWDLMonitorDaemon/awdl_monitor_daemon.c` - AF_ROUTE socket monitoring, ioctl() control
- `AWDLMonitorDaemon/Makefile` - Builds daemon with `-O2` optimization

**Swift App (UI and control)**:
- `AWDLControl/AWDLControlApp.swift` - Main app entry point, menu bar UI, daemon control actions
- `AWDLControl/AWDLMonitor.swift` - Loads/unloads daemon via launchctl with admin privileges
- `AWDLControlWidget/AWDLControlWidget.swift` - ControlWidget implementation (macOS 26+)
- `AWDLControlWidget/AWDLToggleIntent.swift` - AppIntent for toggle action

**State Management**:
- `AWDLControl/AWDLPreferences.swift` - App Groups (`group.com.awdlcontrol.app`) for shared state between app and widget
- Widget and app must share the same state; changes propagate via NotificationCenter

**Critical**: The Swift app does NOT do monitoring itself - it only controls the C daemon via launchctl. All monitoring happens in the C daemon using AF_ROUTE.

## Working with the C Daemon

### Build and Test Cycle
1. Modify `AWDLMonitorDaemon/awdl_monitor_daemon.c`
2. Rebuild with `make clean && make`
3. Reinstall with `sudo ./install_daemon.sh`
4. Restart daemon: `sudo launchctl bootout system/com.awdlcontrol.daemon && sudo launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist`

### Debugging C Daemon
```bash
# Run daemon in foreground with logging:
sudo ./awdl_monitor_daemon

# Add LOG_DEBUG statements in C code and rebuild
```

## Common Development Tasks

### Modify Daemon Behavior
1. Edit `AWDLMonitorDaemon/awdl_monitor_daemon.c`
2. `make clean && make` to rebuild
3. `sudo ./install_daemon.sh` to reinstall
4. Restart: `sudo launchctl bootout system/com.awdlcontrol.daemon` then `sudo launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist`

### Modify Widget UI
1. Edit `AWDLControlWidget/AWDLControlWidget.swift`
2. Build in Xcode (⌘B)
3. Quit and relaunch app to see changes
4. Widget updates on next system refresh cycle

### Change Monitoring Logic
**Important**: Do NOT add polling or timers to Swift code. Monitoring efficiency depends on AF_ROUTE event-driven architecture in C daemon. If you need to change monitoring behavior, modify the C daemon, not the Swift app.

### Testing Without Daemon
If you need to test UI without the daemon:
```swift
// AWDLMonitor.swift - comment out launchctl calls for UI-only testing
// But remember: actual monitoring requires the daemon
```

## Entitlements and Permissions

- **App Groups**: Required for widget/app state sharing (`group.com.awdlcontrol.app`)
- **Sandbox**: Disabled - app needs to run launchctl
- **Daemon setuid**: Required - daemon needs root for ioctl() network control

## Performance Expectations

- Daemon CPU (idle): 0.0%
- Daemon CPU (active): <0.1%
- Response time: <1ms from interface change to ioctl()
- Memory: ~2MB (daemon) + ~40MB (app)

## Documentation

- `README.md` - Installation and usage guide
- `CLAUDE.md` (this file) - Development guide and architecture overview
