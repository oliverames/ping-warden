# AWDL Control

A macOS Sequoia (15.0+) app that provides a Control Center and menu bar toggle for controlling the AWDL (Apple Wireless Direct Link) interface. Built with the new ControlWidget API introduced in macOS Sequoia.

## Features

- **Control Center Integration**: Add an AWDL toggle directly to your Control Center
- **Menu Bar Support**: Drag the control from Control Center to your menu bar for quick access
- **Simple Toggle**: Easily enable or disable the AWDL interface with a single tap
- **Background Operation**: Runs as an accessory app (doesn't appear in the Dock)
- **Privileged Helper**: Optional helper tool for seamless interface control without repeated admin prompts

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

## Requirements

- macOS Sequoia (15.0) or later
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

### Optional: Install Privileged Helper

The privileged helper tool allows the app to control the AWDL interface without prompting for admin credentials each time. This is optional but recommended for the best user experience.

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

- **Tap the control** to toggle AWDL on/off
- When the control shows "AWDL Down", the interface is disabled
- When the control shows "AWDL Up", the interface is enabled
- The first time you toggle, macOS will prompt for admin credentials (unless you installed the privileged helper)

### Managing the App

Since AWDLControl runs as an accessory app:
- It won't appear in your Dock
- You can quit it from Activity Monitor or the menu bar if you add a quit menu
- Set it to launch at login via System Settings > General > Login Items if desired

## Technical Details

### Architecture

The app consists of three components:

1. **AWDLControl.app**: Main application bundle (runs as accessory)
2. **AWDLControlWidget.appex**: Widget extension providing the ControlWidget
3. **AWDLControlHelper**: Optional privileged helper tool for elevated operations

### How It Works

- The ControlWidget uses the new `ControlWidget` API from WidgetKit
- App Intents handle the toggle action when you interact with the control
- The AWDLManager class wraps `ifconfig` commands to control the interface
- Without the helper: Uses `osascript` to prompt for admin credentials
- With the helper: Executes commands directly via the setuid helper tool

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
