# AWDLControl

A macOS menu bar app that keeps AWDL (Apple Wireless Direct Link) disabled to eliminate network latency spikes and improve Wi-Fi performance.

**Performance**: <1ms response time • 0% CPU when idle • Based on proven [awdlkiller](https://github.com/jamestut/awdlkiller) technology

**Requirements**: macOS 15.0+ (Sequoia/Tahoe) • Xcode 16.0+ (for building)

---

## What Does This Do?

AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, Handoff, and Universal Control. While useful, AWDL can cause:
- Network ping spikes (100-300ms)
- Wi-Fi performance degradation
- Increased battery usage
- Connection instability during gaming or video calls

**AWDLControl** keeps AWDL disabled with instant (<1ms) response when macOS tries to re-enable it.

> **Note**: While monitoring is enabled, AirDrop/AirPlay/Handoff will not work. Simply disable monitoring when you need these features.

---

## How It Works

AWDLControl uses a **hybrid architecture**:

### C Daemon (`awdl_monitor_daemon`)
- Monitors interface changes via **AF_ROUTE sockets** (instant kernel notifications)
- Uses **poll()** to wait for events (0% CPU when idle)
- Brings AWDL down via **ioctl()** syscall (<1ms response)
- Based on [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut

### Swift App (`AWDLControl.app`)
- Provides clean menu bar interface
- Controls daemon via `launchctl` (requires password each time)
- Shows installation wizard on first run

### Why This Architecture?

macOS services automatically re-enable AWDL every 1-2 seconds. Timer-based polling (checking every 500ms) isn't fast enough - you get latency spikes in that window. **AF_ROUTE sockets provide instant kernel notifications**, enabling <1ms response time.

---

## Installation

### Quick Start (Build from Source)

1. **Clone and build**:
   ```bash
   git clone https://github.com/oliverames/awdl0-down.git
   cd awdl0-down
   ./build.sh
   ```

2. **Install to Applications**:
   ```bash
   cp -r AWDLControl/build/Release/AWDLControl.app /Applications/
   ```

3. **Launch AWDLControl.app** and follow the on-screen installation wizard

> **Note**: The `build.sh` script builds both the C daemon and Swift app without requiring Xcode GUI. Requires Xcode Command Line Tools.

### First Launch Setup

When you first enable monitoring, AWDLControl will:
1. Show a welcome dialog
2. Copy the installation command to your clipboard
3. Open Terminal
4. Guide you through a one-time daemon installation (~30 seconds)

After this one-time setup, you can toggle monitoring from the menu bar (requires password each time).

### What Gets Installed

The installation script installs:
- `/usr/local/bin/awdl_monitor_daemon` - C daemon binary (34KB, setuid root)
- `/Library/LaunchDaemons/com.awdlcontrol.daemon.plist` - LaunchDaemon configuration

---

## Usage

### Enabling Monitoring

1. Launch AWDLControl from Applications
2. Click the menu bar icon
3. Select "Enable Monitoring"
4. If first time: Follow installation wizard
5. If already installed: Enter password to start daemon
6. AWDL is now kept disabled (<1ms response)

### Disabling Monitoring

1. Click the menu bar icon
2. Select "Disable Monitoring"
3. Enter password to stop daemon
4. AWDL is now available for AirDrop/AirPlay/Handoff

### Checking Status

```bash
# Check if daemon is running
pgrep -x awdl_monitor_daemon

# View daemon logs
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h

# Check AWDL interface status
ifconfig awdl0 | grep flags
# When monitoring: should show DOWN (no UP flag)
# When disabled: may show UP when needed by macOS
```

---

## Performance

| Metric | Value |
|--------|-------|
| Response Time | <1ms (kernel notification → ioctl) |
| CPU Usage (idle) | 0.0% |
| CPU Usage (active) | <0.1% |
| Memory (daemon) | ~2MB |
| Memory (app) | ~40MB |

### Comparison with awdlkiller

| Feature | awdlkiller | AWDLControl |
|---------|-----------|-------------|
| Response Time | <1ms | <1ms ✅ |
| CPU (idle) | 0% | 0% ✅ |
| Monitoring Method | AF_ROUTE | AF_ROUTE ✅ |
| Interface Control | ioctl() | ioctl() ✅ |
| User Interface | None | Menu bar app ✅ |

**Result**: Same performance as awdlkiller, with a modern macOS UI!

---

## Uninstallation

### Remove Everything

```bash
# Stop and remove daemon
sudo launchctl bootout system/com.awdlcontrol.daemon 2>/dev/null || true
sudo rm -f /usr/local/bin/awdl_monitor_daemon
sudo rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist

# Remove app
rm -rf /Applications/AWDLControl.app

# Clean up app data
rm -rf ~/Library/Containers/com.awdlcontrol.app
rm -rf ~/Library/Group\ Containers/group.com.awdlcontrol.app
```

Or use the included script:
```bash
cd awdl0-down
sudo ./uninstall_daemon.sh
rm -rf /Applications/AWDLControl.app
```

---

## Troubleshooting

### Daemon Won't Start

**Check if daemon binary exists**:
```bash
ls -la /usr/local/bin/awdl_monitor_daemon
# Should show: -rwsr-xr-x (note the 's' for setuid)
```

**If missing, run installation wizard again** or install manually:
```bash
cd awdl0-down
sudo ./install_daemon.sh
```

### AWDL Not Staying Down

**Verify daemon is running**:
```bash
pgrep -x awdl_monitor_daemon
# Should return a PID if running
```

**Check logs for errors**:
```bash
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h
```

### Password Prompts Every Time

This is expected behavior. AWDLControl uses `osascript` with administrator privileges to start/stop the daemon, which requires password authentication each time for security.

If you prefer one-time authorization, you would need SMJobBless (deprecated in macOS 13.0) or manual daemon configuration.

---

## Technical Details

### Architecture Flow

```
User clicks "Enable Monitoring"
           ↓
AWDLControl.app prompts for password (osascript)
           ↓
launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
           ↓
awdl_monitor_daemon starts
           ↓
Creates AF_ROUTE socket (kernel notification channel)
           ↓
poll() blocks waiting for routing messages (0% CPU)
           ↓
[macOS service tries to enable AWDL]
           ↓
Kernel sends RTM_IFINFO message
           ↓
poll() unblocks (<1ms)
           ↓
ioctl(SIOCSIFFLAGS) brings awdl0 down instantly
           ↓
Returns to poll() (0% CPU)
```

### Components

| Component | Language | Purpose |
|-----------|----------|---------|
| AWDLControl.app | Swift/SwiftUI | Menu bar UI, daemon control |
| awdl_monitor_daemon | C | AF_ROUTE monitoring, ioctl() control |
| install_daemon.sh | Bash | One-time daemon installation |

### Why Hybrid C + Swift?

- **C daemon**: Swift cannot efficiently use AF_ROUTE sockets for sub-millisecond response. C provides direct kernel integration.
- **Swift app**: Modern UI framework for menu bar integration and user experience.
- **Best of both worlds**: awdlkiller's performance with macOS-native UX.

For complete architecture details, see [CLAUDE.md](AWDLControl/CLAUDE.md).

---

## Security

### Daemon Security
- **setuid root**: Required for `ioctl()` network interface control
- **No user input**: Only processes kernel routing messages
- **Minimal attack surface**: Only responds to RTM_IFINFO for awdl0 interface
- **Open source**: All code is reviewable

### App Security
- **Sandbox disabled**: Required to execute `launchctl` and `osascript`
- **Local only**: No network connections
- **Password required**: Each daemon start/stop requires administrator authentication

---

## Credits

- **[awdlkiller](https://github.com/jamestut/awdlkiller)** by jamestut - Original C daemon implementation
- **AWDLControl** - Swift/SwiftUI menu bar wrapper

---

## License

MIT License - See LICENSE file for details

---

## Contributing

Contributions welcome! Please submit issues or pull requests.

### Building from Source

**Easy method** (recommended):
```bash
# Clone repository
git clone https://github.com/oliverames/awdl0-down.git
cd awdl0-down

# Build everything (C daemon + Swift app)
./build.sh
```

**Manual method** (if you prefer):
```bash
# Build C daemon
cd AWDLControl/AWDLMonitorDaemon
make clean && make
cd ../..

# Build Swift app
xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -configuration Release
```

---

## FAQ

**Q: Why does it ask for my password every time?**
A: For security, macOS requires administrator authentication each time a privileged daemon is started/stopped. This is by design.

**Q: Is this safe?**
A: Yes. The daemon only monitors and controls the AWDL interface. All code is open source and reviewable. The daemon uses the same proven technology as awdlkiller.

**Q: Will this break AirDrop/AirPlay/Handoff?**
A: Yes, while monitoring is enabled. Simply disable monitoring when you need these features.

**Q: How is this different from awdlkiller?**
A: Same core technology (AF_ROUTE sockets, ioctl() control), but with a native macOS menu bar app for easier control.

**Q: Does this work on older macOS versions?**
A: No, requires macOS 15.0+ (Sequoia/Tahoe) due to Swift/SwiftUI framework requirements. For older versions, use [awdlkiller](https://github.com/jamestut/awdlkiller) directly.

---

**AWDLControl** - Keep AWDL disabled with awdlkiller performance and macOS-native UX 🚀
