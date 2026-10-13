# Updating from Ping Warden 2 or 3

**On version 2.0.5 or earlier? You need a manual download to get current.** Quit Ping Warden, [download the latest DMG](https://github.com/oliverames/ping-warden/releases/latest), and replace the copy in Applications. Then launch Ping Warden from Applications. You do not need to install intermediate releases.

Versions through 2.0.4 have no working in-app updater. Version 2.0.5 introduced Sparkle, but its updater configuration was incomplete. Waiting for a prompt will not reliably bring these installations up to date.

Version 4 introduced a one-time $15 license for Ping Protection (plus VAT or sales tax where applicable). Downloading the update is free. Eligible existing users receive a 90-day transition, as described below. The dashboard, diagnostics, and past session recaps remain free.

## What happens when you update

If Ping Protection was already enabled on your Mac with the helper approved, updating starts a 90-day transition. It begins at your first launch of version 4, not at some date in the past, and there is no expiry on the offer. Updating today and updating a year from now both give you the same 90 days.

After you update, **Settings → License** shows the time remaining. Later updates preserve that original deadline, so staying current does not shorten it.

If the transition ends and you have not entered a key, protection stops and everything else keeps working. Nothing is deleted, and a key entered later turns it straight back on.

## What stays free

The dashboard, live latency, jitter, probe failures, history, the spike timeline, and the diagnostics export are all free, with no license and no privileged helper required. So are updates.

The source stays MIT. You can read it, change it, and build it yourself, with protection enabled, without paying. That has not changed and is not going to.

## What the $15 covers

Enabling Ping Protection in the prebuilt, signed, and notarized build. One key covers the Macs you own and every future update. There is no subscription and no ads, and the app sends no usage analytics.

It pays for the Developer ID signing and notarization, and for keeping the thing working as macOS changes. If you find the app useful, buying a license is what funds continuing to develop it.

## If you donated before version 4

Donations through Buy Me a Coffee made before version 4 are honored as full licenses. Email [oliver@ames.consulting](mailto:oliver@ames.consulting) with your receipt and you will get a key. You do not need to pay twice.

## How to update

For **2.0.5 and earlier**, use the manual download above.

For **2.0.6 and later**, choose **Check for Updates** from the menu bar icon. You may be offered an intermediate update before version 4. Check again after installing it. If no update appears or installation fails, quit the app and replace it using the [latest DMG](https://github.com/oliverames/ping-warden/releases/latest).

Version 4 requires confirmation before an in-app upgrade from an older free build. It is not installed silently. If you previously skipped the major upgrade, checking manually lets you reconsider it.

Before 4.1.6, automatic checks could depend on approval of the privileged helper. If you only used the dashboard, this may explain missing prompts. Manual checking is available in builds with an updater. From 4.1.6 onward, automatic checks start independently of helper approval.

## If you would rather not update

Nothing stops working on an older version. The one thing you give up is fixes, and some of those matter: 2.4.2 and 2.4.3 fixed crashes that can abort the app on recent macOS. The [release notes](../../RELEASE_NOTES.md) list what changed in each version.

## Still deciding whether you need any of this

If you are not sure AWDL was ever your problem, the free dashboard answers that before you spend anything. Run it during a session that normally stutters and watch whether the spikes line up with anything at all. The [AirDrop and Wi-Fi lag guide](airdrop-wifi-lag.md) walks through the same test from the command line, and it works on any version.
