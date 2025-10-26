# SMJobBless Setup Guide

This guide walks you through setting up the privileged helper tool using Apple's recommended SMJobBless framework.

## What You're Building

After this setup, your app will have:
- **One password prompt** when first installing the helper
- **Zero password prompts** for all subsequent operations (enable/disable/quit)
- Professional-grade authorization that persists across reboots

---

## Step 1: Get Your Team ID and Signing Identity

```bash
# Find your Team ID
security find-identity -v -p codesigning | grep "Apple Development"
# Look for something like: "Apple Development: Your Name (TEAMID)"
# The TEAMID is typically 10 characters like "ABCD123456"

# Or get it from your certificate
security find-certificate -c "Apple Development" -p | openssl x509 -text | grep "OU="
```

**Note your Team ID - you'll need it in multiple places!**

---

## Step 2: Create Helper Tool Target in Xcode

1. **Open AWDLControl.xcodeproj**

2. **File → New → Target**
   - Choose **Command Line Tool** (macOS)
   - Product Name: `AWDLHelper`
   - Language: **Objective-C**
   - Click Finish

3. **Delete the default `main.m`** from the AWDLHelper group

4. **Add files to AWDLHelper target:**
   - Right-click AWDLHelper group → Add Files
   - Add `AWDLHelper/main.m`
   - Add `AWDLHelper/Info.plist`
   - Add `AWDLHelper/launchd.plist`
   - Add `AWDLHelperProtocol.h` (to both AWDLHelper AND AWDLControl targets)

5. **Configure AWDLHelper target settings:**
   - Select AWDLHelper target
   - Build Settings:
     - Product Bundle Identifier: `com.awdlcontrol.helper`
     - Code Signing Identity: Your Development certificate
     - Code Signing Style: Automatic (or Manual if you prefer)
     - Info.plist File: `AWDLHelper/Info.plist`
     - Skip Install: **NO**

6. **Add launchd.plist to Copy Files phase:**
   - Select AWDLHelper target
   - Build Phases → Add "Copy Files" phase
   - Destination: **Wrapper** (not Resources!)
   - Subpath: `Contents`
   - Add `launchd.plist`

---

## Step 3: Update Info.plist Files with Code Signature Requirements

This is the tricky part. Both the app and helper need to know each other's code signatures.

### 3.1: Update Helper's Info.plist

Edit `AWDLHelper/Info.plist`:

Replace `TEAMID` with your actual Team ID:

```xml
<key>SMAuthorizedClients</key>
<array>
    <string>identifier "com.awdlcontrol.app" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "YOUR_TEAM_ID_HERE"</string>
</array>
```

### 3.2: Update App's Info.plist

Edit `AWDLControl/Info.plist` and add:

```xml
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.awdlcontrol.helper</key>
    <string>identifier "com.awdlcontrol.helper" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "YOUR_TEAM_ID_HERE"</string>
</dict>
```

**Important:** Use the **same** code signature requirement string in both places (just change the identifier).

---

## Step 4: Add Objective-C Bridging

Since the helper uses Objective-C and Swift needs to call it:

1. **Create bridging header** (if not exists):
   - File → New → File → Header File
   - Name: `AWDLControl-Bridging-Header.h`

2. **Add to bridging header:**
```objc
#import "AWDLHelperProtocol.h"
```

3. **Configure in Build Settings:**
   - Select AWDLControl target
   - Build Settings → Search "bridging"
   - Objective-C Bridging Header: `AWDLControl/AWDLControl-Bridging-Header.h`

---

## Step 5: Add HelperAuthorization.swift to Project

1. **Add to AWDLControl target:**
   - Right-click AWDLControl group → Add Files
   - Add `AWDLControl/HelperAuthorization.swift`
   - Make sure it's checked for AWDLControl target

---

## Step 6: Update AWDLMonitor to Use Helper

Edit `AWDLControl/AWDLMonitor.swift`:

Replace the `loadDaemon()` and `unloadDaemon()` methods:

```swift
/// Load the LaunchDaemon (via privileged helper - no password prompt!)
private func loadDaemon() -> Bool {
    do {
        // Check if helper is installed
        if !HelperAuthorization.shared.isHelperInstalled() {
            print("AWDLMonitor: Helper not installed, installing now...")
            try HelperAuthorization.shared.installHelper()
            print("AWDLMonitor: Helper installed successfully")
        }

        // Use helper to load daemon (no password prompt!)
        try HelperAuthorization.shared.loadDaemon()
        print("AWDLMonitor: Successfully loaded daemon via helper")
        return true
    } catch {
        print("AWDLMonitor: Error loading daemon: \(error)")
        return false
    }
}

/// Unload the LaunchDaemon (via privileged helper - no password prompt!)
private func unloadDaemon() -> Bool {
    do {
        // Use helper to unload daemon (no password prompt!)
        try HelperAuthorization.shared.unloadDaemon()
        print("AWDLMonitor: Successfully unloaded daemon via helper")
        return true
    } catch {
        print("AWDLMonitor: Error unloading daemon: \(error)")
        return false
    }
}

/// Check if daemon is currently loaded (via privileged helper)
private func isDaemonLoaded() -> Bool {
    return HelperAuthorization.shared.isDaemonLoaded()
}
```

---

## Step 7: Build and Test

### 7.1: Build Both Targets

```bash
# Build helper first
xcodebuild -project AWDLControl.xcodeproj -scheme AWDLHelper -configuration Debug

# Build app
xcodebuild -project AWDLControl.xcodeproj -scheme AWDLControl -configuration Debug
```

### 7.2: Test Installation

1. **Run the app** (will prompt for password to install helper)
2. **Click "Enable AWDL Monitoring"**
   - First time: Password prompt to install helper
   - Subsequent times: **No password prompt!**

3. **Verify helper is installed:**
```bash
sudo launchctl list | grep com.awdlcontrol.helper
# Should show: PID - com.awdlcontrol.helper

ls -la /Library/PrivilegedHelperTools/com.awdlcontrol.helper
# Should exist
```

4. **Test enable/disable multiple times** - should never prompt again!

5. **Test quit and relaunch** - still no prompts!

---

## Step 8: Verify It Works

Expected behavior:
- ✅ **First launch:** Password prompt to install helper
- ✅ **Enable monitoring:** No password prompt (uses helper)
- ✅ **Disable monitoring:** No password prompt (uses helper)
- ✅ **Quit app:** No password prompt (uses helper)
- ✅ **Relaunch app:** No password prompt at all
- ✅ **Reboot Mac:** No password prompt on first launch

---

## Troubleshooting

### Error: "Failed to install helper tool"

**Check code signing:**
```bash
codesign -v -v /Library/PrivilegedHelperTools/com.awdlcontrol.helper
# Should say "valid on disk" and "satisfies its Designated Requirement"
```

**Check Info.plist requirements match:**
```bash
# Get app's code signature
codesign -d -r- AWDLControl.app

# Get helper's code signature
codesign -d -r- AWDLControl.app/Contents/Library/LaunchServices/com.awdlcontrol.helper

# These should match what's in your Info.plist files
```

### Error: "Helper not installed"

The helper might not be embedded in the app bundle correctly.

**Check it's there:**
```bash
ls -la AWDLControl.app/Contents/Library/LaunchServices/
# Should contain com.awdlcontrol.helper
```

### Error: Connection to helper fails

**Check helper is running:**
```bash
sudo launchctl list | grep com.awdlcontrol.helper
# Should show a PID (not -)

# View helper logs
log show --predicate 'process == "AWDLHelper"' --last 1h --info
```

---

## How It Works

1. **SMJobBless** installs the helper to `/Library/PrivilegedHelperTools/` (one-time password prompt)
2. **launchd** manages the helper (starts it on-demand when app needs it)
3. **XPC** provides secure communication between app and helper
4. **Helper runs as root** so it can call launchctl without password prompts
5. **Code signature requirements** ensure only your app can talk to your helper

---

## Next Steps

Once this is working:
1. Remove all the `osascript` code from AWDLMonitor.swift
2. Remove AWDLManager.swift (no longer needed)
3. Test thoroughly (enable/disable/quit/relaunch/reboot)
4. Celebrate never seeing a password prompt again! 🎉

---

## References

- [Apple SMJobBless Documentation](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless)
- [EvenBetterAuthorizationSample](https://developer.apple.com/library/archive/samplecode/EvenBetterAuthorizationSample/)
- [SMJobBless Tutorial](https://www.raywenderlich.com/1854-smjobbless-tutorial-how-to-install-a-helper-tool-on-macos)
