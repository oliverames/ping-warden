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

### Building from Source

```bash
git clone https://github.com/oliverames/ping-warden.git
cd ping-warden
./build.sh
cp -r "AWDLControl/build/Release/Ping Warden.app" /Applications/
```

### First Launch

1. Open **Ping Warden.app** from Applications
2. Click **Set Up Now** when prompted
3. macOS will show a notification: *"Ping Warden" can run in the background for all users*
4. Click **Allow** on the notification
5. Click **Set Up Now** again if needed
6. Done! No password prompts after initial setup.

### Code Signing Requirement

Ping Warden v2.0 uses SMAppService which requires proper code signing. The build script automatically detects your Developer ID or Apple Development certificate and signs the app appropriately.

**Prerequisites:**
- Apple Developer account signed into Xcode
- Developer ID Application certificate (for distribution) OR
- Apple Development certificate (for local testing)

**Building from Xcode** (recommended):
1. Open `AWDLControl/AWDLControl.xcodeproj` in Xcode
2. Verify your Team is selected in Signing & Capabilities for all targets
3. Build and run (Cmd+R)

**Building from command line:**
```bash
./build.sh  # Automatically uses your Developer ID certificate
```

The build script signs components individually (helper, widget, then app) per Apple's best practices for code signing nested bundles.

> **Note**: The build script will fail if no valid signing certificate is found. Ensure you're signed into Xcode with your Apple Developer account.

## Usage

### Menu Bar

Click the antenna icon in the menu bar:

| Icon | State |
|------|-------|
| Slashed antenna | AWDL blocked (monitoring active) |
| Normal antenna | AWDL available (monitoring off) |

### Settings

Access Settings from the menu bar to configure:

- **General**: Enable/disable blocking, Launch at Login, Show Dock Icon
- **Automation**: Game Mode Auto-Detect (Beta), Control Center Widget (Beta)
- **Advanced**: Diagnostics, Re-register Helper, Uninstall

### Control Center Widget (Beta)

Enable in Settings to add an AWDL toggle to the macOS Control Center. When enabled, the menu bar icon is hidden.

> **Note**: The Control Center widget requires the app to be code-signed with a Developer ID certificate. When building from source without code signing, this feature is disabled and the menu bar icon remains visible. To enable, open the project in Xcode, configure signing with your Apple Developer account, and rebuild.

### Game Mode Auto-Detect (Beta)

When enabled, Ping Warden automatically activates AWDL blocking when it detects a fullscreen application (game mode). Great for cloud gaming services like GeForce NOW, Xbox Cloud Gaming, or Steam.

## Requirements

- macOS 13.0+ (Ventura) or later
- macOS 26.0 (Tahoe) or later for Control Center Widget
- Xcode 16.0+ for building app and helper
- Xcode 26.0+ for building Control Center Widget (requires macOS Tahoe SDK)

> **Tip**: For proper app icon rendering, build from Xcode IDE rather than the command-line script. Xcode properly processes the modern `.icon` asset format.

## How It Works

Ping Warden v2.0 uses a modern architecture based on the original [awdlkiller](https://github.com/jamestut/awdlkiller) approach:

1. **Helper daemon** bundled inside the app (Contents/MacOS/AWDLControlHelper)
2. **SMAppService** registers the helper as a LaunchDaemon with one-time system approval
3. **XPC communication** between the app and helper for control commands
4. **AF_ROUTE sockets** monitor kernel routing messages and instantly bring awdl0 down via `ioctl(SIOCSIFFLAGS)` when macOS enables it

The core monitoring algorithm uses `poll()` with infinite timeout for true 0% CPU usage when idle. When the kernel sends an `RTM_IFINFO` message indicating awdl0 is UP, the helper immediately clears the `IFF_UP` flag before any network activity can occur (response time <1ms).

The helper only runs while the app is running. When you quit Ping Warden, the helper exits and AWDL is automatically restored.

## Uninstall

Simply **drag Ping Warden.app to the Trash**. macOS automatically removes the helper registration.

## Credits

- [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller) - Original AWDL monitoring concept using AF_ROUTE sockets
- [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl) - SMAppService + XPC architecture inspiration

## License

MIT
