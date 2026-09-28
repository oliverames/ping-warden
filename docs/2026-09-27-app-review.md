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

Generation tokens, the license gate, persistent-protection recovery, and a26e6fe's probe and repair each complete exactly once. The weak spot is the gap between app state and what the helper enforces. The fixes add `scripts/test_coordinator.py` (111 checks, run in CI), which compiles the production coordinator and monitor against in-memory stubs; each of 26 reverted fixes fails a test. Welcome-window parts of B5 and B14 moved to the lane C batch.

| ID | Sev | Finding | Status |
|---|---|---|---|
| B1 | P0 impact | a26e6fe's Off shortcut trusted one interface reading, so an Off could skip the stop while the helper enforced, and the skip persisted through `lastKnownState`. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B2 | P1 | The menu item "Turn Off Ping Protection" could turn protection on, and "Turning On Protection" could show indefinitely. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B3 | P1 | A helper restart during a session ended protection for the rest of the game. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B4 | P2 | The app's own distributed notification echoed back and cleared messages, including license-revocation text. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B5 | P2 | Repair was not single-flight. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B6 | P2 | A "Lost connection" alert fired during a repair that then succeeded. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B7 | P2 | Launch opened Login Items with no user action. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B8 | P2 | Automated paths raised modal alerts, some over games, and setup failures stacked duplicates. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B9 | P2 | The saved intent was not retried after the helper recovered. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B10 | P2 | Control Center shows stale "Protected" after an app crash. | Deferred to the #92 redesign |
| B11 | P2 | Quit might leave AWDL down up to 60 s; a pending first enable at quit sent no stop. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B12, B13 | P3 | Generation guards and launch sent three enables. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B14 | P3 | Several messages pointed at restarting or the helper test instead of Repair, or warned falsely. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B15 | P3 | Dashboard Finish Setup still used the unverified registration path. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| B16 | P3 | No sleep or wake handling. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |
| A-B | P2 | XPC error handlers never signaled, so rejections looked like 2 s timeouts. | Fixed in 7eb2091 (tests 78c00ee, 2ba9c5e) |

## Lane E: widget sandbox (#92) and PR #95 (#96)

**#92 design.** Today the widget runs its control intents in the extension and connects to the helper's global Mach service, which a sandboxed extension cannot look up. Three options were weighed:

1. A temporary-exception entitlement for the Mach lookup. Smallest change, but Apple labels it temporary and it fails #92's "App Group only" acceptance.
2. An App-Group-prefixed second Mach service on the helper. Meets the acceptance, but existing installs depend on launchd picking up a changed plist for an existing registration, which Apple DTS could not confirm.
3. **Recommended:** run the control intents in the app process (`supportedModes` with a foreground mode on macOS 26, `allowedExecutionTargets = .main` on macOS 27) and make the widget a sandboxed, display-only extension with only the App Group. The helper then admits only the app. No plist or preference changes.

Option 3 needed a signed spike. **Result, 2026-09-28 on macOS 27.2: blocked.** chronod routes the control's intent to the app (through `allowedExecutionTargets = .main`, or through any foreground-capable mode, which it treats as ForegroundContinuableIntent), then fails to connect with `Operation not permitted`. That happened with the app quit or running, sandboxed or not, and without `get-task-allow`. A sandboxed, App Group–only widget does load and run the intent in its own process, so options 1 and 2 remain. Not tested: macOS 26, a notarized build, or an app with a provisioning profile. Run table: `~/Developer/Projects/ping-warden-intent-spike/SPIKE-RESULTS.md`; summary on #92. **Needs Oliver:** retest option 3 notarized, or move to option 2 and test its launchd plist-update risk on this Mac.

**PR #95.** All eight findings below are fixed on the PR branch (5d72ca5, 1a02aaa), which was merged with main at afc7a0d and pushed as a066756 on 2026-09-28. The PR stays a draft until the Developer ID checks in #96 pass. Existing Hide Menu Bar Icon users keep the 4.2.1 behavior, where the menu bar icon is hidden and the Dock icon forced on. The new mode lives under `ControlCenterOnlyEnabled`, and no saved value is rewritten. The original review found these required before merge:

- E1 (P1): the update silently removes the Dock icon for existing "Hide Menu Bar Icon" users, whose Dock icon the old code forced on. Keep them on the old behavior until they opt in, using a new preference key.
- E3 (P2): the naive conflict resolution with a26e6fe stacks Settings, the Welcome, and the license notice at launch.
- E4 (P3): stale copy says the setting "only hides the menu bar icon".
- E8 (P3): regenerate the conflicting generated site files.

Recommended: E2 (Settings may open at every login after session restore) and E5 (a 26 to 44 ms signature check on the main thread on every window close; cache it). E6: the PR's launch-argument signal collides with #92's Option 3; abstract the launch reason. E7 (Settings opens after each Sparkle update in this mode) is probably acceptable.

## Lane C: UI, UX, and accessibility

The UI is native and mostly consistent, and the #90 fixes that could be exercised in the isolated fixture work (content cards without glass, license-field Return, focus after an invalid host, final-reminder copy). The problems are mostly error surfaces and copy. Screens were checked in a renamed-bundle, unsigned fixture on macOS 27.2 in light and dark, at default and minimum sizes. The installed app never ran.

| ID | Sev | Finding | Status |
|---|---|---|---|
| C1 | P1 | A mistyped license key is reported as "refunded, cancelled, or disabled", because every Gumroad `success:false`, including an unknown key, maps to revoked. | Fixed in 07347a7 and 869bd34: neutral copy; licensing logic unchanged |
| C2 | P2 | The Dashboard shows the protection error twice, and VoiceOver calls the first a session error. | Fixed in 2aa7f25 and c6eb9c1: shown once, in the Ping Protection card, with an inline Repair button |
| C3 | P2 | The Welcome window clips its license line at the default size and mixes alignments. | Fixed in a86ac79 |
| C4 | P2 | The Welcome failure copy points to Advanced settings, which the window cannot reach; its retry button already runs repair. | Fixed in a86ac79 |
| C5 | P2 | Dashboard Finish Setup fails silently and uses a third setup path. | Fixed with B15 in 7eb2091 |
| C6 | P2 | Repair shows no progress and no success message. | Fixed in 7eb2091 (progress) and 869bd34 (result alerts) |
| C7 | P2 | Helper alerts use jargon ("via XPC"), the title "Error", and conflicting advice. | Fixed in 7eb2091 and 869bd34 |
| C8 | P2 | The empty license field is invisible, and "License verified" never shows. | Fixed in 869bd34, as a plain text field per Oliver |
| C9 | P2 | The one-minute chart axis reads like clock time, the line takes the latest sample's color, and the legend glyphs never appear in the plot. | Fixed in 2aa7f25 |
| C10 | P2 | The application menu lacks Check for Updates (a #90 item). | Fixed in 869bd34 |
| C11 | P2 | Prepare to Remove does not say it deletes the saved license key and the transition marker. | Fixed in 869bd34 (copy only) |
| C12–C23 | P3 | Repeated license text, wrong "below" in the host error, a clickable-looking status line, the macOS 15 "Login Items & Extensions" name, outdated Gatekeeper instructions, crash-report copy, terminology drift, VoiceOver labels, Dashboard nits, repeated Automation text, About and Help nits, and a repetitive Welcome headline. | Fixed: Settings, menu, Welcome, and alerts in 07347a7, a86ac79, 869bd34; Dashboard and Targets in 52dab46, 2aa7f25, c6eb9c1; remaining three-dot ellipses in 609c4e5 |

Oliver decided on 2026-09-27: windows open at about 900×780 (done in 869bd34, saved frames kept), the license field is plain text (done), and unlicensed first runs lead with Open Dashboard (done in a86ac79). Undo for target deletion is done (Edit → Undo Remove Target, 52dab46 and 2aa7f25). The original questions were: D1 initial window size (980×1000 leaves about 40% empty; suggest about 900×780, keeping the saved frame); D2 Undo for custom-target deletion (suggest Edit → Undo, no confirmation); D3 whether unlicensed first runs should lead with the helper setup or with Open Dashboard; D4 a plain rather than secure license-key field, which makes paste mistakes visible.

## Lane D: performance and energy

Idle cost with the Dashboard closed is very low: 0.003% CPU, 0.07 wakeups per second, and a flat 18 MB, rising to 0.03% with Game Mode auto-detect on. The open Dashboard is where the cost is, and it keeps rendering when hidden, minimized, or covered. Measured on an M2 Pro with macOS 27.2 in an isolated fixture; Intel and macOS 13 would be slower and were not measured.

| ID | Sev | Finding | Status |
|---|---|---|---|
| D1 | P1 | The chart's x-axis tick dates change every sample, so SwiftUI/Charts retains about five new label views per second: 8 to 13 MB per minute while the Dashboard is open, freed only on close. Wall-clock-aligned ticks kept footprint flat in the fixture. | Fixed in 2aa7f25 |
| D2 | P1 | The Dashboard renders at full cost (about 4.6% CPU at 1 s) while hidden or minimized, the likely case behind a fullscreen game. | Fixed in 2aa7f25: redraws wait while hidden and catch up once |
| D3 | P2 | The chart rebuilds 720 points and a per-point area mark every sample, about 23 ms, and its downsampling shimmers as the window slides. | Fixed in 52dab46 and 2aa7f25: at most 360 time-aligned buckets, rebuilt about once per bucket |
| D4 | P2 | The settings window re-measures its whole layout every sample, about 9.7 ms. | Fixed in 869bd34 |
| D5 | P2 | About seven synchronous `SMAppService.status` calls per Dashboard render. | Fixed in e6ed6e3: a cached value, invalidated on changes and after 2 s |
| D6–D13 | P3 | Duplicate intervention polls and unconditional publishes, noisy error logging, 10 wakeups per timed-out probe, telemetry on the Targets pane, a Screen Recording check every Game Mode tick, main-thread downsampling, undownsampled timeline marks, and a `route` launch on every Dashboard appearance. | Fixed in 57bad02, 83e4b8b, e6ed6e3, 76eac95, 52dab46, 2aa7f25, and 869bd34 (Game Mode permission check). Chart bucketing still runs on the main thread, now about once per bucket instead of every sample |

Before and after in the same fixture on 2026-09-28, with a 1-second probe interval (footprint is the memory macOS charges to the process):

| Case | Before | After |
|---|---|---|
| Footprint over 6 minutes, 1-hour range | 95 → 143 MB | 68 → 76 MB |
| Footprint over 6 minutes, 1-minute range | 66 → 107 MB | 65 to 70 MB, flat |
| Visible, 1-hour range | 5.9% CPU, 162 mW | 2.6% CPU, 62 mW |
| Hidden | 5.6% CPU, 174 mW, 12.9 wakeups/s | 0.23% CPU, 4.6 mW, 1.3 wakeups/s |
| Minimized | 5.6% CPU, 172 mW | 0.22% CPU, 4.8 mW |

A later 10.5-minute run after the fix stayed between 62 and 73 MB with no upward trend.
