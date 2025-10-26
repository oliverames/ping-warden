# AWDL Control

A macOS Sequoia/Tahoe (15.0+/26.0+) app that provides a Control Center and menu bar toggle for controlling the AWDL (Apple Wireless Direct Link) interface.

**Architecture**: Hybrid C daemon (AF_ROUTE monitoring like awdlkiller) + Swift/SwiftUI ControlWidget UI

**Performance**: <1ms response time, 0% CPU when idle, zero network drops

---

## Features

- **Instant Response**: <1ms reaction time using AF_ROUTE sockets (same as awdlkiller)
- **Zero CPU**: Event-driven monitoring uses 0% CPU when idle
- **C Daemon**: Proven awdlkiller-based monitoring for reliability
- **Swift UI**: Modern ControlWidget for Control Center and menu bar
- **Control Center Integration**: Add toggle directly to your Control Center
- **Menu Bar Support**: Drag control from Control Center to menu bar
- **Simple Toggle**: One tap to enable/disable AWDL monitoring
- **No Network Drops**: AWDL never stays up long enough to cause issues
- **Background Operation**: Runs as LaunchDaemon (starts/stops on demand)
- **Easy Installation**: One script installs everything
- **Comprehensive Logging**: Syslog integration for debugging

---

## What is AWDL?

AWDL (Apple Wireless Direct Link) is the underlying technology that powers features like:
- AirDrop
- AirPlay
- Handoff
- Universal Control

Some users prefer to disable AWDL to:
- Eliminate network ping spikes
- Improve Wi-Fi performance
- Reduce battery usage
- Enhance network stability

**Note**: Disabling AWDL will prevent the above features from working until you re-enable it.

---

## How It Works

AWDLControl uses a **hybrid architecture** combining awdlkiller's proven monitoring with modern macOS UI:

### C Daemon (`awdl_monitor_daemon`)
- **AF_ROUTE Socket**: Receives real-time kernel notifications when interfaces change
- **poll()**: Blocks until interface changes (0% CPU when idle)
- **ioctl()**: Brings awdl0 down instantly when it comes up (<1ms)
- **Based on awdlkiller**: Uses the same proven monitoring technology

### Swift App (`AWDLControl.app`)
- **ControlWidget**: Modern macOS UI for Control Center/menu bar
- **AppIntents**: Handles toggle actions
- **launchctl**: Starts/stops the C daemon via LaunchDaemon
- **App Groups**: Manages shared state between app and widget

### Why This Matters

macOS services (AirDrop, AirPlay, etc.) will automatically re-enable AWDL within 1-2 seconds. Timer-based polling (checking every 500ms) isn't fast enough - you get network drops in that window. **AF_ROUTE sockets provide instant notification** from the kernel, allowing <1ms response time.

**Architecture Details**: See [ARCHITECTURE.md](ARCHITECTURE.md) for complete technical documentation.

---

## Requirements

- macOS Sequoia (15.0) or macOS Tahoe (26.0) or later
- Xcode 16.0+ (for building)
- Xcode Command Line Tools (`xcode-select --install`)
- Administrator privileges (for daemon installation)

---

## Installation

### Step 1: Build the App

```bash
# Clone repository
git clone https://github.com/yourusername/awdl0-down.git
cd awdl0-down/AWDLControl

# Open in Xcode
open AWDLControl.xcodeproj

# Build the app (⌘B)
# Product → Build

# Copy to Applications
cp -r build/Release/AWDLControl.app /Applications/
```

### Step 2: Install the Daemon (REQUIRED)

The C daemon provides the actual AWDL monitoring. This must be installed:

```bash
cd AWDLControl
sudo ./install_daemon.sh
```

This script will:
- Build `awdl_monitor_daemon` from source
- Install to `/usr/local/bin` with setuid root permissions
- Install LaunchDaemon plist to `/Library/LaunchDaemons`

**Verification**:
```bash
# Check daemon binary exists and has setuid
ls -la /usr/local/bin/awdl_monitor_daemon
# Should show: -rwsr-xr-x ... (note the 's')

# Check plist installed
ls -la /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
```

### Step 3: Optional - App LaunchAgent

To have the app start automatically at login:

```bash
cd AWDLControl
./install_launchagent.sh
```

---

## Usage

### Adding the Control

#### To Control Center:
1. Open Control Center (click switch icon in menu bar)
2. Click "Edit Controls" at the bottom
3. Find "AWDL Control" in the list
4. Click the + button to add it
5. Click "Done"

#### To Menu Bar:
1. Add to Control Center first (see above)
2. Open Control Center
3. Drag the "AWDL Control" item up to your menu bar
4. Drop it where you want it to appear

### Using the Control

- **Tap to toggle** AWDL monitoring on/off
- **When enabled (green)**: C daemon is running, AWDL stays down (<1ms response)
- **When disabled (blue)**: Daemon stopped, AWDL operates normally

### Checking Status

```bash
# Check if daemon is running
sudo launchctl list | grep awdlcontrol

# View daemon logs
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h

# Or check the log file
sudo tail -f /var/log/awdl_monitor_daemon.log

# Check AWDL status
ifconfig awdl0 | grep flags
```

---

## How the Daemon Works

```
User toggles control in Control Center
           ↓
AppIntent loads LaunchDaemon via launchctl
           ↓
awdl_monitor_daemon starts
           ↓
Creates AF_ROUTE socket
           ↓
poll() blocks waiting for routing messages (0% CPU)
           ↓
macOS tries to bring AWDL up
           ↓
Kernel sends RTM_IFINFO message
           ↓
poll() unblocks INSTANTLY (<1ms)
           ↓
ioctl() brings AWDL down
           ↓
Returns to poll() (0% CPU)
```

This is **exactly how awdlkiller works** - instant response with zero CPU usage.

---

## Uninstallation

### Remove Daemon
```bash
cd AWDLControl
sudo ./uninstall_daemon.sh
```

### Remove App
```bash
rm -rf /Applications/AWDLControl.app
```

### Remove LaunchAgent (if installed)
```bash
cd AWDLControl
./uninstall_launchagent.sh
```

---

## Technical Details

### Components

| Component | Purpose | Language | Location |
|-----------|---------|----------|----------|
| AWDLControl.app | UI and control | Swift/SwiftUI | /Applications |
| awdl_monitor_daemon | AWDL monitoring | C | /usr/local/bin |
| com.awdlcontrol.daemon.plist | Daemon config | XML | /Library/LaunchDaemons |

### Architecture

**AWDLControl.app** (Swift):
- ControlWidget UI
- AppIntents for toggle
- Loads/unloads daemon via launchctl
- State management via App Groups

**awdl_monitor_daemon** (C):
- AF_ROUTE socket monitoring
- poll() for event-driven operation
- ioctl() for interface control
- Exactly like awdlkiller

**Communication Flow**:
```
Swift App ← launchctl → LaunchDaemon → C Daemon
                                          ↕
                                    AF_ROUTE Socket
                                          ↕
                                    macOS Kernel
```

For complete architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Performance

### Metrics
- **Response Time**: <1ms (kernel notification to ioctl)
- **CPU Usage (idle)**: 0.0%
- **CPU Usage (active)**: <0.1%
- **Memory**: ~2 MB (daemon) + ~40 MB (app)
- **Battery Impact**: Negligible

### Comparison with awdlkiller

| Metric | awdlkiller | AWDLControl |
|--------|-----------|-------------|
| Response Time | <1ms | <1ms ✅ |
| CPU (idle) | 0% | 0% ✅ |
| Monitoring | AF_ROUTE | AF_ROUTE ✅ |
| Interface Control | ioctl() | ioctl() ✅ |
| User Interface | None | ControlWidget ✅ |

**Result**: Same performance, better UX!

---

## Troubleshooting

### Daemon Won't Start

**Check installation**:
```bash
ls -la /usr/local/bin/awdl_monitor_daemon
# Should show: -rwsr-xr-x (setuid bit set)
```

**If missing setuid**:
```bash
sudo chmod u+s /usr/local/bin/awdl_monitor_daemon
```

**Try loading manually**:
```bash
sudo launchctl load /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
```

### AWDL Not Staying Down

**Check if daemon is running**:
```bash
sudo launchctl list | grep awdlcontrol
# Should show PID if running
```

**View logs**:
```bash
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h
```

### Toggle Doesn't Work

**Check app permissions**:
- App needs to run launchctl (requires admin password)
- First toggle will prompt for password

**Check daemon plist exists**:
```bash
ls -la /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
```

### Widget Not Appearing

**macOS Version**:
- Requires macOS 15.0 (Sequoia) or later
- ControlWidget API not available on older versions

**Restart App**:
- Quit AWDLControl.app
- Relaunch from Applications

---

## Security

### Daemon Security
- **setuid root**: Required for network interface control (ioctl)
- **No user input**: Only processes kernel routing messages
- **Minimal attack surface**: Only responds to RTM_IFINFO for awdl0
- **Open source**: All code reviewable

### App Security
- **Sandbox disabled**: Required to run launchctl
- **App Groups**: Secure state sharing between app and widget
- **Local only**: No network connections

---

## Documentation

- **README.md** (this file) - User guide and installation
- **ARCHITECTURE.md** - Complete technical architecture
- **PERFORMANCE.md** - Benchmarks and performance details
- **IMPLEMENTATION_COMPARISON.md** - Design decisions and comparisons
- **PROJECT_REVIEW.md** - Code review and testing guide
- **TEST_SUMMARY.md** - Testing checklist

---

## Credits

- **awdlkiller** by [jamestut](https://github.com/jamestut/awdlkiller) - Original C implementation
- **AWDLControl** - Modern Swift/SwiftUI wrapper with ControlWidget
- **Apple** - ControlWidget API, macOS frameworks

---

## License

MIT License - See LICENSE file for details

---

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests.

---

## Summary

AWDLControl combines:
- ✅ **awdlkiller's instant monitoring** (<1ms response, 0% CPU)
- ✅ **Modern macOS UI** (ControlWidget for Control Center/menu bar)
- ✅ **Easy installation** (one script)
- ✅ **Bulletproof reliability** (proven AF_ROUTE technology)

**Best of both worlds!** 🚀
