# AWDL Control

A macOS Sequoia/Tahoe (15.0+/26.0+) app that provides a Control Center and menu bar toggle for controlling the AWDL (Apple Wireless Direct Link) interface. Built with the new ControlWidget API and featuring **continuous monitoring** to keep AWDL down.

## Features

- **Event-Driven Monitoring**: Real-time notifications with ~0% CPU (like awdlkiller daemon)
- **Fast ioctl() Control**: Direct interface control without spawning processes
- **Control Center Integration**: Add an AWDL toggle directly to your Control Center
- **Menu Bar Support**: Drag the control from Control Center to your menu bar for quick access
- **Simple Toggle**: Easily enable or disable AWDL monitoring with a single tap
- **Instant Response**: <10ms reaction time when AWDL comes up
- **Background Operation**: Runs as an accessory app (doesn't appear in the Dock)
- **Persistent Monitoring**: Monitoring state persists across app restarts
- **Privileged Helper**: Optional helper tool for seamless interface control without repeated admin prompts
- **App Groups**: Shared state between app and widget for reliable operation

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

## How It Works

AWDL Control uses **event-driven monitoring** similar to awdlkiller, making it extremely efficient:

1. **SystemConfiguration**: Receives real-time notifications when awdl0 changes state
2. **Instant Response**: Callback fires within <10ms when AWDL comes up
3. **Direct ioctl()**: Fast C syscalls instead of spawning ifconfig processes
4. **Fallback Timer**: Safety net checks every 5 seconds as backup
5. **~0% CPU Idle**: Event-driven architecture uses no CPU when nothing changes

This is necessary because macOS services (AirDrop, AirPlay, etc.) will automatically re-enable AWDL within seconds if you just bring it down once.

**Performance**: See [PERFORMANCE.md](PERFORMANCE.md) for detailed benchmarks and technical implementation.

## Requirements

- macOS Sequoia (15.0) or macOS Tahoe (26.0) or later
- Xcode 16.0+ (for building)
- Administrator privileges (for controlling network interfaces)

## Installation

### Building from Source

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/awdl0-down.git
   cd awdl0-down
   ```

2. Open the Xcode project:
   ```bash
   open AWDLControl/AWDLControl.xcodeproj
   ```

3. Build the project in Xcode:
   - Select the "AWDLControl" scheme
   - Choose Product > Build (⌘B)
   - The app will be built to `AWDLControl/build/Release/AWDLControl.app`

4. Copy the app to your Applications folder:
   ```bash
   cp -r AWDLControl/build/Release/AWDLControl.app /Applications/
   ```

### Recommended: Install LaunchAgent

To ensure continuous monitoring even after logout/reboot, install the LaunchAgent:

```bash
cd AWDLControl
./install_launchagent.sh
```

This will:
- Start AWDLControl automatically at login
- Keep the app running in the background
- Maintain monitoring state across sessions

To uninstall:
```bash
cd AWDLControl
./uninstall_launchagent.sh
```

### Optional: Install Privileged Helper

The privileged helper tool allows the app to control the AWDL interface without prompting for admin credentials each time. This is **highly recommended** for continuous monitoring to work smoothly.

1. Build the helper tool (already built with the main app)

2. Run the installation script with sudo:
   ```bash
   cd AWDLControl
   sudo ./install_helper.sh
   ```

The helper will be installed at `/Library/PrivilegedHelperTools/com.awdlcontrol.helper` with setuid root permissions.

To uninstall the helper later:
```bash
cd AWDLControl
sudo ./uninstall_helper.sh
```

## Usage

### First Launch

1. Launch AWDLControl from your Applications folder
2. The app will run in the background (no Dock icon)

### Adding the Control

#### To Control Center:
1. Open Control Center (click the switch icon in your menu bar)
2. Click "Edit Controls" at the bottom
3. Find "AWDL Control" in the list of available controls
4. Click the + button to add it to your Control Center
5. Click "Done"

#### To Menu Bar:
1. Add the control to Control Center first (see above)
2. Open Control Center
3. Drag the "AWDL Control" item from Control Center up to your menu bar
4. Drop it where you want it to appear

### Using the Control

- **Tap the control** to toggle AWDL monitoring on/off
- **When "AWDL Down" (green)**: Continuous monitoring is active, keeping AWDL down every 500ms
- **When "AWDL Up" (blue)**: Monitoring is stopped, AWDL operates normally
- **First time**: macOS will prompt for admin credentials (unless you installed the privileged helper)
- **Persistent state**: Your monitoring preference is saved and restored on app launch

### Checking Status

Open the app from Applications (⌘+Space, type "AWDLControl") to see:
- Current monitoring status
- Real-time state updates
- About information

### Managing the App

Since AWDLControl runs as an accessory app:
- It won't appear in your Dock
- You can quit it from Activity Monitor or the menu bar if you add a quit menu
- Set it to launch at login via System Settings > General > Login Items if desired

## Technical Details

### Architecture

The app consists of four main components:

1. **AWDLControl.app**: Main application bundle (runs as accessory)
   - AWDLMonitor: Continuous monitoring service (checks every 500ms)
   - AWDLManager: Interface control and state detection
   - AWDLPreferences: Shared state management via App Groups

2. **AWDLControlWidget.appex**: Widget extension providing the ControlWidget
   - ControlWidget UI with toggle
   - AppIntent for state changes
   - Shared preferences access

3. **AWDLControlHelper**: Optional privileged helper tool for elevated operations
4. **LaunchAgent**: Optional background service for persistence

### How It Works

#### Control Flow
1. **User taps control** → AppIntent updates shared preferences
2. **App observes change** → Starts/stops AWDLMonitor
3. **Monitor sets up events** → SystemConfiguration registers callbacks
4. **AWDL state changes** → Callback fires instantly (<10ms)
5. **If AWDL comes up** → ioctl() brings it down immediately
6. **State persists** → Monitoring continues across app restarts

#### Technical Implementation
- **ControlWidget**: New ControlWidget API from WidgetKit (macOS 15+/26+)
- **App Intents**: ForegroundContinuableIntent for state changes
- **Event-Driven Monitoring**: SystemConfiguration SCDynamicStore callbacks
- **Fast Interface Control**: Direct ioctl() syscalls via C bridge
- **Fallback Timer**: 5-second safety checks (vs 500ms polling)
- **State Synchronization**: App Groups with UserDefaults
- **Authentication**: Direct ioctl(), osascript, or setuid helper
- **Background Persistence**: LaunchAgent keeps app running
- **Performance**: ~0% CPU idle, <10ms response time

### Permissions

The app requires administrator privileges to control network interfaces. This is handled in two ways:

1. **Without helper**: macOS will prompt for credentials using a secure system dialog
2. **With helper**: The helper tool has setuid permissions to execute without prompting

The app does not use sandboxing (`com.apple.security.app-sandbox = false`) because it needs to execute privileged system commands.

## Inspiration

This project is inspired by [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut, which provides daemon-based AWDL control. AWDLControl offers a modern macOS Sequoia native interface using the new Control Widget API.

## Troubleshooting

### Control doesn't appear in Control Center

- Make sure you're running macOS Sequoia (15.0) or later
- Restart the app after building
- Check System Settings > Privacy & Security for any blocked extensions

### Toggle prompts for password every time

- Install the privileged helper tool using `sudo ./install_helper.sh`
- Verify the helper is installed: `ls -la /Library/PrivilegedHelperTools/com.awdlcontrol.helper`
- The helper should show `-rwsr-xr-x` permissions (note the 's')

### Toggle doesn't work

- Verify the AWDL interface exists: `ifconfig awdl0`
- Check Console.app for error messages from AWDLControl
- Try toggling manually: `sudo ifconfig awdl0 down` / `sudo ifconfig awdl0 up`

### App won't build

- Ensure you have Xcode 16.0 or later
- Make sure your deployment target is set to macOS 15.0
- Clean build folder: Product > Clean Build Folder (⌘⇧K)

## Security Considerations

- The privileged helper tool only accepts two commands: `up` and `down`
- Interface names are validated using regex to prevent command injection
- The helper only works with the `/sbin/ifconfig` binary
- All code is open source for security review

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

- [awdlkiller](https://github.com/jamestut/awdlkiller) by jamestut - Original inspiration
- Apple's WidgetKit and ControlWidget API documentation
- macOS Sequoia for introducing third-party Control Center controls
