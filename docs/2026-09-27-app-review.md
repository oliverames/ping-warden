# Ping Warden whole-app review, September 27, 2026

Oliver asked for a review of the code that takes AWDL down and of the rest of the app, followed by fixes for rough edges, performance, UI, and UX, and closure of open GitHub issues. Five read-only reviewers covered separate lanes against main at c86197e. Each finding below was checked against the code before it was fixed. Nothing here has been released.

Status key: **Fixed** (commit on main), **In progress**, **Needs Oliver** (a decision or a signed-build check), **Deferred** (with a reason).

## Lane A: helper daemon and AWDL enforcement

The helper's locking, exit-path restore, and XPC authorization were sound, and it passed ThreadSanitizer, ASan/UBSan, and the clang analyzer. The main gap was that enforcement depended on route messages the kernel can drop.

| ID | Sev | Finding | Status |
|---|---|---|---|
| A1 | P1 | Enforcement ran only on an awdl0 route message, read from a default 8 KB socket that drops messages silently when full, with no retry. Measured: an unread socket held 64 of 345 messages. | Fixed in 7aaa069: reconcile from actual flags on every route wakeup, a 5 s timeout, and a 250 ms retry; 256 KB buffer |
| A2 | P2 | Exit paths forced awdl0 up even when the helper never lowered it (Wi-Fi off, another tool). | Fixed in 7aaa069 for exit paths. "Turn off" still raises awdl0, which the app's stop confirmation relies on |
| A3 | P2 | No recovery after a helper crash or SIGKILL left awdl0 down. | Fixed in 7aaa069: `/var/run` marker, restored at next startup |
| A4 | P2 | Refusing to serve exited before check-in, which looks exactly like a launchd spawn failure, and logged no status. | Fixed in 7aaa069: logs the OSStatus, checks in, rejects connections, exits with code 1 |
| A5 | P2 | A poll error ended enforcement for good and blocked "allow". | Fixed in 7aaa069: back off and retry; allow works without the thread |
| A6 | P2 | `isAWDLEnabled` reported the instant macOS re-raised awdl0 while the helper was blocking. | Fixed in 7aaa069: the read enforces first |
| A7 | P2 | Tests faked the route socket with a pipe and never sent route messages; no sanitizer runs. | Fixed in 7aaa069: datagram socketpair, 11 new tests, TSan and ASan/UBSan passes in `test_helper.sh` |
| A8 | P2 | Enforcement latency unmeasured; no ProcessType or thread QoS. | Poll thread set to user-interactive in 7aaa069. ProcessType deferred: launchd may not pick up plist changes for an existing registration |
| A9 | P3 | A helper launched by a rejected peer never exited. | Fixed in 7aaa069: idle exit armed at launch |
| A10 | P3 | An idle helper woke for every route message (about 1.6 per second measured). | Fixed in 7aaa069: routes watched only while blocking |
| A11 | P3 | Logs used the default subsystem, and interventions logged without a rate limit. | Fixed in 7aaa069 |
| A12 | P3 | 32-bit intervention counter. | Fixed in 7aaa069 |
| A13 | P3 | Zero-width spaces in the Copy Helper Plist phase paths. | Fixed in ed60850 |
| A14 | P3 | SIGTERM handler installed after activation; `@available` else-branch failed open; no autoreleasepool in the poll loop. | Fixed in 7aaa069 |

Nothing in the shipped 4.2.1 helper is specific to macOS 13 or Intel. For the September 27 customer report, `launchctl print` distinguishes the causes: `runs = 0` means Background Task Management or launchd never started the helper (what a26e6fe's Repair rebuilds); `runs` above 0 with `last exit code = 1` means the helper refused to serve (A4).

## Lane B: app protection pipeline

Generation tokens, the license gate, persistent-protection recovery, and a26e6fe's probe and repair each complete exactly once. The weak spot is the gap between app state and what the helper enforces.

| ID | Sev | Finding | Status |
|---|---|---|---|
| B1 | P0 impact | a26e6fe's Off shortcut trusted one interface reading, so an Off could skip the stop while the helper enforced, and the skip persisted through `lastKnownState`. | In progress |
| B2 | P1 | The menu item "Turn Off Ping Protection" could turn protection on, and "Turning On Protection" could show indefinitely. | In progress |
| B3 | P1 | A helper restart during a session ended protection for the rest of the game. | In progress |
| B4 | P2 | The app's own distributed notification echoed back and cleared messages, including license-revocation text. | In progress |
| B5 | P2 | Repair was not single-flight. | In progress |
| B6 | P2 | A "Lost connection" alert fired during a repair that then succeeded. | In progress |
| B7 | P2 | Launch opened Login Items with no user action. | In progress |
| B8 | P2 | Automated paths raised modal alerts, some over games, and setup failures stacked duplicates. | In progress |
| B9 | P2 | The saved intent was not retried after the helper recovered. | In progress |
| B10 | P2 | Control Center shows stale "Protected" after an app crash. | Deferred to the #92 redesign |
| B11 | P2 | Quit might leave AWDL down up to 60 s; a pending first enable at quit sent no stop. | In progress |
| B12, B13 | P3 | Generation guards and launch sent three enables. | In progress |
| B14 | P3 | Several messages pointed at restarting or the helper test instead of Repair, or warned falsely. | In progress |
| B15 | P3 | Dashboard Finish Setup still used the unverified registration path. | In progress |
| B16 | P3 | No sleep or wake handling. | In progress |
| A-B | P2 | XPC error handlers never signaled, so rejections looked like 2 s timeouts. | In progress |

## Lane E: widget sandbox (#92) and PR #95 (#96)

**#92 design.** Today the widget runs its control intents in the extension and connects to the helper's global Mach service, which a sandboxed extension cannot look up. Three options were weighed:

1. A temporary-exception entitlement for the Mach lookup. Smallest change, but Apple labels it temporary and it fails #92's "App Group only" acceptance.
2. An App-Group-prefixed second Mach service on the helper. Meets the acceptance, but existing installs depend on launchd picking up a changed plist for an existing registration, which Apple DTS could not confirm.
3. **Recommended:** run the control intents in the app process (`supportedModes` with a foreground mode on macOS 26, `allowedExecutionTargets = .main` on macOS 27) and make the widget a sandboxed, display-only extension with only the App Group. The helper then admits only the app. No plist or preference changes.

Option 3 needs a signed spike to confirm macOS 26 routing before any shipped change. **Needs Oliver.**

**PR #95.** It compiles alone and merged with main, and its tests pass. Required before merge:

- E1 (P1): the update silently removes the Dock icon for existing "Hide Menu Bar Icon" users, whose Dock icon the old code forced on. Keep them on the old behavior until they opt in, using a new preference key.
- E3 (P2): the naive conflict resolution with a26e6fe stacks Settings, the Welcome, and the license notice at launch.
- E4 (P3): stale copy says the setting "only hides the menu bar icon".
- E8 (P3): regenerate the conflicting generated site files.

Recommended: E2 (Settings may open at every login after session restore) and E5 (a 26 to 44 ms signature check on the main thread on every window close; cache it). E6: the PR's launch-argument signal collides with #92's Option 3; abstract the launch reason. E7 (Settings opens after each Sparkle update in this mode) is probably acceptable.

## Lane C: UI, UX, and accessibility

Pending.

## Lane D: performance and energy

Pending.
