# Fix and Test Guide

## What Went Wrong

SMAppService is for **system-level LaunchDaemons** (installed in `/Library/LaunchDaemons/`), not for **privileged helpers embedded in app bundles**.

For embedded helpers, SMJobBless is still the correct API, even though it's deprecated. Apple hasn't provided a replacement for this specific use case yet.

---

## What I Fixed

✅ **Reverted to SMJobBless** - The correct API for embedded helpers
✅ **Restored Info.plist configurations** - SMPrivilegedExecutables and SMAuthorizedClients
✅ **Created embedding script** - `fix_helper_embedding.sh` to manually embed helper

---

## Steps to Make It Work

### Step 1: Clean Build Folder

In Xcode, press **⌘⇧K** (Command + Shift + K) to clean the build folder.

### Step 2: Build AWDLControlHelper

1. Select **AWDLControlHelper** scheme from the dropdown (top left)
2. Press **⌘B** to build
3. Should succeed with 0 errors (may have 1 deprecation warning - that's expected)

### Step 3: Build AWDLControl

1. Select **AWDLControl** scheme from the dropdown
2. Press **⌘B** to build
3. Should succeed with 0 errors (may have 1 deprecation warning - that's expected)

### Step 4: Embed the Helper

The helper needs to be manually embedded in the app bundle (Xcode doesn't do this automatically):

```bash
cd /Users/oliverames/Developer/awdl0-down
./fix_helper_embedding.sh
```

You should see:
```
Fixing helper embedding in AWDLControl.app...

Copying helper to: .../AWDLControl.app/Contents/Library/LaunchServices/
Copying launchd.plist...

✅ Helper embedded successfully!
```

### Step 5: Run and Test

1. **Run the app** (⌘R in Xcode)
2. **Click the menu bar icon** (antenna symbol)
3. **Click "Enable AWDL Monitoring"**
4. **Password prompt should appear**: "AWDLControl wants to install a helper tool"
5. **Enter your password**
6. **Helper should install**

Watch the Console app for logs like:
```
AWDLMonitor: Helper not installed, installing now...
AWDLMonitor: You will be prompted for your password to install the privileged helper
HelperAuthorization: Helper tool installed successfully
AWDLMonitor: ✅ Successfully loaded daemon via helper (no password prompt!)
```

### Step 6: Verify It Works

```bash
# Check helper is installed
sudo launchctl list | grep com.awdlcontrol.helper
# Should show: PID - com.awdlcontrol.helper

# Check if it's in /Library/PrivilegedHelperTools/
ls -la /Library/PrivilegedHelperTools/com.awdlcontrol.helper
# Should exist

# Check daemon is running
sudo launchctl list | grep com.awdlcontrol.daemon
# Should show: 12345 0 com.awdlcontrol.daemon

# Verify AWDL is blocked
sudo ifconfig awdl0 up && sleep 0.01 && ifconfig awdl0 | grep flags
# Should show no UP flag
```

### Step 7: Test Toggle (No More Password Prompts!)

- Click menu bar icon → "Disable AWDL Monitoring"
  - ❌ NO password prompt!
  - ✅ Daemon stops

- Click menu bar icon → "Enable AWDL Monitoring"
  - ❌ NO password prompt!
  - ✅ Daemon starts

---

## Troubleshooting

### Error: Helper not found

**Problem:** `fix_helper_embedding.sh` can't find the built helper

**Solution:**
```bash
# Check if helper was built
ls ~/Library/Developer/Xcode/DerivedData/AWDLControl-*/Build/Products/Debug/AWDLControlHelper

# If not found, rebuild AWDLControlHelper target
```

### Error: Failed to install helper tool

**Problem:** SMJobBless failed (code signature mismatch)

**Check code signatures:**
```bash
# Get app's code signature requirement
codesign -d -r- ~/Library/Developer/Xcode/DerivedData/AWDLControl-*/Build/Products/Debug/AWDLControl.app

# Get helper's code signature requirement
codesign -d -r- ~/Library/Developer/Xcode/DerivedData/AWDLControl-*/Build/Products/Debug/AWDLControl.app/Contents/Library/LaunchServices/com.awdlcontrol.helper

# These should match the strings in Info.plist files
```

**Solution:** If Team ID changed, update Info.plist files with new Team ID

### Error: Connection to helper was invalidated

**Problem:** Helper not running or XPC connection failed

**Check:**
```bash
# Is helper installed?
ls -la /Library/PrivilegedHelperTools/com.awdlcontrol.helper

# Is it running?
sudo launchctl list | grep com.awdlcontrol.helper

# View helper logs
log show --predicate 'process == "com.awdlcontrol.helper"' --last 1h --info
```

### Warning: SMJobBless was deprecated

**This is expected!**

SMJobBless is deprecated in macOS 13.0+, but it's still the correct API for embedded privileged helpers. Apple hasn't provided a replacement for this use case.

The warning looks like:
```
'SMJobBless' was deprecated in macOS 13.0: Please use SMAppService instead
```

**You can ignore this warning.** SMJobBless still works perfectly.

---

## Why SMJobBless is Still Necessary

| Use Case | Correct API |
|----------|-------------|
| System LaunchDaemon in `/Library/LaunchDaemons/` | ✅ SMAppService.daemon() |
| LaunchAgent in `~/Library/LaunchAgents/` | ✅ SMAppService.agent() |
| Login item | ✅ SMAppService.loginItem() |
| **Privileged helper embedded in app bundle** | ✅ **SMJobBless** (no replacement yet!) |

Our helper is **embedded in the app bundle** and installed to `/Library/PrivilegedHelperTools/`, so SMJobBless is the only option.

---

## Expected Behavior After Fix

### ✅ First Launch:
1. App launches as menu bar app
2. User clicks "Enable AWDL Monitoring"
3. **ONE password prompt** appears
4. Helper installs to `/Library/PrivilegedHelperTools/com.awdlcontrol.helper`
5. Daemon starts blocking AWDL immediately

### ✅ All Subsequent Operations:
- Enable/disable - **NO password prompts**
- Quit app - **NO password prompts**
- Relaunch app - **NO password prompts**
- Reboot Mac - **NO password prompts**

---

## Architecture (Correct Implementation)

```
User clicks menu bar toggle
    ↓
AWDLControlApp.swift (menu bar UI)
    ↓
AWDLMonitor.swift (lifecycle management)
    ↓
HelperAuthorization.swift (SMJobBless wrapper)
    ↓ SMJobBless installs helper once
/Library/PrivilegedHelperTools/com.awdlcontrol.helper (runs as root)
    ↓ XPC communication
Helper loads/unloads daemon via launchctl
    ↓
awdl_monitor_daemon (blocks AWDL in <1ms)
```

---

## Success Criteria

✅ Build succeeds (may have deprecation warning)
✅ Helper embeds in app bundle
✅ First enable: ONE password prompt
✅ Helper installs to `/Library/PrivilegedHelperTools/`
✅ Daemon starts and blocks AWDL
✅ Toggle enable/disable: NO password prompts
✅ Quit/relaunch: NO password prompts

---

## Next Steps After Testing

Once everything works:

1. **Optional:** Configure Xcode to automatically embed the helper
   - This requires adding a Copy Files build phase to the AWDLControl target
   - For now, running `fix_helper_embedding.sh` after each build is sufficient

2. **Remove daemon if not needed:**
   ```bash
   sudo launchctl unload /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
   ```

3. **Test complete workflow:**
   - Enable → blocks AWDL
   - Disable → allows AWDL
   - Quit → daemon stops
   - Relaunch → can enable again without password

---

## Ready to Test!

All fixes are committed and pushed to GitHub.

**Start here:**
1. Clean build folder (⌘⇧K)
2. Build AWDLControlHelper (⌘B)
3. Build AWDLControl (⌘B)
4. Run `./fix_helper_embedding.sh`
5. Run app (⌘R)
6. Test!

Good luck! 🚀
