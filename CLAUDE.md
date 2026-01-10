# CLAUDE.md

Development guide for Ping Warden (internally AWDLControl) - a macOS menu bar app that disables AWDL to eliminate network latency spikes during gaming and video calls.

## Quick Start

```bash
./build.sh
cp -r "AWDLControl/build/Release/Ping Warden.app" /Applications/
```

On first launch: Click "Set Up Now" and approve in System Settings (one-time).

## Project Overview

Ping Warden keeps AWDL (Apple Wireless Direct Link) disabled with <1ms response time and 0% CPU when idle. AWDL powers AirDrop/AirPlay/Handoff but causes 100-300ms ping spikes.

**Trade-off**: While active, AirDrop/AirPlay/Handoff won't work.

Based on [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut.
SMAppService + XPC architecture inspired by [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl).

## Features

- **Menu Bar Control**: Quick access from the system menu bar
- **Control Center Widget** (Beta): Modern Control Center integration
- **Game Mode Auto-Detect** (Beta): Automatically enables AWDL blocking when a fullscreen game is detected
- **Launch at Login**: Start automatically when you log in
- **Show/Hide Dock Icon**: Choose your preferred app visibility

## Architecture (v2.0)

| Component | Language | Purpose |
|-----------|----------|---------|
| `AWDLControlHelper` | Objective-C | AF_ROUTE socket monitoring, ioctl() interface control |
| `AWDLControl.app` | Swift/SwiftUI | Menu bar UI, settings, helper lifecycle via SMAppService |
| `AWDLControlWidget` | Swift/WidgetKit | Control Center widget for quick toggle |
| `GameModeDetector` | Swift | Monitors for fullscreen apps to detect Game Mode |

### v2.0 Key Changes

- **No password prompts**: Uses SMAppService for one-time system approval
- **Helper bundled inside app**: Clean uninstall by dragging to Trash
- **XPC communication**: App talks to helper via Mach services
- **Helper exits with app**: AWDL automatically restored when you quit

### Why This Architecture?

- **Obj-C helper**: Swift cannot efficiently use AF_ROUTE sockets. The helper uses `poll()` with infinite timeout for true 0% CPU when idle.
- **SMAppService**: Modern macOS API that registers bundled helpers as LaunchDaemons with user approval (no sudo/password).
- **XPC**: Secure inter-process communication via Mach services.
- **Widget**: Uses App Groups (`group.com.awdlcontrol.app`) to share state with main app.

### How It Works

1. App registers helper via `SMAppService.daemon(plistName:)`
2. User approves once in System Settings → Login Items
3. macOS starts helper as LaunchDaemon (bundled plist)
4. App communicates with helper via XPC (`com.awdlcontrol.xpc.helper`)
5. Helper creates AF_ROUTE socket to receive kernel routing messages
6. On `RTM_IFINFO` for `awdl0`, checks if interface is UP
7. If UP, immediately clears `IFF_UP` flag via `ioctl(SIOCSIFFLAGS)`
8. Response time: <1ms (kernel-level event-driven)
9. When app quits, helper exits and AWDL is restored

## Directory Structure

```
AWDLControl/
├── AWDLControl.xcodeproj/      # Xcode project
├── Common/                      # Shared between app and helper
│   └── HelperProtocol.h        # XPC protocol definition
├── AWDLControl/                 # Main app target
│   ├── AWDLControlApp.swift    # App entry, menu bar, AppDelegate
│   ├── AWDLMonitor.swift       # Helper lifecycle (SMAppService + XPC)
│   ├── AWDLPreferences.swift   # Shared state via App Groups
│   ├── Info.plist              # App metadata, version
│   ├── AWDLControl-Bridging-Header.h  # Imports HelperProtocol.h
│   └── Assets.xcassets/        # App icons
├── AWDLControlHelper/          # Obj-C helper daemon
│   ├── main.m                  # XPC listener entry point
│   ├── AWDLMonitor.h           # Monitor interface
│   ├── AWDLMonitor.m           # AF_ROUTE monitoring, ioctl control
│   ├── Info.plist              # Helper bundle info
│   └── com.awdlcontrol.helper.plist  # SMAppService daemon config
└── AWDLControlWidget/          # Control Center widget
    ├── AWDLControlWidget.swift # Widget UI
    ├── AWDLToggleIntent.swift  # Toggle action intent
    └── AWDLPreferences.swift   # Shared preferences (duplicated)
```

### App Bundle Structure (after build)

```
AWDLControl.app/
├── Contents/
│   ├── MacOS/
│   │   ├── AWDLControl          # Main app binary
│   │   └── AWDLControlHelper    # Helper binary (copied by build.sh)
│   ├── Library/
│   │   └── LaunchDaemons/
│   │       └── com.awdlcontrol.helper.plist  # SMAppService config
│   ├── Info.plist
│   └── Resources/
```

## Build

### Full Build (Recommended)

```bash
./build.sh
```

This:
1. Builds Swift app + widget + helper with `xcodebuild`
2. Copies helper binary to `Contents/MacOS/`
3. Copies helper plist to `Contents/Library/LaunchDaemons/`
4. Verifies bundle structure

### Build Output

- App: `AWDLControl/build/Release/AWDLControl.app`
- Helper (standalone): `AWDLControl/build/Release/AWDLControlHelper`

## Key Files

| File | Purpose |
|------|---------|
| `Common/HelperProtocol.h` | XPC protocol shared between app and helper |
| `AWDLControlHelper/main.m` | XPC listener, connection management |
| `AWDLControlHelper/AWDLMonitor.m` | Core AF_ROUTE monitoring, ioctl control |
| `AWDLControl/AWDLControlApp.swift` | Menu bar UI, first-launch setup, all menu actions |
| `AWDLControl/AWDLMonitor.swift` | SMAppService registration, XPC communication |
| `AWDLControl/AWDLPreferences.swift` | App Groups shared state between app and widget |

## XPC Protocol

Defined in `Common/HelperProtocol.h`:

```objc
@protocol AWDLHelperProtocol <NSObject>
- (void)isAWDLEnabledWithReply:(void (^)(BOOL enabled))reply;
- (void)setAWDLEnabled:(BOOL)enable withReply:(void (^)(BOOL success))reply;
- (void)getAWDLStatusWithReply:(void (^)(NSString *status))reply;
- (void)getVersionWithReply:(void (^)(NSString *version))reply;
@end
```

Swift calls these via `NSXPCConnection` to the Mach service `com.awdlcontrol.xpc.helper`.

## Testing

### Check Helper Status

```bash
# Is helper process running?
pgrep -x AWDLControlHelper

# Is AWDL interface down?
ifconfig awdl0 | grep flags    # Should show DOWN, not UP

# Check SMAppService registration
# (No direct CLI - check System Settings → Login Items)
```

### Response Time Test (from app menu)

Settings → Advanced → Test Daemon runs:
```bash
for i in 1 2 3 4 5; do
    ifconfig awdl0 up
    sleep 0.001
    ifconfig awdl0 | grep -q "UP" && echo "FAILED" || echo "PASSED"
done
```

All iterations should pass, indicating <1ms response time.

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
- `Monitor` - XPC communication, SMAppService operations
- `Settings` - Settings changes
- `GameMode` - Game Mode detection events
- `Performance` - Signpost intervals for timing

### Helper Logs

```bash
# Stream helper logs
log stream --predicate 'subsystem == "com.awdlcontrol.helper"'
```

## Installation

The helper is bundled inside the app. On first launch:

1. App calls `SMAppService.daemon(plistName:).register()`
2. macOS prompts user to approve in System Settings → Login Items
3. Once approved, macOS starts the helper as a LaunchDaemon
4. App connects via XPC and sends commands

No files are installed outside the app bundle.

## Uninstall

Simply **drag Ping Warden.app to the Trash**. macOS automatically removes the SMAppService registration.

Or from the app: Settings → Advanced → Uninstall

## CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`):
- Runs on: `macos-14` with Xcode 16
- Builds app, widget, and helper
- Verifies build artifacts exist

## Code Patterns

### SMAppService Registration

```swift
let helperService = SMAppService.daemon(plistName: "com.awdlcontrol.helper.plist")
try helperService.register()
// User approves in System Settings
// Then helperService.status == .enabled
```

### XPC Communication

```swift
let connection = NSXPCConnection(machServiceName: "com.awdlcontrol.xpc.helper", options: [])
connection.remoteObjectInterface = NSXPCInterface(with: AWDLHelperProtocol.self)
connection.activate()

let proxy = connection.remoteObjectProxy as? AWDLHelperProtocol
proxy?.setAWDLEnabled(false) { success in
    // AWDL is now disabled
}
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

### Helper Health Check

`AWDLMonitor.performHealthCheck()` verifies:
1. Helper is registered with SMAppService
2. XPC connection is active
3. Helper responds to status queries
4. AWDL interface is actually DOWN (when monitoring)

## Requirements

- macOS 13.0+ (Ventura or later)
- Xcode 16.0+ (for building)

## Common Issues

### Helper not starting
- Check System Settings → Login Items for AWDLControl
- Try "Re-register Helper" from Settings → Advanced
- Check Console.app for XPC errors

### "Requires Approval" status persists
- Open System Settings → Login Items
- Toggle AWDLControl off then on
- Restart the app

### AWDL still showing UP
- Verify helper is running: `pgrep -x AWDLControlHelper`
- Check XPC connection in app logs
- Try toggling monitoring off then on

### App shows "Helper not responding"
- Quit and relaunch the app
- If persists, use "Re-register Helper" in settings
