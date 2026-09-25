# Competitor note: AWDL Toggle, September 25, 2026

Prepared for Oliver Ames. Observations were made on 2026-09-25 from the public Reddit thread, the GitHub repository, and its releases page. Star counts and comments will drift.

## What it is

- **Name and source:** AWDL Toggle, [github.com/yay/awdl-toggle](https://github.com/yay/awdl-toggle), announced by u/Dependent_Grand1573 in [r/MacOSBeta](https://www.reddit.com/r/MacOSBeta/comments/1wh0gc5/awdl_toggle_a_small_macos_utility_to_help_with/) on 2026-09-15.
- **Traction on 2026-09-25:** 13 stars, 0 forks, 9 commits, releases 1.0.0 and 1.0.1 (both 2026-09-15).
- **License and price:** MIT, free.
- **Scope:** a manual On/Off switch in Control Center that can be dragged to the menu bar. It has no Game Mode, app detection, dashboard, latency data, or permanent app icon.
- **Architecture:** an Objective-C LaunchDaemon helper using `AF_ROUTE` route events and `SIOCSIFFLAGS`, with a root-owned state file and a code-signature allowlist for XPC clients. It ships a `--status/--on/--off` command-line interface and separate install, repair, and uninstall packages.
- **Provenance:** its README says the event-driven monitor is adapted from James Howard's AWDLControl, the same project Ping Warden credits.
- **Requirements:** macOS 26 or later. It is ad-hoc signed, not Developer ID signed or notarized, so Gatekeeper blocks the download until the user overrides it. The release notes say live testing was on macOS 27 and macOS 26 is unverified.

## How it compares

| | AWDL Toggle | Ping Warden |
|---|---|---|
| Price | Free | Free dashboard; $15 once for Ping Protection |
| macOS | 26+ | 13+ (Control Center toggle on 26+) |
| Signing | Ad-hoc, not notarized | Developer ID, notarized |
| Control Center toggle | Yes, the whole product | Yes, since the first commit on 2025-10-26 ("Create macOS AWDL Control app with ControlWidget API") |
| No app icon | Yes | Yes, with Control Center mode on this branch (PR #95) |
| Automation | None | Game Mode, Latency Sessions, 10-minute pause |
| Evidence | None | Live latency, jitter, history, intervention counter |
| Updates | Manual reinstall | Sparkle |

## What it means

- **The toggle is not a differentiator by itself.** Both apps have it. What still separates Ping Warden is the signed install, macOS 13 support, automation, and the latency evidence. The marketing on PR #95 names the toggle so it no longer looks like a gap.
- **"No icon" was a real gap.** The author said they built it partly because AWDLControl's menu bar icon could not be removed. Ping Warden could hide the menu bar icon but forced the Dock icon on. PR #95 makes Control Center mode hide both.
- **Price is the durable difference.** A free, single-purpose switch covers people who only want AWDL off. Ping Warden's guides already send those people to free options, and the awdl0 guide now lists AWDL Toggle beside awdlkiller and AWDLControl.
- **Name confusion continues.** In the thread, u/Pigeon_Observation pointed people to AWDLControl, not Ping Warden. This matches the correction drafted on 2026-09-14.

## What the thread shows about demand

Commenters named Moonlight streaming, Discord, and iPad-as-trackpad apps as the latency they were fighting. One asked whether turning off AirDrop and Continuity is enough. The author answered that other apps can still request AWDL. Another asked about unreliable Universal Clipboard, which the author said this does not fix.

## Reply draft

Destination: the r/MacOSBeta thread above. It is optional, and my recommendation is to skip it. The thread is ten days old, the subreddit is for macOS betas, a moderator has already removed one comment there, and the author was generous about crediting prior work. A reply from a paid competitor adds little and is easy to read as promotion. If you do post, this version offers one useful test and discloses the conflict without linking.

> Nice work on the Control Center control. For anyone deciding whether AWDL is their problem before leaving it off: run `ping -i 0.2` against your router for a minute, then run `sudo ifconfig awdl0 down` in another window partway through. If the spikes repeatedly subside while it's down and come back when it returns, AWDL is a likely contributor. If nothing changes, look elsewhere. `sudo ifconfig awdl0 up` brings AirDrop back.
>
> Disclosure: I maintain a similar app, so I've spent a lot of time staring at these graphs.

Not posted. Oliver decides whether and where to post.
