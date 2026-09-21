# Quick start

Ping Protection keeps Apple's AWDL network interface offline. While it is active, AirDrop, AirPlay, Handoff, and other nearby-device features may be unavailable. You can turn protection off at any time or pause it for 10 minutes from the menu bar.

## Install and verify

### 1. Install Ping Warden

1. Buy the [Ping Warden License on Gumroad](https://amesconsulting.gumroad.com/l/pingwarden). The signed DMG is attached to the purchase and your license key arrives in the same email. To try the free features first, [download the same build from Releases](https://github.com/oliverames/ping-warden/releases/latest).
2. Open the DMG and drag Ping Warden to Applications.
3. Launch Ping Warden from Applications or Spotlight.

### 2. Activate your license (prebuilt app)

Ping Protection in the prebuilt app requires a one-time $15 license. Buy it at [Gumroad](https://amesconsulting.gumroad.com/l/pingwarden), then open **Settings → License** and enter the key. The app verifies once and then works offline for up to 14 days.

Updating from an earlier version, or donated before version 4? You may already have access without buying a key. **Settings → License** shows your current status, and [Pricing](../README.md#pricing) explains the transition and the donor path.

### 3. Approve the helper

The welcome appears automatically once. Choose **Not Now** to use the free dashboard and finish setup later.

1. Click **Turn On Ping Protection** in the welcome window (the button reads **Set Up Ping Warden** until a license or transition is active), or **Finish Setup** in **Settings → General** if you already closed it.
2. Approve Ping Warden in System Settings when macOS asks.
3. Return to Ping Warden after the approval is complete.

The helper needs one-time approval because changing the AWDL interface requires elevated access.

### 4. Turn on Ping Protection

Open the menu bar menu and choose **Turn On Ping Protection**. If you haven't activated a license (and you aren't in the transition period), the app will point you to **Settings → License**. The menu bar icon will show that protection is active.

### 5. Verify the connection

Open the dashboard and confirm that Ping Protection is active. Leave it open during a normal game or call to compare live latency, jitter, and probe failures. The intervention count records the helper's attempts to lower AWDL after macOS reactivates it. It does not measure confirmed blocks or spikes prevented.

For a helper health check, open **Settings > Advanced** and click **Run Test**.

## Automatic protection for games

1. Open **Settings > Automation**.
2. Turn on **Game Mode Auto-Detect**. No permission is needed.
3. Optional: click **Enable Fullscreen Detection…** and allow Screen Recording if you also want fullscreen games behind other windows caught.

Game Mode turns protection on when a recognized game is the frontmost app. Once no game is detected through either the frontmost or optional fullscreen path, it restores your previous protection state. Game Mode skips automatic activation on Ethernet. This rule does not disable protection that you enabled manually. Some games do not declare the metadata that macOS uses for Game Mode; use the menu bar toggle for those titles.

## Control Center widget

The Control Center widget requires [macOS Tahoe 26](https://support.apple.com/en-us/122868) or newer and a signed release build.

1. Open **Settings > Automation** and turn on **Hide Menu Bar Icon**.
2. Open **System Settings > Control Center**.
3. Find Ping Warden and add it to Control Center or the menu bar.

## Everyday controls

- Choose **Pause for 10 Minutes** when you need AirDrop, AirPlay, or Handoff briefly.
- Start a **Latency Session** from the dashboard when you want a beginning-to-end recap for one game or call. Starting a session enables Ping Protection and requires a license or an active transition. Past recaps remain free to view.
- Turn on **Launch at Login** under **Settings > General** if you want protection available after every restart.
- Use **Settings > Advanced > Diagnostics Snapshot** to create a local troubleshooting file you can review before sharing.

## Get help

- Read the [Troubleshooting guide](TROUBLESHOOTING.md).
- Read the [full documentation](README.md).
- [Report a bug](https://github.com/oliverames/ping-warden/issues/new?template=bug_report.md) with the exported diagnostics attached after you review it.
