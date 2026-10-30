# Ping Warden Worklog


## 2026-10-29 - Publish 4.4.2 helper diagnostics

**What changed:** Published 4.4.2 (build 44200) from main e8afe6a after PR #162 passed its required checks. The release reports the helper's reason for a declined enable and retains disable-failure telemetry when connection validation ends first. The canonical release produced a fresh universal archive, Developer ID signatures, Apple-accepted app and disk-image notarizations, a stapled and mounted-payload-verified disk image, signed stable and beta feeds, the GitHub download, Sentry symbols and release, and a verified Gumroad buyer download with license content preserved. Homebrew tap commit 612ffb6 publishes the matching checksum; the in-repository cask and generated website now match.

**Verification:** The reviewed source passed 347 core tests, the monitor regression harness, and 108 crash-reporter checks. The regenerated site validates its pages, links, structured data and sitemap, and all seven worker tests pass. The first packaging attempt failed while the Mac's disk-image services were busy; its temporary artifacts disappeared during interruption. The successful retry rebuilt through the full canonical pipeline without skipping artifact or publication guards. No installed app, helper or AWDL setting was changed.

**Left off at:** GitHub release v4.4.2 and both update feeds are published. The maintained finalizer verified receiving downloads and both feeds, then confirmed the completed Ping Warden 4.4.2 release in Linear. The closeout commit records the regenerated website and feeds.

**Still open:** #145, #153 and #158 retain their production follow-up; better diagnostics do not establish that the underlying helper failures are resolved. The unlicensed-dashboard decision in #148 and the prior hardware, older-system and live-game acceptance items remain outside this release verification.

---

## 2026-10-28 - Sentry helper diagnostics follow-up

The seven-day Sentry review found 17 production events, all from 4.4.0 before today's 4.4.1 release. [#158](https://github.com/oliverames/ping-warden/issues/158) now tracks the declined enable separately from the unanswered enables in #145. Declined enables use the same version-gated helper reason/errno query as declined disables, with an unknown fallback and one event. An invalid connection no longer drops a disable failure when validation tears the connection down first (#153); superseded and compensating commands stay excluded. The README privacy disclosure and generated overview cover both command directions.

Verification: new regression cases failed against the old production monitor, showing the missing reason and dropped disable event. The production-monitor harness passes with zero failures, all 32 diagnostic-reporting tests pass, the crash-reporter harness passes 108 checks, and site checks pass. Protected native CI and independent review remain the merge gate. These are source diagnostics for a future release. Published 4.4.1 is unchanged, and the underlying helper failures remain open.

## 2026-10-28 - Ping Warden 4.4.1 released

Published [4.4.1](https://github.com/oliverames/ping-warden/releases/tag/v4.4.1), build 44100, from `0acfef5ccd51f30b9d1a2477065b8a87e6246c57`. The release ships the About/license-window layout crash fix, Dashboard/setup layout improvements, and helper failure diagnostics already merged since 4.4.0. The notes and generated release page now cover those changes.

Verification: 347 local core tests pass, and the full native build, helper harnesses, and Swift/Objective-C CodeQL passed on the integrated app source. The canonical release script built a fresh universal archive, signed it with the existing `PV3W52NDZ3` identity, and verified the mounted DMG, Gatekeeper, and Apple's accepted/stapled notarization. Both live Sparkle feeds and the GitHub asset matched local delivery checks. Sentry received the symbols/release, Gumroad verified the current buyer download while preserving license-key content, and Linear confirmed release completion. The underlying window-layout crash was not reproduced during this session.

The DMG SHA-256 is `01d87bad5aba66e55c6f5fb2c74362667ea78710cca93a0eef8fb4e4643ac6a0` (6,349,423 bytes). The Homebrew tap is updated at `e90033fc1cce2cfd1a4abcc0ee7ef9ee8538c8bb`, and the in-repository cask matches it. The required Gumroad CLI was restored through the existing `antiwork/cli/gumroad` Homebrew formula.

Post-release CI separates feed validation from native source checks. Feed-only updates retain XML and Sparkle-signature verification, while app, test, script, and workflow changes retain native verification. The receiving checks on the bookkeeping pull request remain the final integration gate. Existing unresolved helper-behavior and customer-acceptance follow-ups below keep their recorded status.

## 2026-10-28 - Complete branch integration and scope CI

The integration branch combines the reviewed CodeQL action update (#139), Wrangler update (#152), and worklog compaction (#155), preserving their commits. Build and CodeQL jobs now select native, site, and shell checks from the changed paths while retaining the required check names. Scheduled analysis still runs every surface, and changes to the workflows or classifier run every check.

Verification: classifier checks cover documentation-only, site, native Swift source, workflow, and classifier changes. The full receiving CI run remains the integration gate. Historical platform branches and unfinished experiments stay preserved.

Compacted October 28, 2026. The [complete pre-compaction worklog](WORKLOG-2026-10-28.md) preserves every entry and historical anchor byte for byte, beside this file so relative links keep their original base. The retained entries below keep their recorded dates and verification limits. This documentation pass adds no release, installation or runtime acceptance.

## 2026-10-27 - 4.4.1: window layout crash and turn-off decline reason

**What changed:** Two fixes from the daily Sentry check, for [#144](https://github.com/oliverames/ping-warden/issues/144) (PING-WARDEN-D) and [#153](https://github.com/oliverames/ping-warden/issues/153) (PING-WARDEN-C), plus the version bump to 4.4.1 (build 44100). D was a fatal `NSGenericException` raised from `_changeWindowFrameFromConstraintsIfNecessary`, where a window took its frame from its hosting view's constraints and the new frame invalidated the hosting view's safe area again. About and the license transition notice were the only windows still using the default `.standardBounds`, so both now set `sizingOptions = []` and own their size, as Settings has since 2.4.3. About is also built with its style mask instead of gaining `.fullSizeContentView` after creation. For C, the helper records why `setAwdlEnabled:` returned NO (`PingWardenCommandFailure`: shutting down, monitor stopped, read failed, write failed, confirm read failed, not confirmed) with the errno of a failed ioctl, and answers a new `getLastCommandFailure` XPC request. A declined turn-off asks the helper's version first and asks for the reason only from 4.4.1 or later, so an older running helper never gets a selector it doesn't know. The event waits up to 2 seconds for the reason and goes out once.

**Disclosure:** Events add a `decline_reason` tag and, for a failed ioctl, the errno as an `NSPOSIXErrorDomain` code. A reason without an errno keeps the existing fingerprint, so those events stay in PING-WARDEN-C. New `app.window` breadcrumbs record which window opened (setup, settings, about, license notice). README's "What crash reporting sends" and the CrashReporter header comment cover both, the site pages were rebuilt, and the overview's date moved to 2026-10-27.

**Verification:** Written in a Linux cloud session without a Mac, so nothing here was built or run locally. CI runs the helper tests (plain, TSan, ASan), the monitor and coordinator harnesses, the crash reporter tests, `swift test`, and the Release build. The crash itself was not reproduced, so the D fix rests on the stack trace matching the only two windows sized from constraints.

**Still open:** The release (`release.sh 4.4.1`) needs Oliver's Mac for signing, notarization, and the appcast. Once it ships, PING-WARDEN-C and -D get resolved in the next release. Whether a failed turn-off should stop blocking is still Oliver's call on #153; this change only reports why it happens.

---

## 2026-10-23 - Security and dead-code review

**What changed:** Removed `OnboardingModel.enterLicenseTapped()`, which nothing has called since it arrived in #125.

**Reviewed, no change needed:** The helper admits XPC peers through the listener's `connectionCodeSigningRequirement` (team ID plus the app and widget identifiers), refuses to serve when its own signature fails, and confines callers to root or the console user. It changes awdl0 with a fixed-name ioctl, and the app's `Process` calls (`route`, `ifconfig`, `launchctl`) use fixed argument arrays. Sparkle requires a signed feed with `SUVerifyUpdateBeforeExtraction`. The license key lives in the Keychain. The site has 0 npm advisories, and its worker only redirects production hosts to the canonical HTTPS origin. Gitleaks found nothing in history. The repository's default workflow token is read-only, so the workflows without a `permissions` block get no write access.

**Verification:** The unsigned Release app built with `xcodebuild build -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`.

---

## 2026-10-23 - Visual consistency pass across every window

**What changed:** Reviewed every window state and fixed the layout bugs and inconsistencies it turned up ([#147](https://github.com/oliverames/ping-warden/pull/147)). The setup window keeps one 528-point height from Protection through Done, so the footer buttons stay put, and the current approval card's accent outline draws now. The dashboard uses one status palette, draws its chart as soon as samples exist, keeps the Network Quality card's height when a probe fails, and shows Ping Protection side by side at the default window size. Settings buttons are one size across panes, and busy buttons keep their width. The latest-value chart label never rendered, so it's gone.

**Verification:** I captured every Settings pane, the dashboard, all 17 setup previews, About, the transition notice, and the diagnostics sheet from an isolated Debug build of the 92 Test fixture, in light and dark, at the default, tall, and 760 by 520 sizes, and in the paid, unlicensed, and transition license states. Six review agents measured the code and the captures, and a seventh compared before and after captures for regressions. `scripts/test_presentation.py` passed all 37 checks. The status menu and the Control Center control weren't captured, and nothing was checked on macOS versions before 26.

**Decisions made:** Oliver declined computer-use control of the fixture, so a scratch-only patch adds a Debug capture tour that shows each window without taking focus, and the shell captures them by window ID. The method is in memory as the capture-tour reference. Liquid Glass stays on the dashboard cards (7424c6f). The Network Quality hero stays colored by the smoothed median quality. CI triggers aren't path-scoped, because main's ruleset requires `build`, `linux-core-tests`, `shell-lint`, and CodeQL on every PR.

**Still open:** In the unlicensed state the dashboard shows both "Unlock Ping Protection" and "Finish Setup…", and which one leads is Oliver's call ([#148](https://github.com/oliverames/ping-warden/issues/148)). The status menu and the Control Center control weren't captured, and nothing was checked on macOS versions before 26.

**Left off at:** #147 merged as `891d443` after all six checks passed. The verification pass caught a taller Fastest Target row and a dropped time label at the chart's trailing edge, and both are fixed in the follow-up commit.

**Open questions:** Whether the unlicensed dashboard should drop one of its two calls to action (#148).

---

## 2026-10-23 - Enable-timeout telemetry for #145

**What changed:** Two telemetry changes for the launch-time enable timeouts in [#145](https://github.com/oliverames/ping-warden/issues/145) (Sentry PING-WARDEN-A). First, an enable that an invalid connection ends is now reported. The validation request's error tore the connection down and bumped the operation token before the enable's own error ran, so the enable looked superseded and sent nothing, which hid the missing-launchd-job state from Sentry. `handleXPCInvalidation` now records which operation a drop ended, and the enable reports its XPC error when nothing newer superseded it. Second, a timed-out enable's event waits for a late reply: up to 25 seconds after the 5-second deadline (30 seconds after the command was sent). It goes out with a `late_reply` tag of `under_10s`, `10_to_20s`, `over_20s`, or `none`. The fingerprint is unchanged, so these events stay in PING-WARDEN-A. A quit during the wait flushes the event synchronously in `applicationWillTerminate`, without the tag. The enable and disable deadlines now share `protectionCommandTimeout` (still 5 seconds) so the harness can shorten it.

**Disclosure:** README's "What crash reporting sends" now lists the failure reason, which was already sent but undisclosed, and the late-reply range. The CrashReporter header comment matches. Site pages were rebuilt, and the overview's date was bumped to 2026-10-23.

**Verification:** The new invalid-connection harness check failed on unchanged code (no event) and passes with the fix. A mutation that disabled both changes failed all six new monitor checks. The monitor harness, coordinator harness (222 checks), crash-reporter tests (104 and 108 checks), `swift test --filter DiagnosticReportingTests` (29 tests), and the site build and check all passed. The Release app build status is recorded in the PR. Not verified: a real invalid connection or late reply on a signed build, and SentrySDK storing the flushed event before exit, which relies on the SDK writing its envelope during `capture`.

**Review:** Codex found that the grace started when the timeout handler ran, so a stalled main thread could stretch the wait past 30 seconds. The wait is now fixed from the send (ae952bd), with a harness check that stalls the main thread. Its second finding, reserving the rate-limit slot for a held timeout, was declined: a held event only loses the slot to a newer failure that carries at least as much information.

**Decisions made:** Oliver approved the disclosure wording on 2026-10-23 and asked to merge once CI passes.

**Left off at:** #145 stays open until a release with this telemetry produces events. The disable path has the same gap, where a dropped connection's failure goes unreported. It's left alone because PING-WARDEN-B's events are timeouts, not drops. A coordinator-harness run under a load average of about 470 failed four timing-sensitive checks (B1, B14, and two #107 checks), and they passed on rerun at both commits.

## 2026-10-20 - Gumroad reviews on the home page, and discoverability follow-ups

**What changed:** Added the written Gumroad reviews to the home page testimonials, quoted verbatim with the existing "Verified buyer" attribution ([#141](https://github.com/oliverames/ping-warden/pull/141), commits `f42b576` and `2a6581d`). The page now shows six Gumroad reviews and the two Reddit comments that were already there. Drafted replies to the two unanswered Gumroad reviews and to the new one. They are drafts only and were not posted. Opened [#140](https://github.com/oliverames/ping-warden/issues/140): the Protection-on panel in the off-vs-on image shows an 83 ms spike, and the image is labeled 4.3.2 while the current release is 4.4.0. Opened [#142](https://github.com/oliverames/ping-warden/issues/142) for search and discoverability work beyond per-page metadata, and [#143](https://github.com/oliverames/ping-warden/issues/143) for the Reddit comments that are still pending.

**Verification:** `npm run build` built 12 pages, and `npm run check` passed (Python checks, then 7 worker tests) for both commits. The live site was not checked after deploy. The Gumroad page showed six ratings and five written reviews at the first read, and a sixth written review arrived later.

**Decisions made:** Reddit reviews are deferred because the Chrome browser tool blocks reddit.com. Anonymous Gumroad reviewers are not named in replies. Oliver asked for auto-merge on #141 once its checks pass, and it is enabled with squash. Direct pushes to `main` are rejected by repository rules, so changes to main go through a pull request.

**Resolved this session:** The Gumroad review gap. Every written Gumroad review is now on the home page.

**Still open:** #140, #142, and #143. #129's 30-day click-through re-check is due around 2026-11-13, and #106's Search Console performance data was still processing at the last check.

**Left off at:** PR #141 is open with auto-merge enabled. At the last read, `Analyze Swift and Objective-C` and `build` were pending, and the website, shell-lint, and linux-core-tests checks had passed. Delete the `website-gumroad-reviews` branch after the merge.

**Open questions:** Whether to post the three Gumroad replies as drafted. Which Reddit comments count as reviews, and whether the intro "Selected public reviews and comments from Mac gamers" should change. Both are in #143.

---

## 2026-10-17 - Setup page search title and description

**What changed:** Retuned the `/docs/setup` title and description for search ([#135](https://github.com/oliverames/ping-warden/pull/135), `73ce4fe`), then dropped the repeated brand from the title because the build appends " | Ping Warden" (this PR). The live title is "Setup for Mac: Install, Approve, Verify | Ping Warden". The geforce page was retuned earlier in `5274efe`.

**Verification:** `npm run build` and `Site/check.py` passed; the Website workflow deployed #135 and the live page served the new metadata.

**Left off at:** [#129](https://github.com/oliverames/ping-warden/issues/129) stays open for the 30-day click-through re-check around 2026-11-13. Baselines: `/docs/setup` 96 impressions and 0 clicks, `/docs/geforce-now-mac-stutter` 248 impressions and 2 clicks.

**Open questions:** None.

---

## 2026-10-14 - Ping Warden 4.4.0 released (stable)

**What changed:** Published [4.4.0](https://github.com/oliverames/ping-warden/releases/tag/v4.4.0) (build 44000) to the stable and beta feeds from main `7623b97` ([#125](https://github.com/oliverames/ping-warden/pull/125)). Oliver renamed the planned 4.3.4 to 4.4. It contains:
- Guided setup and Repair ([#124](https://github.com/oliverames/ping-warden/issues/124), verified by Oliver on 4.4.0-beta.1).
- License activation turns protection on; a silent helper after activation runs Repair; Repair is offered once per failure episode when the helper stops working while protection is needed.
- Control Center refresh after a crash, helper recovery, Repair and wake ([#130](https://github.com/oliverames/ping-warden/pull/130), closes [#101](https://github.com/oliverames/ping-warden/issues/101)).
- Full Sentry integration ([#131](https://github.com/oliverames/ping-warden/pull/131), [#133](https://github.com/oliverames/ping-warden/pull/133), closes [#100](https://github.com/oliverames/ping-warden/issues/100)): allowlist events, helper error events (one per problem per 30 minutes, persisted), one session per run, registers stripped, build-time release channel.
- [#132](https://github.com/oliverames/ping-warden/pull/132): a busy DMG detach that finishes late now counts as detached.

Betas shipped earlier the same day: 4.3.4-beta.2 (43392) and 4.4.0-beta.1 (43901). Homebrew tap bumped to 4.4.0 (`507d573`); the in-repo cask copy now matches it.

**Decisions made:**
- Build numbers: stable 4.4.0 is 44000; betas for a release sit just below it.
- Crash reporting stays on by default (unchanged since 4.3.3); a saved opt-out is respected. Turning it off sends one session-end record, which the disclosure now states because sentry-cocoa 9.26.0 has no supported way to drop it.
- Sentry project `scrubIPAddresses` is on (read-only check).

**Verification:** release.sh completed: notarized and stapled app and DMG, both appcasts signed and verified, GitHub release, Sentry release `com.amesvt.pingwarden@4.4.0+44000`, Gumroad deliverable, Linear confirmed. Live stable feed leads with 44000 then 43300; beta leads with 44000 then 43901.

**Left off at:** Not yet confirmed at runtime: a live Sentry test event, session-end record on opt-out, and register stripping. Known gaps: widget toggle failures and helper-side AWDL enforcement failures are not reported to the app. Release tooling lesson: release.sh archives by itself; never stage an app inside `PingWarden/PingWarden/build`.

**Open questions:** None.

---

## 2026-10-13 - 4.3.4-beta.1, feed incident, release guard, cleanup

**What changed:** Published [4.3.4-beta.1](https://github.com/oliverames/ping-warden/releases/tag/v4.3.4-beta.1) (build 43391, pre-release) on the beta channel from `42de8f0` on `onboarding-4.4` (draft [#125](https://github.com/oliverames/ping-warden/pull/125), issue [#124](https://github.com/oliverames/ping-warden/issues/124)). It adds the guided setup and Repair flow:
- The Welcome window is unchanged from 4.3.2.
- Helper approval appears only after a license is active.
- Screens are balanced and their System Settings copy changes by macOS version.
- Repair checks the helper before handing off to the approval step.

[#126](https://github.com/oliverames/ping-warden/pull/126) recorded the 4.3.3 feeds on main. [#127](https://github.com/oliverames/ping-warden/pull/127) (`c47e9d1`) makes `release.sh` abort when its local feeds lack an item already published on gh-pages, both in pre-flight and again before Step 8. Every merged or superseded branch and worktree is pruned. Oliver deleted the paused migration branch and worktree himself.

**Decisions made:**
- Beta build numbers sit between stable builds. 43391 is above 4.3.3's 43300 and below a future stable 4.3.4's 43400, so beta users still receive the stable release.
- The in-app setup copy attempt was reverted, and the guided flow replaces it.

**Incident (resolved):** `BETA_CHANNEL=1 release.sh` ran from a branch whose `appcast.xml` predated the 4.3.3 entry, so the published stable feed dropped 4.3.3. That stable feed was live from about 20:51 to 20:53 UTC. gh-pages `f59a005` restored it:
- Stable leads with 4.3.3.
- Beta leads with 4.3.4-beta.1, then 4.3.3.
- Both feeds re-signed and verified against the app key, and every enclosure signature is unchanged.

The Linear report was retried and confirmed for both releases.

**Verification:**
- Beta DMG: its SHA-256 matches GitHub's digest, it is Notarized Developer ID, its staple validated, and it holds 4.3.4 build 43391.
- 279 Core tests passed.
- `test_release_tools.py`: 37 tests passed, including 5 guard tests under Bash 3.2.
- All six CI checks were green on #127.

**Left off at:** The live macOS approval path in the beta has not been run, because it needs Oliver to click Allow. After the beta soaks, merge #125 and release stable 4.3.4 (build 43400). Outreach drafts are in `docs/2026-10-13-outreach-drafts.md`. Still open: #93, #94, #96, #100, #101, #105, #106, #124.

## 2026-10-07 - Preserve paused migration outside main

**What changed:** At Oliver's request, preserved source at `d57bb12` on `migration/paused-developer-account` in `/Users/oliverames/Developer/Projects/ping-warden-migration-paused`. The branch is pushed and its worktree is locked against accidental cleanup. Reverted the changes from the nine preparation commits, `f83e625` through `78b665b`, from `main` without rewriting history. The later README refresh and release-reporting changes remain. README now points to the preserved branch.

**Verification:** The reverted source matches the pre-preparation baseline `fc618424` with the later unrelated commits applied. All 42 offline release-tool and release-reporting checks passed. Bash syntax and ShellCheck error checks passed for `release.sh`. Project settings, both appcasts and release notes are unchanged. No app suite, build, app launch, signing, account change or publication ran.

**Pause:** Migration implementation and customer handoff remain incomplete and paused. Oliver's explicit authorization is required before resuming migration implementation, signing changes (including identities, entitlements and provisioning), account changes, packaging, merges of migration work, or migration releases. Keep `migration/paused-developer-account` and `/Users/oliverames/Developer/Projects/ping-warden-migration-paused`. Revert `273e26c` removes the preparation from current `main` source; the old preparation commits remain in Git history. Resumption must deliberately restore the required changes after reviewing the revert, rather than automatically merging the preserved branch. PR #110 is website documentation maintenance and does not resume migration work. Tracking remains [#109](https://github.com/oliverames/ping-warden/issues/109) / [AME-90](https://linear.app/ames-consulting/issue/AME-90/verify-4x-continuity-before-signing-migration).

## Open items

- Deliver the new unlicensed-dashboard purchase/activation card in a subsequent release, tracked in [#104](https://github.com/oliverames/ping-warden/issues/104). The published 4.3.0 artifact remains unchanged.

- Remaining older-OS verification and gallery assets for Control Center Only mode; current-host launch paths, Dock restore, Settings access and toggle state passed: [#96](https://github.com/oliverames/ping-warden/issues/96) (since 2026-09-25)
- Control Center screenshots for the homepage and README, tracked in [#96](https://github.com/oliverames/ping-warden/issues/96) (since 2026-09-25)
- Product Hunt waits for new gallery images and a website redesign, with several alternative designs for Oliver to choose from. Not scheduled. No draft or launch exists (since 2026-09-24; [#93](https://github.com/oliverames/ping-warden/issues/93))
- Decide how to run CI locally instead of on GitHub-hosted runners, which have a usage limit (since 2026-09-24; [#94](https://github.com/oliverames/ping-warden/issues/94))
- Signed checks under [#78](https://github.com/oliverames/ping-warden/issues/78): Off, ordinary quit restore, and responsive-helper Repair while on passed in the approved isolated licensed fixture on 2026-09-28. Forced awdl0 re-raise also passed during 4.3.0 verification. VoiceOver, remaining appearance and live-game checks remain. The 4.2.0 to 4.2.1 update checks passed earlier that day (since 2026-09-14).
- Live-game validation of the frontmost-app engage and disengage handoff and the Ethernet skip. Needs an eligible real-game session and wired hardware; only Wi-Fi was available on 2026-09-21 (since 2026-09-06; [#64](https://github.com/oliverames/ping-warden/issues/64))
- Crash-state Control Center display remains under [#101](https://github.com/oliverames/ping-warden/issues/101). The sandbox and quiet-launch fix shipped in 4.3.0 and #92 is closed. Physical macOS 26 acceptance remains under #96.
- Exercise the session recorder with the Dashboard open during a Game Mode session to confirm the recap stays on the session's target (since 2026-09-14) (unverified)
- Confirm the four inferred `transientSystemUIBundleIdentifiers` entries beyond `UserNotificationCenter`; a SecurityAgent password sheet over a game would confirm the most likely one (since 2026-09-12)
- Re-run `python3 scripts/download_stats.py --snapshot` to measure 4.x acceptance after the upgrade-notice rewrite and announcements. The latest snapshot in `docs/download-history.tsv` is 2026-09-14 (since 2026-09-11)
- Keep carrying the "New since 4.0" section in release notes while 4.0.x installs remain (since 2026-09-12)
- Decide whether to create a personal Homebrew tap; the official cask is blocked by owner-submission notability thresholds (since 2026-09-14)
- Gumroad Discover eligibility and account-review outcome were not established (since 2026-09-14) (unverified)
- Optional outreach not rechecked: the Gumroad reply to Paul Nobert's review awaiting Submit, the rating-request drafts to Christophe Stenstrom and Michael Grimm awaiting Send, and the remaining Reddit modmail and post drafts (since 2026-09-14) (unverified)
- Physical or virtual macOS 13 runtime smoke test (since 2026-07-13) (unverified)
- Watch the GameController crash count per release (since 2026-06-22) (unverified)
- README mention of the beta channel, deferred until a 2.4.0 build shipped; the README currently does not mention it (since 2026-05-27) (unverified)
- Rotate the Sentry User Auth Token that transited chat history, and consider an Org Auth Token if CI/CD use begins (since 2026-05-18) (unverified)
- Helper-daemon crash reporting, deferred until main-app crashes reveal cross-process incidents the XPC logs miss (since 2026-05-18)
- Customer report (2026-09-27, Intel MacBook Pro 2017, macOS 13.7.8): helper registered and allowed but never answers XPC (health check timeout), Welcome skipped. Oliver sent the reply asking for `launchctl print system/com.amesvt.pingwarden.helper` output and a clean reinstall on 2026-09-27. The readout confirmed the missing job. The 4.3.0 release/retest reply was sent and verified on 2026-09-28; awaiting customer retest
- First-attempt missing-helper Repair on macOS 27.2 remains under [#99](https://github.com/oliverames/ping-warden/issues/99). The release is published with this limitation disclosed.
- Bounded recovery for a temporarily busy validation volume remains under [#103](https://github.com/oliverames/ping-warden/issues/103). The completed release required an ordinary eject and full canonical rerun before any publication.
- Sentry: decide on a one-time delivery test against a separate project, on `enableUncaughtNSExceptionReporting`, and on helper-timeout events (a disclosure change). Server side checked clean on 2026-09-27; the last accepted error event was 2026-08-06 (since 2026-09-27; [#100](https://github.com/oliverames/ping-warden/issues/100))
