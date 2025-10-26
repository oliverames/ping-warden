# Build and Test Instructions - SMJobBless Helper

## ✅ Configuration Complete!

I've automated all the SMJobBless configuration with your Team ID **PV3W52NDZ3**.

**What was configured:**
- ✅ Helper Info.plist with correct code signature requirements
- ✅ App Info.plist with SMPrivilegedExecutables
- ✅ Bridging header updated for Objective-C/Swift interop
- ✅ AWDLMonitor.swift now uses helper instead of osascript

---

## Build Steps

Xcode should be open. Follow these steps:

### Step 1: Build AWDLControlHelper

1. In Xcode, **select the AWDLControlHelper scheme** from the scheme dropdown (top left)
2. Press **⌘B** to build
3. Check for build errors - should succeed with 0 errors

If you get errors, they'll likely be:
- Missing files: Make sure all files are added to the AWDLControlHelper target
- Code signing: Check Build Settings → Code Signing Identity

### Step 2: Build AWDLControl (Main App)

1. **Select the AWDLControl scheme** from the scheme dropdown
2. Press **⌘B** to build
3. Check for build errors - should succeed with 0 errors

Common errors:
- "Use of undeclared type AWDLHelperProtocol": Check bridging header path
- Info.plist issues: Make sure AWDLControl/Info.plist is set in Build Settings

### Step 3: Check Build Products

```bash
# Helper should be embedded in app
ls -la ~/Library/Developer/Xcode/DerivedData/AWDLControl-*/Build/Products/Debug/AWDLControl.app/Contents/Library/LaunchServices/

# Should see com.awdlcontrol.helper or AWDLControlHelper
```

---

## Test Steps

### First Launch (Helper Installation)

1. **Run the app** (⌘R in Xcode or launch from Finder)
2. **Click "Enable AWDL Monitoring"**
3. **You'll see a password prompt** - this is the ONE-TIME helper installation
   - The prompt says: "AWDLControl wants to install a helper tool"
   - Enter your password

4. **Check Console app** - you should see:
   ```
   AWDLMonitor: Helper not installed, installing now...
   AWDLMonitor: You will be prompted for your password to install the privileged helper
   AWDLMonitor: After this ONE-TIME setup, you'll never see password prompts again!
   AWDLMonitor: ✅ Helper installed successfully
   AWDLMonitor: ✅ Successfully loaded daemon via helper (no password prompt!)
   ```

5. **Verify helper is installed:**
   ```bash
   sudo launchctl list | grep com.awdlcontrol.helper
   # Should show: PID - com.awdlcontrol.helper

   ls -la /Library/PrivilegedHelperTools/com.awdlcontrol.helper
   # Should exist
   ```

### Subsequent Operations (No Password Prompts!)

1. **Click "Disable AWDL Monitoring"**
   - ❌ NO password prompt
   - ✅ Console shows: "Successfully unloaded daemon via helper (no password prompt!)"

2. **Click "Enable AWDL Monitoring"**
   - ❌ NO password prompt
   - ✅ Console shows: "Successfully loaded daemon via helper (no password prompt!)"

3. **Quit the app**
   - ❌ NO password prompt
   - ✅ Console shows daemon unloaded

4. **Launch the app again**
   - ❌ NO password prompt on launch
   - ✅ App just works

5. **Reboot your Mac and test again**
   - ❌ STILL NO password prompts!
   - ✅ Helper persists across reboots

---

## Success Criteria

✅ **Build succeeds** with 0 errors
✅ **First launch** prompts for password ONCE
✅ **Enable/Disable** - NO password prompts
✅ **Quit app** - NO password prompts
✅ **Relaunch app** - NO password prompts
✅ **After reboot** - NO password prompts

---

## Troubleshooting

### Build Error: "Use of undeclared type 'AWDLHelperProtocol'"

**Fix:** Check bridging header path
1. Select AWDLControl target
2. Build Settings → Search "bridging"
3. Objective-C Bridging Header should be: `AWDLControl/AWDLControl-Bridging-Header.h`

### Build Error: Info.plist not found

**Fix:** Set Info.plist path
1. Select AWDLControl target
2. Build Settings → Search "Info.plist"
3. Info.plist File should be: `AWDLControl/AWDLControl/Info.plist`

### Runtime Error: "Failed to install helper tool"

**Check code signature requirements match:**
```bash
# Get your current Team ID from certificate
security find-identity -v -p codesigning | grep "Apple Development"
# Should show: PV3W52NDZ3

# Verify it matches what's in Info.plist files
grep -r "PV3W52NDZ3" AWDLControl/
# Should find it in both helper and app Info.plist
```

### Helper not embedding in app

**Check Copy Files phase:**
1. Select AWDLControlHelper target
2. Build Phases
3. Look for "Copy Files" phase
4. Should copy `launchd.plist` to `Contents` (Wrapper destination)

If missing, add it:
- Click + → New Copy Files Phase
- Destination: Wrapper
- Subpath: `Contents`
- Add `launchd.plist`

---

## What Happens Behind the Scenes

1. **First time you enable monitoring:**
   - App calls `HelperAuthorization.shared.installHelper()`
   - `SMJobBless()` prompts for password (ONE TIME)
   - Helper gets installed to `/Library/PrivilegedHelperTools/com.awdlcontrol.helper`
   - launchd registers the helper as an on-demand service

2. **When you toggle enable/disable:**
   - App connects to helper via XPC (no password needed!)
   - Helper runs `launchctl load/unload` as root
   - Daemon starts/stops instantly

3. **When you quit:**
   - App tells helper to unload daemon via XPC (no password!)
   - Daemon stops
   - Helper stays installed and ready for next launch

4. **When you reboot:**
   - Helper is still installed in `/Library/PrivilegedHelperTools/`
   - launchd knows about it
   - App can immediately use it (no password!)

---

## Viewing Helper Logs

```bash
# View helper activity
log show --predicate 'process == "AWDLControlHelper" OR process == "com.awdlcontrol.helper"' --last 1h --info

# View helper installation
log show --predicate 'subsystem == "com.apple.ServiceManagement"' --last 1h --info
```

---

## Next Steps

Once this is working, celebrate! 🎉 You now have:
- Professional-grade authorization
- Zero password prompts (after first time)
- Secure XPC communication
- Helper that persists across reboots
- Same approach used by Little Snitch, Bartender, etc.

Ready to test? Let's do it!
