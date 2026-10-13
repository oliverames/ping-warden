# Troubleshooting

Start with the checks below. Ping Warden includes its own helper repair, diagnostics snapshot, and removal-preparation flows, so Terminal cleanup should not be the first step.

On macOS 15 and later the System Settings page is called **Login Items & Extensions**. On macOS 13 and 14 it is called **Login Items**. Ping Warden's messages use the name that matches your Mac.

## Messages you might see

Find the message Ping Warden shows, then follow the steps under it. Messages appear in the menu bar menu, in alerts, on the Dashboard, under **Settings → General**, or in the **Run Test** result under **Settings → Advanced**.

- [Status: Not Set Up](#status-not-set-up)
- [Helper Approval Timed Out](#helper-approval-timed-out)
- [Helper Setup Failed](#helper-setup-failed)
- [Setup did not finish](#setup-did-not-finish)
- [Move Ping Warden to Applications](#move-ping-warden-to-applications)
- [Ping Warden Needs to Be Reinstalled](#ping-warden-needs-to-be-reinstalled)
- [macOS Could Not Verify Ping Warden](#macos-could-not-verify-ping-warden)
- [Helper Not Responding](#helper-not-responding)
- [Helper Still Not Responding](#helper-still-not-responding)
- [AWDL Is Still Active](#awdl-is-still-active)
- [Protection Could Not Be Restored](#protection-could-not-be-restored)
- [Ping Protection could not turn off or pause](#ping-protection-could-not-turn-off-or-pause)
- [License messages](#license-messages)
- [Maintenance Could Not Finish](#maintenance-could-not-finish)

### Status: Not Set Up

**What you'll see:** Any of these.

- The menu reads **Status: Not Set Up**, and the protection item reads **Finish Setup…**.
- **Settings → General** shows **Status: Not Set Up** and "Approve the helper to finish setup".
- **Run Test** reports **Helper Not Set Up**: "Click Finish Setup… in General, then allow Ping Warden in Login Items & Extensions."
- The Dashboard or Settings says "Ping Protection is waiting for setup. Choose Finish Setup… to approve the helper in Login Items & Extensions."
- "Finish Ping Protection setup before recording a latency session."

**What it means:** macOS has not approved Ping Warden's helper, or the approval was turned off. Without it, Ping Warden cannot change the AWDL interface. The "waiting for setup" message appears when protection was on before and the helper approval is now missing. Ping Warden never opens System Settings on its own at launch; it waits for you.

**What to do:**

1. Choose **Finish Setup…** from the menu bar menu, the Dashboard, or **Settings → General**.
2. When macOS shows **Background Items Added**, or when Ping Warden opens System Settings, go to **System Settings → General → Login Items & Extensions**.
3. Under **Allow in the Background**, turn on **Ping Warden**. If it is already listed but off, turn it on.
4. Return to Ping Warden. The status changes to **Protected**, or **Not Protected** if protection is off.

macOS can report a pending approval as an "Operation not permitted" registration result. That is expected until you approve the helper. The full walkthrough is in the [Setup Guide](QUICKSTART.md#5-approve-the-helper).

### Helper Approval Timed Out

**What you'll see:** An alert titled **Helper Approval Timed Out**: "Ping Warden did not get approval in time. Allow Ping Warden in System Settings → General → Login Items & Extensions, then try again."

**What it means:** Ping Warden waits about one minute for approval after you start setup. The helper is registered, but macOS still lists it as needing approval.

**What to do:**

1. Open **System Settings → General → Login Items & Extensions**.
2. Turn on **Ping Warden** under **Allow in the Background**.
3. Return to Ping Warden and click **Try Again** in the welcome window, or **Finish Setup…** in the menu or **Settings → General**.

### Helper Setup Failed

**What you'll see:** An alert titled **Helper Setup Failed** with one of these messages:

- "Ping Warden could not register its helper. Try again." followed by a detail from macOS.
- "Ping Warden could not complete helper registration. Try setting up Ping Protection again."
- "Ping Warden could not register its helper after several attempts. Open Settings → Advanced and click Repair… If that fails, check System Settings → General → Login Items & Extensions."

**What it means:** macOS refused or did not finish the helper registration.

**What to do:**

1. Confirm that you opened Ping Warden from `/Applications`.
2. Choose **Finish Setup…** again and approve Ping Warden when macOS asks.
3. If it fails again, open **Settings → Advanced** and click **Repair…** under **Repair Helper Connection**.
4. If it still fails, [reinstall safely](#reinstall-safely).

### Setup did not finish

**What you'll see:** The welcome window shows "Setup did not finish", the message from the setup alert that appeared just before, and a **Troubleshooting Guide** link. If there was no specific message, it reads "macOS did not finish approving the helper. Check Login Items & Extensions, then click Try Again." After **Finish Setup…** in Settings, the same failure appears in an alert titled **Setup Did Not Finish**.

**What it means:** Setup stopped before the helper answered. The message names the cause, and it matches one of the alerts in this list.

**What to do:** Find the message in this list, follow its steps, then click **Try Again**. The same message appears again if the problem remains.

### Move Ping Warden to Applications

**What you'll see:** An alert titled **Move Ping Warden to Applications**: "Quit Ping Warden, move it to Applications, and open it from there before setting up or repairing Ping Protection."

**What it means:** Ping Warden is running from Downloads, Desktop, Documents, or a temporary location macOS uses for apps opened straight from a download. macOS can prevent the helper from starting there, so Ping Warden stops before registering it.

**What to do:**

1. Quit Ping Warden.
2. Move Ping Warden to `/Applications` in Finder. If you opened it from the disk image, drag it from the disk image to Applications and eject the disk image.
3. Open Ping Warden from Applications and choose **Finish Setup…**.

Your settings and license stay saved.

### Ping Warden Needs to Be Reinstalled

**What you'll see:** An alert titled **Ping Warden Needs to Be Reinstalled**, with "Helper binary not found in app bundle.", "Helper configuration not found in app bundle.", or "Helper binary is not executable."

**What it means:** The copy of Ping Warden on this Mac is incomplete or damaged, so Ping Warden will not register or repair the helper from it.

**What to do:** [Reinstall safely](#reinstall-safely) from a fresh download.

### macOS Could Not Verify Ping Warden

**What you'll see:** An alert titled **macOS Could Not Verify Ping Warden**: "Download the current signed and notarized release from the official GitHub Releases page."

**What it means:** This copy was downloaded from the internet and is not signed with Ping Warden's Developer ID. Official releases never show this alert.

**What to do:** Click **Open Releases**, download the latest DMG, and replace your copy in Applications. If you built this copy yourself, try to open it once, then open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** for Ping Warden. On macOS 13 and 14 you can also Control-click the app in Finder and choose **Open**. Ping Warden will never ask you to remove quarantine attributes in Terminal.

### Helper Not Responding

**What you'll see:** Any of these.

- The menu reads **Status: Not Protected, Helper Not Responding**, and a **Repair Helper…** item appears.
- "Ping Warden's helper is not responding. Open Settings → Advanced and click Repair…"
- "Ping Protection could not turn on because the helper is not responding. Open Settings → Advanced and click Repair…"
- "Lost connection to the helper, so Ping Protection turned off. Open Settings → Advanced and click Repair…"
- "Ping Protection could not be restored after the helper restarted. Open Settings → Advanced and click Repair…"
- **Run Test** reports **Helper Not Responding**: "Click Repair… below. If that fails, restart your Mac and click Repair… again."

**What it means:** macOS lists the helper as approved, but the helper did not answer Ping Warden's request. This can happen after a macOS update, an interrupted install, or when macOS keeps an approval record that no longer starts the helper.

**What to do:**

1. Choose **Repair Helper…** from the menu bar menu, click **Repair…** on the Dashboard, or click **Repair…** under **Repair Helper Connection** in **Settings → Advanced**.
2. **Repair Helper Connection?** lists what happens next. Click **Repair**.
3. If macOS shows **Background Items Added** or Ping Warden is off in **Login Items & Extensions**, turn it on under **Allow in the Background**. macOS may ask for your password or Touch ID.
4. Wait for **Helper Is Responding**, followed by "Ping Protection is on. The Ping Warden icon shows a crossed-out antenna while it is active." or "Ping Protection is off."

**Behind the scenes:** Repair first asks the helper to answer. If it does not, Ping Warden removes the stale registration and registers the helper again, then waits for a reply. Your protection preference, settings, and session history stay as they are.

A brief **Status: Reconnecting to Helper** means Ping Warden is reconnecting to a helper that restarted. It clears once the helper answers. If it does not clear, run Repair.

### Helper Still Not Responding

**What you'll see:** After Repair, **Helper Still Not Responding**: "Ping Warden could not get a response from its helper," followed by three steps (turn Ping Warden on in **System Settings → General → Login Items & Extensions**, restart your Mac, try Repair again) and a **Troubleshooting Guide** button that opens this section. After **Finish Setup…** in Settings, you may instead see **Setup Did Not Finish**: "The helper was approved but is not responding. Restart your Mac, then open Settings → Advanced and click Repair…"

**What to do:**

1. Open **System Settings → General → Login Items & Extensions** and confirm that Ping Warden is on under **Allow in the Background**.
2. Restart the Mac.
3. Open Ping Warden and run Repair again.

If Repair still fails, macOS is keeping the helper's approval without starting it. In this state **Prepare to Remove** can stop with an error, because it first asks the silent helper to confirm that Ping Protection is off. Use these steps instead.

1. Quit Ping Warden.
2. Open **System Settings → General → Login Items & Extensions** and turn off Ping Warden under **Allow in the Background**.
3. Move `/Applications/Ping Warden.app` to the Trash and empty the Trash.
4. Restart the Mac.
5. Download a fresh DMG from the [latest release](https://github.com/oliverames/ping-warden/releases/latest), drag Ping Warden to Applications, and eject the disk image before you open the app.
6. Open Ping Warden from Applications, complete setup, and approve the helper when macOS asks.
7. Run **Settings → Advanced → Run Test**.

If the test still fails, reset the macOS background item records, restart the Mac, and repeat steps 5 through 7:

```bash
sfltool resetbtm
```

This resets background item approvals for every app on the Mac, so other apps may ask for approval again. If the helper still does not respond, follow [Collect useful diagnostics](#collect-useful-diagnostics) and include the snapshot in a bug report.

### AWDL Is Still Active

**What you'll see:** **Run Test** reports **AWDL Is Still Active**: "Ping Protection is on, but AWDL read as active. Run the test again. If it repeats, click Repair…"

**What it means:** The helper answered, but `awdl0` read as up while protection was on. macOS raises the interface often, and the helper lowers it again, so one reading can catch it in between. A repeated result means the helper is not keeping up.

**What to do:**

1. Click **Repair…** under **Repair Helper Connection** and confirm.
2. Run the test again.
3. If the result repeats, temporarily turn off VPN or other network-control software, then test again.
4. If it still repeats, [collect diagnostics](#collect-useful-diagnostics) and report the problem.

### Protection Could Not Be Restored

**What you'll see:** After Repair, **Protection Could Not Be Restored**: "The helper is responding again, but Ping Warden could not restore protection. Your saved protection preference has not changed." The Dashboard may say "The helper is responding again, but Ping Warden could not restore your protection preference."

**What to do:** The helper works again. Choose **Turn On Ping Protection** from the menu. If an alert mentions a license, see [License messages](#license-messages).

If Repair reports **Protection Change In Progress**, wait a few seconds and check the status in the menu. If it reports **Helper Repair Could Not Start**, wait for the current protection change to finish, then try Repair again.

### Ping Protection could not turn off or pause

**What you'll see:** An alert titled **Ping Protection Could Not Turn Off** or **Ping Protection Could Not Pause**, with "Ping Protection could not turn off. Quit Ping Warden to restore wireless sharing, then try again." or the same message for pausing.

**What it means:** The helper answered but could not change the interface.

**What to do:** Quit Ping Warden from the menu. When the app disconnects, the helper stops blocking and brings `awdl0` back up. Open Ping Warden again and retry.

If the message says the helper is not responding, follow [Helper Not Responding](#helper-not-responding). If wireless sharing stays unavailable, restart your Mac.

### License messages

| What you'll see | What to do |
| --- | --- |
| **Ping Protection Requires a License**: "Ping Protection needs a one-time $15 license. If you already bought one, enter the key in Settings → License." | Click **Buy a License…** to buy, or **Enter License Key…** to open **Settings → License**. Donated before version 4? Email oliver@ames.consulting. |
| "The transition period has ended." | Your free transition is over. Enter a license key in **Settings → License**. |
| "Ping Protection stayed off." at launch | Protection was on when Ping Warden last quit, but this Mac has no active license or transition. Enter a key in **Settings → License**. |
| "Gumroad did not accept this key. Check that you copied the whole key from your Gumroad receipt, then try again." | Copy the key again from the receipt email, without extra spaces or missing characters. If it still fails, email oliver@ames.consulting. |
| "That key does not look like a Gumroad license key. Check it and try again." | The pasted text is not in the license key format. Copy the license key itself from the receipt. |
| "Gumroad could not be reached. Connect to the internet and try again." | Connect to the internet and click **Verify** again. A key that was verified before keeps working offline for up to 14 days. |
| "The license for Ping Protection is no longer valid, so protection turned off." | Enter a valid key in **Settings → License**. If you think this is a mistake, email oliver@ames.consulting. |
| From the Control Center control: "Ping Protection requires a $15 one-time license. Open Ping Warden Settings → License to buy or enter your key." | Enter a key in **Settings → License**, then use the control again. |

### Maintenance Could Not Finish

**What you'll see:** After **Prepare to Remove**, an alert titled **Maintenance Could Not Finish** with one of these messages:

- "Ping Protection could not be turned off, so no settings were erased. Quit Ping Warden to restore wireless sharing, then try again."
- "The helper is not responding, so Ping Warden could not turn off protection safely. Click Repair… under Maintenance, then try again. If Repair fails, see the Troubleshooting Guide."
- A cause, followed by "Your previous Ping Warden settings were restored, and no local data was erased."
- A cause, followed by "Ping Warden could not fully restore the prior state. Open Settings → Advanced, click Repair…, and review Launch at Login before retrying. No local data was erased."

Removal failures include a **Troubleshooting Guide** button that opens this section.

**What to do:** Run Repair, then try **Prepare to Remove** again. If the helper is not responding and Repair cannot fix it, use the steps in [Helper Still Not Responding](#helper-still-not-responding) instead of the removal flow.

## Reinstall safely

Use the app's removal flow before deleting the application. It stops Ping Protection, restores AWDL, unregisters the helper and Launch at Login, clears Ping Warden's local data, and reveals the app in Finder.

1. Open **Settings → Advanced**, click **Prepare to Remove…**, and confirm with **Prepare to Remove**.
2. Move `/Applications/Ping Warden.app` to the Trash in Finder.
3. Download a fresh DMG from the [latest release](https://github.com/oliverames/ping-warden/releases/latest).
4. Drag Ping Warden to Applications and complete setup again.

**Prepare to Remove** also deletes this Mac's saved license key. Keep your Gumroad receipt so you can enter the key again.

If the app cannot open far enough to run its removal flow, do not delete LaunchDaemon files or shared containers by hand. [Open a bug report](https://github.com/oliverames/ping-warden/issues/new?template=bug_report.md) so the helper can be recovered without leaving AWDL in the wrong state.

## Ping Protection is active, but latency still spikes

Ping Warden addresses AWDL-related interruptions. Internet congestion, a busy router, VPN software, Location Services scans, and the remote service itself can also affect latency.

1. Open the dashboard and confirm that Ping Protection is active.
2. Open **Settings → Advanced** and run the helper test.
3. Check that the AWDL interface exists:

   ```bash
   ifconfig awdl0
   ```

4. Temporarily disable other network-control tools or VPN software, then test again.
5. Compare the dashboard against a target close to the service you are using. A public DNS target may not reflect the path to a game server.

If the helper test fails, follow the [message it shows](#messages-you-might-see). If it passes, export diagnostics and include the approximate time of the spike in the bug report.

## CPU or energy use is higher than expected

Use Activity Monitor's CPU and Energy tabs to confirm that Ping Warden is the process using resources.

1. Close the dashboard and compare usage. Faster dashboard update intervals perform more probes and chart updates.
2. Turn off **Game Mode Auto-Detect** under **Settings → Automation** and compare again.
3. Quit and reopen Ping Warden.
4. Export diagnostics and report the macOS version, app version, selected ping interval, and whether the dashboard was open.

Do not use a fixed CPU percentage as the only test. Activity Monitor readings vary with the Mac, selected interval, open windows, and current network state.

## Game Mode auto-detect does not work

### Check that the game is frontmost

Since 4.1.0, detection works from the frontmost app and needs no permission. Bring the game to the front and wait a few seconds; the menu bar status changes when protection engages. Detection is skipped while the Mac is on Ethernet.

### Optional: Screen Recording access

Screen Recording only adds detection of a fullscreen game sitting behind other windows. To enable it, open **Settings → Automation** and click **Enable Fullscreen Detection…**, or open **System Settings → Privacy & Security → Screen Recording** and turn on access for Ping Warden. Ping Warden reads only window metadata and never records or uploads the screen.

### Check the game

Automatic detection depends on the app metadata used by macOS Game Mode. Some fullscreen apps and games do not declare `LSApplicationCategoryType` or `LSSupportsGameMode`. Use the menu bar toggle when a title is not detected.

## The Control Center widget does not appear

The widget requires [macOS Tahoe 26](https://support.apple.com/en-us/122868) or newer and a signed Ping Warden release build.

1. Install the latest signed release from GitHub rather than a local debug build.
2. Click **Control Center** in the menu bar, then click **Edit Controls**.
3. Find **Ping Protection** and add it to Control Center, or drag it to the menu bar.

If **Control Center Only** in **Settings → General** shows **Unavailable**, the footer below it gives the reason:

- "Control Center widgets in Ping Warden require macOS 26 or newer." Update macOS, or use the menu bar icon.
- "The Ping Warden widget extension was not found in this app bundle. Reinstall Ping Warden from a signed release." [Reinstall safely](#reinstall-safely).
- "Control Center widgets require the app to be signed with Ping Warden's Developer ID certificate." This copy is a local or unofficial build. Install the official release.

If the control is added but reports "Ping Protection could not reach its helper. Open Ping Warden and finish setup." or "Ping Protection could not change. Open Ping Warden and finish setup.", open Ping Warden and check the menu status. Follow [Status: Not Set Up](#status-not-set-up) or [Helper Not Responding](#helper-not-responding).

## Ping Warden has no menu bar icon

**Control Center Only** in **Settings → General** (**Settings → Automation** in 4.3.0) replaces the menu bar icon with the Control Center toggle. Protection keeps running.

1. Open Ping Warden from Applications or Spotlight. If Settings does not appear, open it once more.
2. Turn off **Control Center Only** under **Settings → General** to bring the menu bar icon back. In 4.3.0 it is under **Settings → Automation**.

If you turned on **Hide Menu Bar Icon** in version 4.2.1 or earlier, Ping Warden keeps its Dock icon. Click the Dock icon to open Settings, then click **Show Menu Bar Icon** under **Settings → General** (**Settings → Automation** in 4.3.0). In 4.2.1 and earlier, turn off **Hide Menu Bar Icon** under **Settings → Automation** instead.

## The menu bar icon or Settings window stops updating

1. Turn Ping Protection off and back on.
2. Quit and reopen Ping Warden.
3. Confirm that the processes are present:

   ```bash
   pgrep -fl 'Ping Warden|PingWardenHelper'
   ```

4. Open **Settings → Advanced**, run the helper test, and export diagnostics if the problem continues.

## The app crashes on launch

1. Confirm that the Mac is running macOS 13 Ventura or newer:

   ```bash
   sw_vers
   ```

2. Open Console and search for the `Ping Warden` and `PingWardenHelper` processes.
3. Look for a Ping Warden crash report under **Crash Reports** in Console.
4. Reinstall the latest signed release. If the app can open Settings first, use **Settings → Advanced → Prepare to Remove** before reinstalling.

Do not clear the app's preferences or shared container before collecting diagnostics. That state can explain the crash and makes the report more useful.

## AirDrop, AirPlay, or Handoff does not work

These features depend on AWDL and are expected to be unavailable while Ping Protection is active.

- Choose **Turn Off Ping Protection** to restore them until you turn protection on again.
- Choose **Pause for 10 Minutes** if you need them briefly.
- If they remain unavailable after protection is off, quit Ping Warden and check the interface:

  ```bash
  ifconfig awdl0
  ```

Report the issue if `awdl0` does not return to an active state.

## Uninstall Ping Warden

1. Open **Settings → Advanced** and click **Prepare to Remove…** under **Remove Ping Warden**.
2. Read **Prepare Ping Warden for Removal?** and click **Prepare to Remove**. Ping Warden turns off Ping Protection, unregisters the helper and Launch at Login, and deletes its settings, custom ping targets, latency session history, this Mac's saved license key, and its transition status. Keep your Gumroad receipt to enter the key again.
3. Wait for Ping Warden to show the app in Finder and quit.
4. Move `/Applications/Ping Warden.app` to the Trash in Finder.
5. Confirm that AWDL has returned:

   ```bash
   ifconfig awdl0
   ```

The built-in flow is important because deleting the app alone does not reliably unregister its privileged helper. If the flow stops with **Maintenance Could Not Finish**, see [that message](#maintenance-could-not-finish).

## Collect useful diagnostics

1. Open **Settings → Advanced**.
2. Click **Create Snapshot** under Diagnostics Snapshot.
3. Review the text file before sharing it. It contains app and macOS versions, helper state, relevant settings, an AWDL status snapshot, and only the selected target category. Custom hostnames and IP addresses are redacted.
4. Note the approximate time of the problem and what Ping Warden was doing.
5. Attach the file to a [bug report](https://github.com/oliverames/ping-warden/issues/new?template=bug_report.md).

For a short read-only log sample, run:

```bash
log show --last 15m --predicate 'subsystem == "com.amesvt.pingwarden" OR process == "PingWardenHelper"' --info
```

Do not post unrelated Console output, account names, or network details that are not needed to reproduce the problem.

## Other sources of Wi-Fi latency

Location Services can ask macOS to scan nearby Wi-Fi networks. If the dashboard still shows spikes while Ping Protection is active, compare a test with Location Services disabled under **System Settings → Privacy & Security → Location Services**. You can also disable access for individual apps and system services instead of turning it off globally.

Ping Warden does not block Location Services scans.

## Known limitations

- Ping Warden requires macOS 13 Ventura or newer.
- Ping Protection temporarily disables AWDL-dependent features.
- Game Mode detection requires compatible app metadata; Screen Recording access is optional and only adds fullscreen games behind other windows.
- The Control Center widget requires macOS 26 or newer and a signed release build.
- Ping Warden addresses AWDL-related interruptions, not every source of network latency.
