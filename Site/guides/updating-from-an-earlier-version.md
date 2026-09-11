# Updating from Ping Warden 2 or 3

If you are still on an older version and you have seen a note about a license, here is the short answer: updating does not cost you anything, and your protection keeps working.

Version 4 introduced a one-time $15 license for Ping Protection, the part that holds AWDL down. That change is real, but it does not land on existing users the day they update, and the free part of the app got no smaller.

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

If the app is running and has checked for updates, it will offer version 4 and ask you to confirm. Version 4 is never installed silently on top of an older version, because the licensing change is something you should read before accepting rather than discover afterwards.

You can also trigger it yourself from the menu bar icon, under **Check for Updates**, or download the current build from the [releases page](https://github.com/oliverames/ping-warden/releases/latest) and drag it over the old copy in Applications.

One thing worth knowing if you only ever used the free dashboard and never approved the helper: on versions before 4.1.6, automatic update checks did not start at all in that state, so you may never have been offered anything. Using **Check for Updates** from the menu works regardless, and once you are on 4.1.6 or later the automatic checks run normally.

## If you would rather not update

Nothing stops working on an older version. The one thing you give up is fixes, and some of those matter: 2.4.2 and 2.4.3 fixed crashes that can abort the app on recent macOS. The [release notes](../../RELEASE_NOTES.md) list what changed in each version.

## Still deciding whether you need any of this

If you are not sure AWDL was ever your problem, the free dashboard answers that before you spend anything. Run it during a session that normally stutters and watch whether the spikes line up with anything at all. The [AirDrop and Wi-Fi lag guide](airdrop-wifi-lag.md) walks through the same test from the command line, and it works on any version.
