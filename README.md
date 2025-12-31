# AWDLControl

A macOS menu bar app that keeps AWDL (Apple Wireless Direct Link) disabled to eliminate network latency spikes and improve Wi-Fi performance.

**Performance**: <1ms response time | 0% CPU when idle | Based on proven [awdlkiller](https://github.com/jamestut/awdlkiller) technology

**Requirements**: macOS 26.0+ (Tahoe) | Xcode 16.0+ (for building from source)

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

## Installation

### Build from Source

```bash
# Clone and build
git clone https://github.com/oliverames/Cloud-Gaming-Optimizer.git
cd Cloud-Gaming-Optimizer
./build.sh

# Copy to Applications
cp -r AWDLControl/build/Release/AWDLControl.app /Applications/
```

### First Launch

1. **Launch** AWDLControl.app from Applications
2. **Welcome dialog appears** - Click "Set Up Now"
3. **Enter your password** (one time only for installation)
4. **Done!** Daemon is installed and running

That's it! The app automatically:
- Installs the monitoring daemon
- Starts blocking AWDL immediately
- Shows status in the menu bar

---

## Usage

### Menu Bar Controls

Click the antenna icon in the menu bar:

| Action | Description |
|--------|-------------|
| **Enable AWDL Monitoring** | Start blocking AWDL (password required) |
| **Disable AWDL Monitoring** | Stop blocking, allow AirDrop etc. (password required) |
| **Test Daemon** | Verify daemon is working correctly |
| **View Logs in Console** | Open Console.app with filter instructions |
| **Reinstall Daemon** | Fix issues by reinstalling |
| **Uninstall Everything** | Complete removal |

### Checking Status

The menu bar icon indicates current state:
- **Slashed antenna** = AWDL blocked (monitoring active)
- **Normal antenna** = AWDL available (monitoring disabled)

---

## How It Works

AWDLControl uses a **hybrid C + Swift architecture**:

### C Daemon (`awdl_monitor_daemon`)
- Monitors interface changes via **AF_ROUTE sockets** (instant kernel notifications)
- Uses **poll()** to wait for events (0% CPU when idle)
- Brings AWDL down via **ioctl()** syscall (<1ms response)
- Based on [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut

### Swift App (`AWDLControl.app`)
- Clean menu bar interface
- Auto-installs daemon on first launch
- Controls daemon via `launchctl`

### Architecture Flow

```
User enables monitoring
        ↓
App prompts for admin password
        ↓
launchctl starts daemon
        ↓
Daemon creates AF_ROUTE socket
        ↓
poll() blocks (0% CPU)
        ↓
[macOS tries to enable AWDL]
        ↓
Kernel sends notification
        ↓
poll() unblocks (<1ms)
        ↓
ioctl() brings AWDL down
        ↓
Returns to poll()
```

---

## Performance

| Metric | Value |
|--------|-------|
| Response Time | <1ms (kernel notification to ioctl) |
| CPU Usage (idle) | 0.0% |
| CPU Usage (active) | <0.1% |
| Memory (daemon) | ~2MB |
| Memory (app) | ~40MB |

---

## Uninstallation

### From the App

Menu bar → **Uninstall Everything** → Enter password

### Manual Removal

```bash
# Stop and remove daemon
sudo launchctl bootout system/com.awdlcontrol.daemon
sudo rm -f /usr/local/bin/awdl_monitor_daemon
sudo rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist

# Remove app
rm -rf /Applications/AWDLControl.app
```

---

## Troubleshooting

### Daemon Not Starting

1. Try **Reinstall Daemon** from the menu
2. Or manually install:
   ```bash
   cd Cloud-Gaming-Optimizer/AWDLControl
   sudo ./install_daemon.sh
   ```

### View Logs

From the menu bar, click **View Logs in Console**, then:
1. Click "Start Streaming" in Console.app
2. Filter by: `subsystem:com.awdlcontrol`

### Password Prompts

Password is required for:
- **First setup**: Installs daemon (one time)
- **Enable/Disable**: Controls daemon start/stop

This is by design for security - LaunchDaemons require admin privileges.

---

## Security

- **Daemon runs as root**: Required for network interface control via ioctl()
- **Minimal attack surface**: Only processes kernel routing messages
- **Open source**: All code is reviewable
- **Password protected**: Each daemon operation requires authentication

---

## Development

See [CLAUDE.md](CLAUDE.md) for development guide and architecture details.

### Quick Build

```bash
./build.sh
```

This builds:
- C daemon with `-O2` optimization
- Swift app and Control Center widget
- Bundles daemon binary in app Resources

---

## Credits

- **[awdlkiller](https://github.com/jamestut/awdlkiller)** by jamestut - Original C daemon implementation
- **AWDLControl** - Swift/SwiftUI wrapper with modern macOS integration

---

## License

MIT License - See [LICENSE](LICENSE) file

---

**AWDLControl** - Keep AWDL disabled with <1ms response and 0% CPU idle
