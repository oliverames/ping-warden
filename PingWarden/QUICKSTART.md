# Quick start

Ping Protection keeps Apple's AWDL network interface (`awdl0`) offline. While it is active, AirDrop, AirPlay, Handoff, and other nearby-device features may be unavailable. You can turn protection off at any time or pause it for 10 minutes from the menu bar.

This guide walks through every step of setup in order. Each step lists what you will see, what to do, and what Ping Warden and macOS are doing in the background. If something on screen does not match, the [Troubleshooting guide](TROUBLESHOOTING.md#messages-you-might-see) is organized by the exact message Ping Warden shows.

On macOS 15 and later the System Settings page is called **Login Items & Extensions**. On macOS 13 and 14 it is called **Login Items**. Ping Warden uses the name that matches your Mac, and this guide uses the newer name.

## Install and verify

### 1. Download Ping Warden

**What to do:** Buy the [Ping Warden License on Gumroad](https://amesconsulting.gumroad.com/l/pingwarden). The signed DMG is attached to the purchase, and your license key arrives in the same email. To try the free dashboard first, [download the same build from Releases](https://github.com/oliverames/ping-warden/releases/latest). You can buy a key later without reinstalling.

**Behind the scenes:** Every release is signed with Ping Warden's Developer ID and notarized by Apple, so macOS can confirm that the copy you downloaded is the one that was published.

### 2. Move it to Applications and open it

<!-- Screenshot: ![The Ping Warden disk image window, with the Ping Warden icon and an arrow pointing to the Applications folder](../docs/images/setup-dmg-drag.png) -->

**What you'll see:** A disk image window with the Ping Warden icon and an Applications folder.

**What to do:**

1. Drag Ping Warden onto the Applications folder.
2. Eject the disk image.
3. Open Ping Warden from Applications or Spotlight. Do not open it from the disk image, Downloads, Desktop, or Documents.
4. The first time, macOS asks you to confirm that you want to open an app downloaded from the internet. Click **Open**.

<!-- Screenshot: ![The macOS confirmation that asks whether to open Ping Warden, an app downloaded from the internet](../docs/images/setup-gatekeeper-open.png) -->

**Behind the scenes:** Gatekeeper checks the notarization before the first launch. Ping Warden's background helper must start from the copy in Applications. If you open the app from Downloads, Desktop, or Documents, or macOS runs it from a temporary location because it was never moved, setup stops with **Move Ping Warden to Applications** instead of registering a helper that macOS would refuse to start. Ping Warden does not check other folders outside Applications, so setup can fail there without that message. Keep the app in Applications. If macOS cannot verify the copy at all, Ping Warden shows **macOS Could Not Verify Ping Warden** with a button to open the official Releases page. See [Troubleshooting](TROUBLESHOOTING.md#macos-could-not-verify-ping-warden).

### 3. Read the welcome window

The welcome window opens automatically on the first launch. It is titled **Welcome to Ping Warden** and lists what the app does. Its buttons depend on whether this Mac can already turn on Ping Protection.

<!-- Screenshot: ![The Welcome to Ping Warden window for a licensed Mac, with the Turn On Ping Protection button and a Not Now link](../docs/images/setup-welcome-licensed.png) -->

**If you have a license or an active transition**, you'll see:

- **Turn On Ping Protection** as the main button.
- **Not Now** below it.
- "Setup asks for one approval in Login Items & Extensions."

<!-- Screenshot: ![The Welcome to Ping Warden window before a license is entered, with Open Dashboard, Set Up Ping Protection, Not Now, and the Enter or Buy a License link](../docs/images/setup-welcome-unlicensed.png) -->

**If you have not entered a license yet**, you'll see:

- **Open Dashboard** as the main button, because the dashboard is free.
- **Set Up Ping Protection** as a second button.
- **Not Now** below them.
- "Ping Protection is a one-time $15 purchase." with an **Enter or Buy a License…** link.

Every version of the window ends with: "Ping Warden sends anonymous crash and error reports. You can turn this off in Settings → Advanced."

**What to do:** If you already have a key, click **Enter or Buy a License…** and continue with step 4. If you are licensed or in the transition, skip to step 5. Choose **Not Now** to use the free dashboard and set up protection later.

**Behind the scenes:** Nothing changes on your Mac until you click a setup button. The window opens automatically only once. If you choose **Not Now**, the menu bar shows **Status: Not Set Up**, and the protection item in the menu reads **Finish Setup…**. Choosing it opens the welcome window again.

Crash and error reports include crash details, helper error codes, and app session counts. They never include ping targets, IP addresses, host names, network names, or license keys, and the [privacy section](../README.md#what-crash-reporting-sends) lists everything they send. To stop sending them, turn off **Send Crash Reports** under **Settings → Advanced → Privacy**. Turning it off takes effect immediately; the only thing sent afterward is one record that the current app session ended.

### 4. Enter your license key

<!-- Screenshot: ![Settings, License pane, with the License Key field, the Verify button, and the Buy a License button](../docs/images/setup-license-entry.png) -->

**What you'll see:** **Settings → License** opens with a **License Key** field that says "Paste your key from the Gumroad receipt", a **Verify** button, and a **Buy a License…** button. The status line reads "Enter a license key to enable Ping Protection."

**What to do:**

1. Copy the whole key from your Gumroad receipt email.
2. Paste it into the field and click **Verify**.
3. Wait for "License verified. Ping Protection is available." The status changes to **Licensed**.

<!-- Screenshot: ![Settings, License pane, after a key is verified, showing the Licensed status and the License verified message](../docs/images/setup-license-verified.png) -->

**Behind the scenes:** Ping Warden checks the key with Gumroad once. After that it works offline for up to 14 days between checks. The key is stored in your Mac's keychain.

If you are updating from an earlier version, the pane may show **Free Transition** instead. You already have access and do not need to buy anything yet. [Pricing](../README.md#pricing) explains the transition and the path for donors before version 4.

Opening the License pane closes the welcome window. To continue, choose **Finish Setup…** from the Ping Warden menu bar icon, or click **Finish Setup…** under **Settings → General**.

If Verify fails, see [license messages](TROUBLESHOOTING.md#license-messages).

### 5. Approve the helper

Ping Protection needs a small background helper. This is the only step that needs your approval in System Settings.

**What to do:**

1. Click **Turn On Ping Protection** in the welcome window. You can also click **Finish Setup…** in **Settings → General**, on the Dashboard, or in the menu bar menu.
2. The welcome window changes to "Waiting for approval" and says: "In System Settings, allow Ping Warden under Login Items & Extensions, then return here."
3. macOS shows a **Background Items Added** notification. If approval is still pending after about 10 seconds, Ping Warden opens **System Settings → General → Login Items & Extensions** for you. You can also click **Open Login Items & Extensions** in the welcome window.
4. Under **Allow in the Background**, turn on **Ping Warden**.
5. macOS may ask for an administrator password or Touch ID. That prompt comes from macOS, not from Ping Warden.
6. Return to Ping Warden.

<!-- Screenshot: ![The Welcome window in the Waiting for approval state, with the Open Login Items and Extensions button](../docs/images/setup-welcome-waiting.png) -->

<!-- Screenshot: ![The macOS Background Items Added notification for Ping Warden](../docs/images/setup-background-items-notification.png) -->

<!-- Screenshot: ![System Settings, General, Login Items and Extensions, with Ping Warden turned on under Allow in the Background](../docs/images/setup-login-items-allow.png) -->

Finish the approval within about a minute. If you take longer, Ping Warden shows **Helper Approval Timed Out** and the welcome window shows "Setup did not finish". Click **Try Again**. See [Troubleshooting](TROUBLESHOOTING.md#helper-approval-timed-out).

**Behind the scenes:** Ping Warden asks macOS to register its helper with Apple's `SMAppService` service, which is why macOS announces a new background item. Approval lets macOS start the helper when the app asks for it. Ping Warden then waits for the helper to answer before it reports that setup worked.

#### What the helper is and why it needs approval

The helper, `PingWardenHelper`, ships inside the Ping Warden app. macOS runs it as a system background item with administrator-level rights, because only a privileged process can take a network interface down. Ping Warden itself never runs with those rights.

The helper does one job: it keeps the `awdl0` interface down while Ping Protection is on.

- It reads and sets the up or down state of `awdl0` only.
- It counts its attempts to lower `awdl0` and reports its version and status to the app.
- It accepts requests only from the Ping Warden app and its Control Center control, signed by the same developer.
- It starts when the app asks for it. After the app disconnects, it stops blocking, brings `awdl0` back up if it was the one that lowered it, and exits.

The helper never:

- Touches Wi-Fi, Ethernet, or any interface other than `awdl0`.
- Reads, records, or sends your network traffic.
- Connects to the internet.
- Asks for your password. The only password prompt comes from macOS during approval.

You can turn the helper off at any time under **Allow in the Background** in **Login Items & Extensions**. Protection stops, and Ping Warden shows **Status: Not Set Up** until you approve it again. To remove it completely, use **Prepare to Remove**, described in [Uninstall Ping Warden](TROUBLESHOOTING.md#uninstall-ping-warden).

### 6. Confirm that Ping Protection is on

<!-- Screenshot: ![The Welcome window showing Setup complete. Ping Protection is on, with the Open Dashboard button](../docs/images/setup-welcome-complete.png) -->

**What you'll see:**

- The welcome window shows "Setup complete. Ping Protection is on." and an **Open Dashboard** button.
- If you have not entered a license, it shows "Helper ready. Ping Protection is off." The helper is approved, but protection stays off. After you [enter a license](#4-enter-your-license-key), choose **Turn On Ping Protection** from the menu bar or the Dashboard. Verifying a key does not turn protection on by itself.

**What to do:** Check any of these.

- **Menu bar icon:** The antenna icon gains a slash while protection is on. Hovering over it shows "Ping Protection: Active".
- **Menu:** The first line reads **Status: Protected**. The protection item reads **Turn Off Ping Protection**, and **Pause for 10 Minutes** appears below it.
- **Dashboard:** The **Ping Protection** card shows a **Turn Off** button and "Ping Protection is active."
- **Settings → General:** **Status** reads **Protected** with a green dot.

<!-- Screenshot: ![The Ping Warden menu open, showing Status: Protected, Turn Off Ping Protection, and Pause for 10 Minutes](../docs/images/setup-menu-protected.png) -->

<!-- Screenshot: ![The Dashboard Ping Protection card with the Turn Off button and the intervention attempt counter](../docs/images/setup-dashboard-protected.png) -->

For a full helper check, open **Settings → Advanced** and click **Run Test** under **Test Helper Connection**. A working helper reports **Helper Is Working**, with its version and "Ping Protection is on." Any other result is covered in [Troubleshooting](TROUBLESHOOTING.md#messages-you-might-see).

**Behind the scenes:** The menu, Dashboard, and Settings all read the state the helper reports, not just the setting you chose. The intervention counter records the helper's attempts to lower AWDL after macOS raises it again. It does not measure confirmed blocks or spikes prevented. Leave the Dashboard open during a normal game or call to compare latency, jitter, and probe failures.

## Automatic protection for games

1. Open **Settings → Automation**.
2. Turn on **Game Mode Auto-Detect**. No permission is needed.
3. Optional: click **Enable Fullscreen Detection…** and allow Screen Recording if you also want fullscreen games behind other windows caught.

**Behind the scenes:** Game Mode turns protection on and records a Latency Session while a recognized game is the frontmost app. The menu shows **Status: Protected, Game Mode Session Active**. Once no game is detected through either the frontmost or the optional fullscreen path, it restores your previous protection state. Game Mode skips automatic activation on Ethernet and needs a license or an active transition. It does not turn off protection that you enabled yourself. Some games do not declare the metadata macOS uses for Game Mode; use the menu bar toggle for those titles.

Screen Recording only lets Ping Warden read window metadata to notice a fullscreen game. Ping Warden never captures or saves screen contents.

## Control Center widget

The Control Center widget requires [macOS Tahoe 26](https://support.apple.com/en-us/122868) or newer and a signed release build.

1. Click **Control Center** in the menu bar, then click **Edit Controls**.
2. Find **Ping Protection** and add it. To pin it to the menu bar, drag it there while you edit.
3. Optional: open **Settings → General** (**Settings → Automation** in 4.3.0) and turn on **Control Center Only**. Ping Warden asks "Use Control Center Only?" Click **Use Control Center Only**, and the toggle replaces Ping Warden's menu bar and Dock icons. Open Ping Warden from Applications or Spotlight to return to Settings. Version 4.2.1 and earlier offer **Hide Menu Bar Icon** instead, which keeps the Dock icon.

<!-- Screenshot: ![Control Center in edit mode with the Ping Protection control added](../docs/images/setup-control-center.png) -->

The control uses the same helper, so it needs the approval from step 5. If **Control Center Only** shows **Unavailable**, the footer below it explains why. See [The Control Center widget does not appear](TROUBLESHOOTING.md#the-control-center-widget-does-not-appear).

## Everyday controls

- Choose **Pause for 10 Minutes** from the menu bar when you need AirDrop, AirPlay, or Handoff briefly. The menu shows **Status: Paused** and offers **Resume Ping Protection**. After 10 minutes, protection returns to your saved choice. Pausing ends a running Latency Session. A Game Mode session starts again after the pause if the game is still running, but a Latency Session you started yourself stays ended.
- Choose **Turn Off Ping Protection** to restore those features until you turn protection on again.
- Start a **Latency Session** from the dashboard when you want a beginning-to-end recap for one game or call. Starting a session enables Ping Protection and requires a license or an active transition. Past recaps remain free to view.
- Turn on **Launch at Login** under **Settings → General** if you want protection available after every restart.
- Use **Settings → Advanced → Diagnostics Snapshot** to create a local troubleshooting file you can review before sharing.

## Get help

- Read the [Troubleshooting guide](TROUBLESHOOTING.md).
- Read the [full documentation](README.md).
- [Report a bug](https://github.com/oliverames/ping-warden/issues/new?template=bug_report.md) with the exported diagnostics attached after you review it.
