# Ping Warden Worklog

## 2026-10-07 - Preserve paused migration outside main

**What changed:** At Oliver's request, preserved source at `d57bb12` on `migration/paused-developer-account` in `/Users/oliverames/Developer/Projects/ping-warden-migration-paused`. The branch is pushed and its worktree is locked against accidental cleanup. Reverted the changes from the nine preparation commits, `f83e625` through `78b665b`, from `main` without rewriting history. The later README refresh and release-reporting changes remain. README now points to the preserved branch.

**Verification:** The reverted source matches the pre-preparation baseline `fc618424` with the later unrelated commits applied. All 42 offline release-tool and release-reporting checks passed. Bash syntax and ShellCheck error checks passed for `release.sh`. Project settings, both appcasts and release notes are unchanged. No app suite, build, app launch, signing, account change or publication ran.

**Pause:** Migration implementation and customer handoff remain incomplete. Further implementation, packaging, account changes, merges and releases require Oliver to explicitly resume the migration. Keep the preserved branch and worktree. The old preparation commits remain in Git history; resumption must deliberately restore the required changes after reviewing this revert, rather than automatically merging the preserved branch. Tracking remains [#109](https://github.com/oliverames/ping-warden/issues/109) / [AME-90](https://linear.app/ames-consulting/issue/AME-90/verify-4x-continuity-before-signing-migration).

## 2026-10-07 - GitHub Issue Review Closeout

**What changed**: Reviewed all 10 open issues against source at `111fb34686e4` and their complete issue history. No issue qualified for closure.

**Decisions made**: Close completed implementations even when device acceptance remains, and close testing-only tasks under Oliver's explicit instruction. Keep unresolved defects, missing implementation, release work, and owner decisions open.

**Left off at**: Resolved this session: issue assignment and state reconciliation. GitHub was independently re-read on October 7, 2026 at 10:20 AM EDT. All 43 repository issues include Oliver as an assignee, with 10 open. Source paths and cited lines were checked. No runtime tests, deployment, or application changes were performed. This is one part of the account-wide review.

**Open questions**: Still open: [#93](https://github.com/oliverames/ping-warden/issues/93), [#94](https://github.com/oliverames/ping-warden/issues/94), [#96](https://github.com/oliverames/ping-warden/issues/96), [#100](https://github.com/oliverames/ping-warden/issues/100), [#101](https://github.com/oliverames/ping-warden/issues/101), [#103](https://github.com/oliverames/ping-warden/issues/103), [#105](https://github.com/oliverames/ping-warden/issues/105), [#106](https://github.com/oliverames/ping-warden/issues/106), [#107](https://github.com/oliverames/ping-warden/issues/107), [#109](https://github.com/oliverames/ping-warden/issues/109). Other previously recorded operational follow-ups retain their dated status. No new issue was needed for this review.

---

## 2026-10-07 - README Refresh Closeout

**What changed**: Clarifies measured interventions, licensing, privacy, and dormant migration preparation.

**Decisions made**: Keep setup and status claims tied to current source or explicitly dated evidence. This entry records the multi-repository README maintenance session.

**Left off at**: Resolved this session: README review and publication at `111fb34`. Relative links, examples and applicable counts were checked. Verification covered documentation. No fresh runtime acceptance is claimed.

**Open questions**: No new question from the README refresh. Dormant migration work and the earlier setup-investigation evidence remain separate from this README refresh. No helper, licensing or network setting changed.

---

## 2026-09-29 - 4.3.1 released

**What changed:** 4.3.1 (43100) was published from c730502 via `release.sh`. It contains the #99 setup and Repair fix, #104's license offer, and the Control Center settings in General. At Oliver's request, the release notes now list only each version's changes. The 4.3.1 notes dropped "New since 4.0" and the licensing paragraph, and `update_appcast.py` no longer injects the "Upgrading from Ping Warden 3 or earlier?" paid notice. The normalizer strips that notice from every existing feed item, and the `minimumAutoupdateVersion` 40000 boundary is kept (b763161, gh-pages a4b94db). The GitHub release body was re-rendered to match.

**Verification:** The downloaded GitHub DMG matches the local artifact and GitHub's SHA-256 (`ae592fcd…`). Gatekeeper reports notarized Developer ID, and the staple validates. The mounted app is 4.3.1 (43100), universal, and contains the retry. Stable, beta and raw-main feeds offer 4.3.1 and verify against the app key, before and after the notes edit. Every enclosure signature was unchanged by the feed edit. Sentry release `com.amesvt.pingwarden@4.3.1+43100` published, and the Gumroad buyer download was verified by release.sh. #99 and #104 are closed.

**Left off at:** Felix's follow-up is a Gmail draft asking him to test 4.3.1 and consider a Gumroad review or an r/GeForceNOW post. Oliver switches From to oliver@ames.consulting and sends it. Resolved this session: the project-release-runbooks runbook now states the changes-only notes rule (ames-plugins-local e8316fd, ames-dev-workflows-local 2.2.2). NEW: #107 tracks the misleading "rejected the connection (XPC error 4099)" log text for a missing launchd job, and whether the menu should offer Repair for a silent helper. Still open: Ventura and Intel confirmation of 4.3.1 via Felix, and the existing manual-testing issues #64, #78 and #96.

## 2026-09-29 - Live setup acceptance and 4.3.1 preparation (#99)

**What changed:** A signed `Ping Warden 92 Test` fixture on this Mac (macOS 27.2) reproduced #99. After `launchctl bootout` of an approved helper, Repair unregistered and re-registered about 30 ms later. `register()` threw SMAppService code 1 with the status Not Registered, while BTM still listed the old item as allowed. No notification appeared, and a second Repair succeeded. 6dd011a retries a refused registration every 2 s, up to three times. With it, the first Repair click recovered the helper in 3 s with no prompt. Fresh setup with notification approval also passed on the first attempt. Version 4.3.1 (43100) ships everything on main: the setup fix, #104's license offer, and Control Center settings in General. README, QUICKSTART and TROUBLESHOOTING now say General and note the 4.3.0 location.

**Verification:** The release delta since v4.3.0 touches no license, seal, preference-storage, entitlement, helper, or Keychain file, and adds or removes no defaults key. Before commit, all local suites passed: site check, 245 Core, monitor, 111 coordinator, 204 helper checks in each sanitizer mode, 38 crash-reporter checks, and release tools. Fixture cleanup left no fixture data. Production executables and App Group preferences match the pre-test hashes, and AWDL is up. Full results are on #99.

**Left off at:** Run `release.sh 4.3.1`, commit the signed appcast, and verify the published artifacts. Then draft Felix's follow-up asking him to test 4.3.1 and consider a Gumroad review or a r/GeForceNOW post.

## 2026-09-29 - Helper approval setup fix (#99), unreleased

**What changed:** 7d393be makes first-time setup wait for approval instead of failing. The SMAppService or POSIX Operation not permitted error (code 1) counts as pending approval again, and Not Registered must persist for 10 s before polling fails. After a fresh registration, Login Items opens only if approval is still pending after 10 s, so it no longer competes with macOS's notification. A fresh helper gets five reply attempts, and setup logs at notice level.

**Verification:** Universal unsigned Release build succeeded. Monitor checks passed, including nine new ones, and a mutation run that disabled the fixes produced 9 failures. 245 Core tests, 111 coordinator checks and 204 helper checks in each of the three sanitizer modes passed. The first attempt failed to build: the `SMAppServiceErrorDomain` constant requires macOS 15, so the fix matches the domain string.

**Left off at:** No release, version bump, or release-notes change. The 4.3.0 "Repair can fail on its first attempt" note remains until a release ships this fix. The fix still needs a Ventura or Intel acceptance run. The customer log is pending.

## 2026-09-29 - #99 comparative investigation: likely 4.3.0 regression

**Finding:** Commit 0de3f50 (Sept 28) removed the long-standing fallback that treated a permission-type `register()` error as pending approval. 4.3.0 now waits only if status reads exactly `.requiresApproval` right after the throw, and otherwise shows "could not register its helper. Try again." Apple DTS reports show SMAppService Code 1 "Operation not permitted" is the normal pending-approval result. The credited upstream (AWDLControl) ignores that error, never treats `NotRegistered` as terminal while polling, opens Login Items only on a second click, and allows 10 s for the first check-in. Ventura 13.1 to 13.3 had SMAppService daemon registration and notification bugs per Apple release notes.

**Verification:** Git history read from tags v2.0.0 to v4.3.0. I confirmed the removed fallback myself in `git show v4.2.1` and `git show 0de3f50`. Upstream repos cloned read-only to the session scratchpad. Web findings are cited on #99. No code changed, and nothing ran on Ventura or Intel.

**Left off at:** Six ranked fixes are on #99, awaiting Oliver's decision. The customer's log export is still pending.

## 2026-09-29 - Customer setup report investigated under #99

**What changed:** A customer on a 2017 Intel MacBook Pro (Ventura) confirmed 4.3.0 works after a clean install, but first-time setup took three Finish Setup attempts and two password prompts. Apple's ServiceManagement docs show `requiresApproval` also means revoked consent and that daemon approval needs an admin password, so the notification's Allow plus a later switch flip reads as approve, then revoke. The docs also allow a transient `notRegistered` during re-registration, which the registration poll treats as terminal. This host's Sept 28 fixture logs hold no app-level record of the first-attempt Repair failure: the setup narration is info-level and never persisted, so only `SMAppService` status reads and launchd/BTM lines survive. Findings and four ranked recommendations are on #99.

**Verification:** Local `log show` over Sept 28 covered the production app, the `Ping Warden 92 Test` fixture and backgroundtaskmanagementd. No code changed. The customer reply is a Gmail draft in the thread asking for `sw_vers` plus a two-day log export with launchd and BTM lines, to be sent from oliver@ames.consulting.

**Left off at:** Waiting on the customer log to name the failing branch. Decide whether the next release promotes setup logging to notice level, adds a grace period before `notRegistered` ends the poll, extends the post-approval reply check, and tells people not to re-toggle the Login Items switch.

## 2026-09-28 - Product Hunt scheduled, MacMenuBar submitted, NVIDIA approval requested

**What changed:** Product Hunt launch is scheduled for Sep 29 2026 at 12:01 AM PDT (3:01 AM EDT). Live listing copy now differs from the 09-24 prepared docs: tagline "Less Wi-Fi stutter in GeForce NOW and Mac cloud gaming", a 462-character description that leads with the symptom, topics Mac, Open Source and Menu Bar Apps, and four captioned gallery images (hero with menu bar, dashboard chart cropped to exclude a test latency-session card, menu bar states, Game Mode). The MacMenuBar form was filled with three real menu bar captures and submitted (its thanks page appeared). The required reviewer promo field holds a note offering a free license on request, not a code. A direct message asking permission for one General Chat introduction was sent to a listed NVIDIA admin, as the NVIDIA code of conduct requires prior approval for advertising.

**Verification:** Menu captures were taken on a neutral temporary backdrop, cropped to the menu bar and popover. The production app was restored afterward: Not Protected, live metrics off, AWDL up, app not running as originally found. No repository files or app settings changed. The Product Hunt listing was checked in the editor and the product page shows the scheduled banner. Live rendering of the new gallery was not re-checked on launch day.

**Left off at:** The maker first comment (text in the private prepared JSON) posts after launch. A session-only job was set for about 3:04 AM EDT. It only runs if the session stays open, so post manually if it did not. Awaiting the NVIDIA reply and any MacMenuBar confirmation email. Search Console sitemap still reports "Couldn't fetch" (#106).

**Open questions:** Whether to record a short demo video before or after launch. Whether to create a reviewer license code for MacMenuBar if asked. Tracking stays in #93, #105 and #106.

---

## 2026-09-28 - Search Console ownership verification

Oliver authorized adding pingwarden.app to his chosen Google account. Added the supplied HTML ownership tag to the homepage source and generated site. The tag is public verification metadata. DNS, analytics, crawl policy and app artifacts remain unchanged. Root owns the site and Git changes; agents own their named community submissions.

Deployment `ac6ed84` and Website run 36485855185 passed. Google verified ownership through the HTML tag. URL Inspection reports the homepage and all three priority guides as indexed. The homepage live test passed, and each guide has one valid Breadcrumbs item. The sitemap submission was accepted. Its initial report says it could not be read, while Google's live test of the exact sitemap at 21:34:39 UTC shows crawling allowed and a successful fetch. The public XML has 12 valid, distinct URLs. Leave the accepted submission in place for processing. No network or crawler settings changed.

Follow-up #106 retains the sitemap processing result and the first performance baseline. Search Console performance data is still processing, so no traffic or ranking improvement is claimed. The earlier account-choice question below is resolved. Community publication continues independently under #105 and #93.

---

## 2026-09-28 - Move interface controls to General for the next build

**What changed:** Moved the Control Center Only section, confirmation dialog, availability explanation and retained legacy menu-icon choice from Automation to General. General now refreshes availability when the app becomes active. Existing preference keys, protection behavior and icon policies remain intact. App-footer copy no longer directs people to Automation.

**Verification:** Native Xcode build of the production project succeeded with no reported errors. All 28 existing interface-policy tests and all 35 presentation checks passed, with no skipped tests. The first SwiftPM attempt was blocked by sandbox compiler-cache access, then passed with normal cache access. This is a next-build source change, not an installed or published update. The installed 4.3.0 stays unchanged. No new behavior tests were added for this relocation.

**Delivery:** Include this move with the pending license-card follow-up in the next release. Refresh the setup and troubleshooting instructions when that build is published; current live 4.3.0 documentation correctly points to Automation. Discovery submissions continue separately. Unlicensed-state tests continue to use isolated copies.

Commit `c195d90` is pushed. Its Build Verification run 36483975224 and CodeQL run 36483975226 both passed. The later ownership-tag commit's Build Verification also passed; its analysis was still running at this checkpoint.

---

## 2026-09-28 - Discovery review and sitemap freshness

**What changed**: Corrected the homepage, documentation hub and release-note sitemap dates to reflect the significant September 28 release edits. The public sitemap had still reported September 21. The site already exposes canonical URLs, static guide content, structured data and an open crawl policy. The source generator retains explicit dates so builds stay deterministic. Website verification passed all 13 HTML pages, all 12 sitemap URLs, links and structured JSON, plus both Worker tests with no skips.

**Decisions made**: Oliver authorized Chrome and Google Search Console work to improve SEO. Root owns site edits and Search Console interactions. The public marketplace listing already has symptom-focused copy and tags. No ranking or traffic improvement is established by these checks. Crawl policy, analytics preferences, pricing and app release artifacts remain unchanged.

**Left off at**: Sitemap correction `ee94954` is deployed. Website run 36476403697 passed both jobs and all 14 steps, and the public sitemap exactly matches the committed file. Search Console property/account setup is awaiting Oliver's account choice before verification, tracked in [#106](https://github.com/oliverames/ping-warden/issues/106). The private dated discovery review retains the observed account and evidence. Prior community outreach remains tracked in [#105](https://github.com/oliverames/ping-warden/issues/105); new directory and creator opportunities are recommendations only.

**Open questions**: Which account should own the Search Console property, and which discovery channels should receive a concrete submission? The earlier dashboard follow-up's Build Verification and CodeQL have now passed for both `01975fa` and `f9c6ac8`; delivery remains [#104](https://github.com/oliverames/ping-warden/issues/104). Other release/manual follow-ups below remain open.

---

## 2026-09-28 - Published 4.3.0 and unlicensed dashboard follow-up

Version 4.3.0 is published from `2b5d02e`; signed feed copies are committed as `26d6958`. Public GitHub and Gumroad downloads match the frozen notarized artifact. Stable, beta and legacy feeds retain all 35 historical entries and verify with the previous release's signing key. The website and release notes are live. Exact-source CI passed all seven jobs and 63 steps, including all 50 Swift source extractions. Oliver updated the production app himself. Its installed version, signature, notarization and retained session history are verified. Saved choices are unchanged apart from normal update/window/cache metadata. The isolated test helper and app have been removed.

The first missing-helper Repair attempt can still fail on the tested macOS 27.2 host. This is disclosed in the published notes and remains follow-up work under #99. Release-volume cleanup recovery is tracked in #103. Reddit moderator messages remain blocked by the service's generic send error. These do not hold the published release.

**Current scope and ownership:** Oliver requested replacing the confusing unavailable Latency Session controls with a license offer for users without protection access. Root owns all source edits, Git, UI and delivery. An independent reviewer checked entitlement, saved-history edge cases and the verification receipts. No other active chat owns this repository. This is a follow-up to the immutable published 4.3.0 artifact.

**Task list and resume point:**
- [x] Publish and independently verify 4.3.0, website, update continuity and customer delivery.
- [x] Verify Oliver's installed production update and remove the isolated test fixture.
- [x] Send the authorized post-publication customer reply and verify it in Sent.
- [x] Replace unlicensed session actions with a clear purchase/activation card while retaining saved history and eligible-user controls.
- [x] Verify the focused UI change and update release tracking and the dated private report. The follow-up is committed and pushed as `01975fa`; delivery remains #104.

**UI verification:** The native universal Release build passed with zero warnings/errors, and all 35 existing presentation checks passed. An inert native harness compiled the exact production views and exercised seven entitlement/history states, purchase and activation actions while busy, sharing previous recaps, and ending an active session after entitlement loss. Light and narrow dark layouts were inspected. Both new action labels omit ellipses at Oliver's request. No production app, helper, license or session data was changed by this UI review. The harness is closed. Shipping this follow-up remains tracked in #104; it is not part of the published 4.3.0 artifact.

**Wrap-up, September 28:** Resolved this session: 4.3.0 publication and receiving-host verification, the sandbox/quiet-launch issue #92, analysis coverage #102, test-fixture cleanup, and the post-publication customer reply. Build Verification for the subsequent UI commit `01975fa` passed all three jobs and 30 steps. At 19:20 UTC, [CodeQL run 36470324201](https://github.com/oliverames/ping-warden/actions/runs/36470324201) remained active in the native build stage, with no failed or skipped steps recorded. Do not transfer the published source's successful analysis result to this later commit.

**Still open:** Deliver the UI follow-up under [#104](https://github.com/oliverames/ping-warden/issues/104) after its remaining analysis and the next release's distribution checks. First-attempt Repair is [#99](https://github.com/oliverames/ping-warden/issues/99), and release-volume cleanup is [#103](https://github.com/oliverames/ping-warden/issues/103). Existing manual acceptance, crash-state display and Sentry decisions remain under #64, #78, #96, #100 and #101. **New tracking:** remaining community follow-up is [#105](https://github.com/oliverames/ping-warden/issues/105); draft completion does not establish message delivery. Private research and a continuation bundle retain the account-specific evidence. No new feature proposals were added to the release scope.

**Documentation and configuration:** The Control Center verification record and release issues now distinguish the initial fixture observations from final publication. Website/release notes and storefront copy were already delivered. No user configuration, marketplace skills or Notes content changed, so no configuration backup or Notes rewrite applies. Git preserves the project work. Memory remains unchanged. The separate CloudForce task reads the Site directory only and owns no Ping Warden edits.

## 2026-09-28 - Final quiet-launch correction and publication scope

The Control Center toggle and containing-app launch work in the licensed, signed test fixture. Its cold launch exposed a separate Settings presentation bug: NSWorkspace ignores launch arguments from a sandboxed caller. The widget now leaves a one-use App Group launch hint, and the app consumes it before choosing its launch presentation. Normal Finder reopening remains unrestricted. A failed request removes only its own hint, and abandoned hints expire after 60 seconds. A near-simultaneous independent cold launch can consume the hint, affecting initial window presentation only. No authorization or saved protection preference depends on it.

All 245 core tests pass, including expiry, invalid marker removal, one-use behavior and ownership cleanup. Website generation and checks pass. The universal Release fixture builds without warnings or errors. Signing/notarization and physical quiet-launch acceptance are pending. Root owns source, Git, installation and publication. Independent reviewers confirmed target membership and the bounded presentation behavior.

The extraction guard now resolves only its query's bundled dependencies. The exact corrected query accepts all 49 Swift files in the preceding CI database and correctly rejects the older widget-only database. The new shared launch source raises the final expected count to 50. The next exact-head workflow must verify all 50 and the unchanged required contexts.

Publication is authorized independently of community outreach. The first-attempt Repair limitation observed on this host is disclosed in the release notes and is not holding all verified fixes. Signing, update continuity and the remaining launch check still require verification. Publication, delivered-feed checks, production update, fixture cleanup and the post-publication customer reply remain pending under #99.

## 2026-09-28 - Current release resume point and analysis coverage

This entry supersedes the earlier resume points below. Version remains 4.3.0, build43000. PR #95 is merged. Dashboard Liquid Glass, explicit preference preservation, fresh crash-report defaults, same-path isolated upgrades, and the recorded performance comparisons are complete. Publication, final recovery acceptance, fixture cleanup, and the post-publication customer reply remain pending under #99. Production app and preference checksums remain unchanged.

The exact aafe1ea push workflows passed, but inspection found that native CodeQL extracted only the five widget Swift files and missed all 44 main-app files. The confirmed coverage defect is tracked in #102. The analysis-only build now disables explicit modules to address incompatible precompiled modules, and a new guard queries successful extraction for every app and widget Swift source. A successful result upload alone no longer satisfies this gate. The corrected run and query still require exact-head CI verification.

CodeQL does not support Objective-C, so the native job now combines Swift CodeQL with separate Xcode Clang analysis of the helper. It retains the required status-check name and leaves the repository ruleset unchanged. A result check requires every helper source in both architectures and rejects analyzer findings. Local native analysis processed both helper sources for arm64 and x86_64 with zero diagnostics. Existing helper behavior and sanitizer results remain separate evidence.

The coordinator owns repository edits, installed test apps, Git, and delivery. An independent agent reviews CI evidence. Changes in this commit affect the security-check workflow, its guard, and this log. They do not change release-build settings or the application. Private dated verification records retain live testing and community-outreach state. No experimental helper-lifecycle change is included in shipping source.

## 2026-09-28 - Integrated release readiness and Felix follow-up

**Request**: Commit and merge the pending Control Center work into main, clean up, and run full release gates with particular care for performance, functionality, and existing users. Verify crash reporting defaults on while preserving explicit opt-outs. Investigate the missing dashboard Liquid Glass appearance against Oliver's screenshot. Reply to Felix with thanks and a retest request only after the fix is live. Oliver authorized publication after passing gates, followed by Felix's reply. The previous publication hold is lifted for this release.

**Plan and ownership**: The coordinator owns all source edits, merges, builds, installed fixture operations, and delivery. Independent agents will review (1) upgrade and helper compatibility and (2) dashboard appearance/performance. No other active chat is working in ping-warden. The checkout began clean at e8d20b1 with no other worktrees. PR #95 is merged locally as 9952104. Candidate version is 4.3.0, build 43000.

**Shared task list**:
- [x] Review current PR #95, CI, open gates, Felix's thread, and release runbook.
- [x] Merge authorized Control Center work, preserving existing preferences and helper/upgrade compatibility.
- [ ] Diagnose and fix the dashboard appearance regression, then measure visible/hidden performance.
- [ ] Verify crash-report defaults and prior opt-outs, plus release delta and functional gates.
- [ ] Build and test the integrated signed candidate, including existing-install upgrade paths.
- [ ] Commit/push and clean up completed branches and fixtures without removing user state.
- [ ] If publication is authorized and gates pass, release and verify the delivered artifact/feed before replying to Felix.

**Current verification plan**: Build a signed v4.2.1 fixture and the 4.3.0 candidate with the same isolated identity. Preserve fixture license/transition state on relaunch. Test Downloads guidance, an absent launchd job with retained registration, same-path upgrade, legacy and new icon modes, and actual On/Off. Compare visible/hidden dashboard CPU and memory with a pre-glass fixture under matching workload. Coordinator owns UI and installation. Read-only agents own helper/crash/release suites and compatibility review. All fixture data stays separate from production.

**Current resume point (September 28, 11:25 AM)**: Publication and Felix's reply are still pending. The administrator-only recovery script awaits Oliver. The six-minute glass comparison and matched hidden run are complete in `/tmp/pingwarden-release-measurements`; no material app CPU regression was observed. The real Downloads check found that this Mac redirects Downloads into iCloud. First add a failing redirected-folder test, then canonicalize both sides of the protected-folder comparison. Commit that small correction separately, rebuild both signed fixtures, and recheck CI on the final source. The coordinator owns repository edits and live UI. A build agent may rebuild scratch fixtures, without installation or live preference changes.

**Live Downloads acceptance**: Signed `36e3663` launched from the actual iCloud-redirected Downloads path. Setup and Repair gave relocation guidance, and no location-test helper was registered. Fresh Advanced settings showed Send Crash Reports on. Dismissing the setup error exposed an older, misleading blanket instruction to approve Login Items and restart. A separate one-line copy fix now points back to the specific setup error. Rebuild the fixture and verify that rendered retry text before final CI and publication.

**Progress**: Core 240, coordinator 111, presentation 35, crash reporter 38, release tooling 21, and helper 204 checks in each of plain/TSan/ASan+UBSan passed. Monitor and website checks passed. Native signed universal 4.3.0 candidate builds and validates. Same-path signed 4.2.1-to-4.3.0 fixture upgrade preserves the transition deadline and seal, explicit crash opt-out, saved Dock and legacy menu-icon choice, ongoing protection intent, and session JSON bytes. The existing helper still answers across the update without new approval. Liquid Glass is visible in the candidate. A six-minute visible CPU/footprint sample is running; a matching pre-glass baseline is building in scratch. Production app and user preferences remain untouched.

**Resume point**: Re-read this list, current git status, the new agent reports, and `docs/2026-09-28-control-center-verification.md`. The previous test setup has been removed and production is unchanged. Preserve the original production app and preferences until a deliberate upgrade test. Felix's screenshot reports no launchd helper service and first launch from Downloads. Do not call the fix live before verified publication.

## 2026-09-28 - Codex continuation of Control Center investigation

**Request**: Continue the work Claude could not resolve. The latest transcript and worklog identify #92, widget loading and intent routing, as the remaining technical blocker. Oliver lifted the implementation hold on September 28 by choosing "Resume #92 investigation and implementation". Publication remains on hold.

**Plan and ownership**: The coordinating session owns all edits, builds, and Git operations. A read-only agent will independently review the failed app-intent routing spike and relevant Apple documentation. The coordinator will inspect current extension signing, helper communication, release validation, and live GitHub issue state. No other active Codex chat was found in this repository. Process inspection is restricted by the sandbox.

**Task list**:
- [x] Confirm the current #92 and #95 state and the exact scope of resumed work. #92 remains open and #95 remains a draft.
- [x] Reassess the rejected widget and failed routing variants using current source and primary documentation.
- [x] Implement App Sandbox with one exact helper lookup exception and validate both signed architectures.
- [x] Record evidence and remaining acceptance checks on #92, #78, #96, and #99. Track B10 separately as #101. Commit the verified fix and fixture evidence on main.

**Resume point**: The implementation (7f87bbb), isolated live tests, cleanup, and issue updates are complete. See `docs/2026-09-28-control-center-verification.md`. The fixture and evidence are committed alongside this entry. Do not publish or merge PR #95. The original routing spike remains outside this repository and was read-only.

**Licensed test approved**: Oliver approved an isolated app with a stubbed license and computer control. The fixture uses `com.amesvt.pingwarden92test`, its own App Group, helper, XPC endpoint, Keychain namespace, and session-history directory. The preparation script removes Keychain operations, licensing requests, Sentry, and Sparkle only in the scratch source. The helper implementation remains unchanged apart from identifiers, so AWDL is a shared hardware surface. Check that the installed app is inactive and AWDL is up before any live toggle, turn protection off afterward, and unregister only the fixture helper during cleanup.

**Build verification**: Native Xcode Debug build and universal Release build succeeded with no reported warnings. The signed Release candidate passes distribution validation in both architectures. PlugInKit accepted the signed candidate after registering its containing app. All 21 release-tool tests and five license-parity tests passed. A separately sandboxed diagnostic using unchanged production seal and widget-gate code accepted a synthetic valid app seal and rejected tampered, expired, and unlicensed fixtures without writing real license state.

**Live verification and cleanup**: The signed sandboxed fixture passed control On/Off, containing-app launch from a quit state, responsive-helper Repair while on, legacy menu-icon hiding, and ordinary quit restoring AWDL. Oliver supplied the decisive menu-bar clicks and confirmed the on-state gray capsule persists away from the pointer. The helper and test control were removed, generated installed data was trashed, and AWDL finished UP. Production app/helper and preference checksums are unchanged. B10 remains separate under [#101](https://github.com/oliverames/ping-warden/issues/101).

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

## 2026-09-28 - Session wrap-up: review fixes merged, #92 escalated

**What changed**: All lane A to D review fixes are on main (latest code commit afc7a0d; docs through d1a209d). The Dashboard batch cut hidden-Dashboard CPU from 5.6% to 0.23% in the fixture and to 0.35% on a signed build, and memory growth stopped. PR #95 is merged with main and fixed (a066756, 6c25b4f). #89, #90, and #91 are closed. #99 (release) and #100 (Sentry) are new. 898 empty test plists are in the Trash, and tests now use temporary-path suites. The #92 spike and the signed-build checks are recorded below and on #78, #92, and #96.

**Decisions made**: PR #95 keeps 4.2.1 Hide Menu Bar Icon users on the old behavior under a new key. A2 stays: Off still raises awdl0. #92 is held. The installed /Applications copy may be overwritten for testing.

**Left off at**: the official 4.2.1 is reinstalled (digest verified) with its test settings removed. Main is clean and pushed. The spike source and `SPIKE-RESULTS.md` live at `~/Developer/Projects/ping-warden-intent-spike` (not under git). The Ping Protection menu bar control Oliver placed is now orphaned, because 4.2.1's widget doesn't load.

**Open questions**: whether to ship option 1 for #92; how to license signed protection checks (a test key, or a license-stubbed test build); release approval (#99); the Sentry decisions (#100); the customer's `launchctl print` readout.

---

## 2026-09-28 - #92 routing spike (done: option 3 blocked)

**Request**: Oliver approved the #92 spike on this Mac with computer control, and said on 2026-09-28 that he doesn't use the installed app, so it may be overwritten. He also chose to keep Off forcing awdl0 up (A2) and approved trashing the old test plists (898 moved to the Trash).

**Plan**: (1) A minimal Developer ID–signed spike app with its own bundle IDs (`com.amesvt.pwintentspike`, App Group `PV3W52NDZ3.com.amesvt.pwintentspike`) and a sandboxed control widget whose shared SetValueIntent logs which process runs `perform()`. Variants: `.background` only, `supportedModes` with `.foreground(.dynamic)`, and that plus `allowedExecutionTargets = .main` (macOS 27). Test with the app quit and running, and check for activation or windows. This Mac runs macOS 27.2, so macOS 26 routing can only be approximated. (2) If routing works, implement option 3 in Ping Warden on a branch, following lane E's file plan (`docs/2026-09-27-app-review.md`, lane E; full notes in the session scratchpad), and verify a signed build installed over /Applications. No release.

**Resume point**: spike sources under `~/Developer/Projects/ping-warden-intent-spike` (scratch, not committed to ping-warden). Remove the spike app and its control from Control Center when done.

**Result**: Routing to the app works, but chronod's connection to the Developer ID app fails with `Operation not permitted` in every app-routed variant (C, E, F, G, sandboxed C, C without get-task-allow). The extension path (variant A) runs `perform()` in the sandboxed widget. Details in `SPIKE-RESULTS.md` beside the spike source and on #92. Cleanup: the spike app and its build copy are in the Trash and unregistered, and the menu bar control is removed. A Control Center tile may remain, because MenuBarAgent's panel can't be clicked or captured; remove it with Control Center → Edit Controls if it shows. Shortcuts access was declined, so no Shortcuts comparison. Next step waits on Oliver: a notarized option 3 retest, or option 2 with its launchd test on this Mac.

**Oliver's decisions (2026-09-28)**: notarize the spike and retest option 3, then move to option 2 if it still fails. Run the #78 and #96 signed-build checks on this Mac with Developer ID builds of main and PR #95, installed over /Applications. VoiceOver, contrast, and root-only awdl0 checks stay with Oliver, and he clicks any Login Items approval.

**Resume point (signed checks)**: build an unsigned Release archive, then `SIGN_ONLY_OUTPUT=<new dir> PingWarden/PingWarden/notarize.sh <version>` signs with release entitlements without uploading. The target must not exist. Record results on #78 and #96.

**Notarized retest (08:32)**: the notarized, stapled spike (Gatekeeper: "Notarized Developer ID") failed the same way. Oliver clicked the control three times, and all three logged EPERM. Option 3 is blocked.

**Signed-check phases** (starting state: /Applications has 4.2.0 (42000), helper registered and allowed, `runs = 0`): (1) Launch 4.2.0 and update to 4.2.1 through Sparkle. Check What's New, the Help release link, preference persistence, and no donation buttons (#78). Turn on 4.2.1's Hide Menu Bar Icon for the #96 upgrade check. (2) Install a signed main build over it and run the release-candidate checks: Off and quit restore awdl0, Repair on a working helper, Dashboard CPU when hidden, and the control's availability. (3) Install a signed PR #95 build and run the #96 checks. (4) Option 2 launchd test: install a build whose helper plist adds an App Group–prefixed MachServices key, then check whether launchd lists the new endpoint without re-registering. Always turn protection off before moving on.

**Signed-check results (2026-09-28)**:
- #78: the Sparkle update from 4.2.0 to 4.2.1 worked. What's New showed and then stayed dismissed, preferences carried over, and there were no donation buttons.
- The signed PR build: open Dashboard 2.03% CPU, hidden 0.35%.
- #96: the legacy upgrade, the Control Center Only toggle (Cancel and confirm), General, and all three launch paths passed. The unlicensed toggle opened no window. The disabled General rows weren't visibly dimmed, fixed as 6c25b4f on the PR branch.
- **#92 is live**: pkd rejects the shipped widget ("plug-ins must be sandboxed"), so the Ping Protection control can't be added on macOS 27.2. Option 2's new Mach service isn't picked up on update (`parent bundle version` stays 42000). Option 1 (sandbox plus the global-name Mach-lookup exception) loads, and its unlicensed enable and its Off-to-helper paths work. The licensed enable path is untested.
- Protection checks are blocked because the install is unlicensed.
- Restored the official 4.2.1 (digest matches) and removed the test settings. The menu bar control Oliver placed is now orphaned. Results are posted on #78, #92, and #96.

**Decisions (Oliver, 2026-09-28)**: hold #92 for now. Option 1 is the documented recommendation, and nothing is implemented. Oliver has no Ping Warden license on his Mac, since he's the developer. So the signed protection checks (awdl0 enforcement, Off, quit, and Repair with protection on) need either a key he issues himself or a separately signed test build with a stubbed license gate and its own helper identity. Building that test build is new infrastructure and waits for his go-ahead.

## 2026-09-27 - Whole-app review and polish (fixes complete; signed checks pending)

**Request**: Oliver asked for a review of the code that takes down AWDL and the rest of the app, polish of rough edges, performance, UI, and UX, and closing open GitHub issues.

**Plan**: Phase 1 runs five read-only review agents in parallel, each with a fixed lane: (A) helper daemon and AWDL enforcement, (B) app protection pipeline, XPC, sessions, Game Mode, and widget control path, (C) UI, UX, accessibility, and copy through the isolated fixture, (D) performance and energy, (E) the #92 widget-sandbox redesign plus a review of open PR #95 (#96). Phase 2 consolidates verified findings into `docs/2026-09-27-app-review.md`, then fixes them in batches with disjoint file ownership, with tests and a CI-flag Release build per batch. Phase 3 closes issues with evidence. Items needing a signed installed build, VoiceOver, or a live game (#64, #78, #89, #90 residue, #91 residue, #96 signed checks) are listed for Oliver rather than run against the installed app. #93 and #94 wait on Oliver's decisions. No release without approval.

**Guardrails for every agent**: no edits to the repo in Phase 1; never launch or read preferences of the installed app; never register or unregister the helper; never touch licensing or the keychain; builds only into scratch DerivedData with signing off; UI viewing only through a renamed-bundle isolated fixture.

**Resume point**: If interrupted, re-read the agents' reports (or rerun the lanes), then continue Phase 2 from `docs/2026-09-27-app-review.md`.

**Progress (2026-09-28)**: All five reviews are in; findings and status live in `docs/2026-09-27-app-review.md`. Every lane A to D finding is fixed on main except the deferred A8 ProcessType and B10, which waits for #92. Merged: helper hardening (7aaa069, ed60850), the protection pipeline (7eb2091, 78c00ee, 2ba9c5e), Settings, Welcome, menus, and copy (07347a7, a86ac79, 869bd34), harness waits (c47a473), and the Dashboard and performance batch (52dab46 to c6eb9c1). Follow-ups: the menu shares the intervention poll (83e4b8b), the last three-dot ellipses (609c4e5), and test preference suites now live in a temporary folder instead of adding about 20 empty plists to ~/Library/Preferences per run (afc7a0d). PR #95 has E1 to E8 fixed, was merged with main, and was pushed as a066756; it stays draft for the signed #96 checks. Issues on 2026-09-28: #91 closed after an isolated full-window check; #89 and #90 closed with their signed-build and VoiceOver residue moved into one checklist on #78; design review posted on #92 (recommends running the control intents in the app process, pending a signed spike); status posted on #96, and the PR #95 description updated. #64, #93, and #94 are unchanged. Agent worktrees and temporary branches were removed.

**Decision needed**: about 910 empty plists from earlier test runs remain in ~/Library/Preferences, named `com.amesvt.pingwarden.tests.*`, `PingWardenWelcomeTests.*`, `PingWardenCrashReportingTests.*`, and similar. Moving them to the Trash waits for Oliver's go-ahead. The app's own `com.amesvt.pingwarden.plist` and the fixture domains are not part of that set.

**Decisions (Oliver, 2026-09-27)**: PR #95 keeps existing "Hide Menu Bar Icon" users on the old Dock behavior until they opt in, using a new preference key. New windows open at about 900×780, keeping saved frames. The license key field becomes a plain text field. Unlicensed first runs lead with Open Dashboard, with "Set Up Ping Protection" as the secondary action. Undo (no confirmation) for deleting a custom ping target was decided in the session as a routine choice.

## 2026-09-27 - Helper-timeout recovery

**What changed**: a26e6fe makes Repair, Welcome setup, and Finish Setup confirm that the helper answers, and rebuilds a registered but silent helper (unregister, register) only from those explicit actions. Success requires a helper reply, and a registration is never removed when the bundle could not rebuild it. At launch, a registered helper that stays silent after three attempts shows the Welcome once if it was never presented, otherwise a dashboard message pointing to Repair. Turning protection off skips the helper when nothing requested it and awdl0 reads up. Diagnostics add `location` (category only, no path) and `launchd_job` (whitelisted `launchctl print` fields; exit 113 means no job).

**Evidence**: The 4.2.1 app, helper, and widget are universal (x86_64 and arm64) with minos 13.0, and the helper signing identifier and team are unchanged since 2.2.2. Before the fix, `registerHelper` returned success on `.enabled` without a helper reply, so Repair could not rebuild a stale Background Task Management record, and a first enable that timed out left `lastKnownState` "unknown", so turning off called the silent helper and failed. The customer's Login Items shows the background item enabled.

**Verification**: Release build (CI flags) succeeded with no warnings on either main or the change. 164 core tests (11 new), the monitor harness (5 new repair and probe checks, each mutation-tested to fail against a broken implementation), 162 helper checks, 38 crash-reporter checks, release-tool tests, and 26 presentation checks passed. Not verified: a real Ventura or Intel run, and a real unregister-then-register cycle on any Mac. The repair path is covered only by the in-memory harness.

**Sentry audit (read-only, 2026-09-27)**: Client wiring is correct. The SDK 9.26.0 is statically linked in the shipped binary, the DSN matches the project's only key, release names match `release.sh` (`com.amesvt.pingwarden@4.2.1+42100`), dSYM UUIDs match the binary, and consent defaults on for new and never-chose installs per #85. Zero errors and issues in 90 days; the last event arrived 2026-06-25 on 2.4.3. Reporting was off by default from 3.0.0 through 4.1.9 and on again only from 4.2.0, so zero is plausible but delivery is unproven. Non-fatal errors, including the helper timeout, are never sent. Server-side filters, key rate limits, and outcome stats were not readable through the connector.

**Sentry server side (REST API with the vaulted token, read-only, 2026-09-27)**: stats_v2 over 90 days shows 5 accepted error events, one each on 2026-07-24, 07-26, 07-30, 08-01, and 08-06, and no filtered, rate-limited, invalid, or client-discard outcomes. The connector's event search returns none of them, consistent with those events being past the plan's retention window (inferred). The only active inbound filter is `filtered-transaction`, the single client key is active with no rate limit, there are no discard rules, and both 4.2.1 dSYMs (x86_64 `659d396c`, arm64 `143344fb`) are uploaded with debug, symtab, and unwind data. Data scrubbing and IP scrubbing are on.

**Docs**: 74f8716 adds a troubleshooting section for a helper that is approved but never answers, including the note that Prepare to Remove can stop with an error in that state. Oliver approved publishing it.

**Left off at**: main at 74f8716 plus this worklog commit. No release and no version bump.

## 2026-09-25 - Control Center toggle in marketing

**What changed**: A new competitor, AWDL Toggle (github.com/yay/awdl-toggle, posted to r/MacOSBeta on 2026-09-15), leads with a Control Center switch and no menu bar icon. Ping Warden already ships both, so the toggle is now a named feature: a "One switch in Control Center" section on the homepage, a Control Center toggle section and nav link in the README (which also feeds `/docs/overview`), and a "Control it your way" paragraph in `docs/gumroad-product-description.html`. Separately, the Settings footer, the Hide Menu Bar Icon confirmation, the Quick Start, and Troubleshooting told people to add the control in System Settings > Control Center. On macOS 26, third-party controls come from Control Center > Edit Controls (Apple, "Customize the menu bar on Mac"). The guides also implied hiding the menu bar icon was required; it is optional.

**Dock icon (follow-up the same day)**: Oliver chose to allow hiding both the menu bar and Dock icons. The H2 lockout guard that forced the Dock icon on in Control Center mode is gone. `InterfaceVisibilityPolicy` (Core, with tests) decides instead: a launch the person starts opens Settings when no icon is visible, while login-item launches (the `keyAELaunchedAsLogInItem` Apple event) and Control Center launches (the widget now passes `--launched-by-control-center`) stay silent. Reopening a running app already opened Settings (#28). Existing users keep their current Dock setting. Public copy avoids Dock claims because the site deploys on merge before the app ships; it says to open Ping Warden from Applications or Spotlight, which is true in 4.2.1 and after. Oliver then asked that Control Center mode always hide the Dock icon, so opening the app is the single route to Settings. The Show Dock Icon preference is kept but ignored while the mode is on, and General disables it and Show Live Metrics in Menu. Competitor notes and an optional, unposted reply draft are in `docs/2026-09-25-competitor-awdl-toggle.md`; the recommendation is not to post. Troubleshooting gained a hidden-icon entry, and the awdl0 guide lists AWDL Toggle among free options. The setting was then renamed from Hide Menu Bar Icon to Control Center Only; docs give both names while 4.2.1 is current. Mac verification is tracked in #96.

**Resume point (2026-09-25 12:45 UTC)**: PR #95 is a draft on `claude/competitor-research-wqmkir` at 47d2a59. Every CI check passes, including the macOS `xcodebuild` build and CodeQL, and it merges cleanly into `main`. There are no review comments. PR monitoring was stopped at Oliver's request. Next: run the #96 checklist on a Mac with a signed build, then take the PR out of draft and merge it. After merge, publish the Gumroad description and let the site deploy.

**Decisions made**: Dropped a homepage header link to the new section because four links wrapped the header at phone width. The toggle-reflects-Game-Mode claim was checked against the code: the `effectiveMonitoringEnabled` setter reloads the control.

## 2026-09-24 - Released 4.2.1

**What changed**: Published v4.2.1 (42100) from 7e14da1 with `release.sh`, which exited 0. Xcode's build-setting tool bumped the project versions; the plists and `HELPER_VERSION` were bumped directly. The version bump (1248009) was pushed before the notes, then the notes and site pages (7e14da1), so the website published the notes only minutes before the download. Added bddec76, which centers the transition notice's donation section, after Oliver flagged the mixed alignment; checked in the isolated fixture. Appcast copies committed as 3f118b9.

**Verification**: 153 core tests, 13 release-tool tests, 26 presentation checks, site build and check, and shellcheck passed locally. GitHub Build Verification passed on bd56178. CodeQL had not finished on the final commits, and no CodeQL CLI is installed locally. For the published release: the DMG SHA-256 matches the local artifact; Gatekeeper accepts it as Notarized Developer ID with the ticket stapled; the deep codesign check passes; app and widget report 4.2.1 (42100). Both live feeds offer 42100 and verify against the app key, and the enclosure EdDSA signature verifies. The releases page lists 4.2.1, and Sentry has the dSYMs. The script verified Gumroad delivery, and the license-key node is present. Evidence is in [#78](https://github.com/oliverames/ping-warden/issues/78).

**Decisions made**: Keep "Enter a License Key" as the prominent transition action. Run the remaining hands-on checks after release. Product Hunt waits for a redesign ([#93](https://github.com/oliverames/ping-warden/issues/93)). Standing rule from Oliver: updates must never disturb existing licenses, registrations, or saved state. The v4.2.0 → v4.2.1 audit found no diff in LicenseManager, LicenseStateSeal, PingWardenPreferences, or entitlements.

**Left off at**: Release complete. Post-update signed checks remain in #78 and #90. The local-CI decision is [#94](https://github.com/oliverames/ping-warden/issues/94).

**Open questions**: Which local-CI option to adopt (#94).

---

## 2026-09-24 - Claude 4.2.1 release-readiness review

**What changed**: Reviewed the full app delta from v4.2.0 to 4ccad28 (app code identical to 8d13d34). Found no release-blocking regression. Targets keeps every control and handler. The view model and store load path are unchanged, so existing saved targets load without revalidation. Ran the #90 interaction checks in a rebuilt isolated fixture with scratch-file preferences: add, cancel, Escape, Return submission, URL rejection with no storage write, IPv6 save, relaunch persistence, removal fallback, and the relaunch badge across navigation all pass. Results are in [#90](https://github.com/oliverames/ping-warden/issues/90). Signed-host dispositions are in [#78](https://github.com/oliverames/ping-warden/issues/78). Corrected one phrase in the draft notes: the host error appears in the form, not beside it.

**Not verified**: Picker menus, focus movement after an invalid host, and license-field Return. Foreground desktop control was not approved. `CrashReporter` is now `@MainActor`, so its Sentry `beforeSend` closure would pick up main-actor isolation under Swift 6 mode. Swift 5 mode inserts no runtime check, so this is harmless today but worth revisiting before any language-mode change.

**Decisions (Oliver, September 24)**: Keep "Enter a License Key" as the prominent transition action. Run the three unverified checks on the signed 4.2.1 after updating, not before release. Publish only after CodeQL and Build Verification pass on the exact release commit. After release, refresh the #93 Product Hunt copy and check for drafts or duplicates, then stop before submission. Publication remains on hold until Oliver resumes it.

## 2026-09-24 - Wrap-up and Claude release handoff

**What changed**: Prepared [4.2.1 release notes](docs/release-4.2.1-draft.md) and a [self-contained Claude handoff](docs/2026-09-24-claude-release-handoff.md). The candidate build is 42100. Current source carriers and published feeds remain 4.2.0/42000. The notes extract correctly with the maintained release renderer.

**Decisions made**: Oliver requested wrap-up and a Claude review before publication to existing users or Product Hunt. The release notes remain outside RELEASE_NOTES.md because the Website workflow deploys that file's changes. No app, website, appcast, Gumroad, or Product Hunt release was performed.

**Left off at**: Build Verification for 8d13d34 passed, including macOS, Linux, and app bundle checks. CodeQL was still running at draft time. Source fixes and launch assets are pushed. The independent review found no actionable layout regressions. No configuration, marketplace, Notes, or memory was changed, so those reconciliation and backup phases did not apply.

**Open questions**: Claude must review remaining live interaction and signed-host acceptance in #90 and #78 before release readiness is declared. #93 tracks Product Hunt's account access, duplicate check, preview, date, and submission. Existing sales are supplied by Oliver; no customer count or product-success retest was added.

**Follow-up resolved**: Replaced the cloud-gaming graphic's landscape with a generated composite using the actual landing-page dashboard screenshot. Compared the result with the supplied dashboard and checked the marketing copy and laptop framing. The saved card is 1622 × 970 and 1,327,375 bytes. Updated the prompt record, launch description, and Claude handoff. The untouched screenshot still leads the gallery. No app source or release carrier changed in this follow-up. Build Verification for ba9e285 passed; CodeQL for 8d13d34 and ba9e285 remained in progress when rechecked. Publication remains held.

## 2026-09-24 - Restore Linux compilation of target validation

The hosted Linux check for 5905784 failed because CustomPingTargetStore imported Darwin unconditionally. The import came from the earlier a344c0c target-validation change. Wrapped it with the same Darwin/Glibc platform selection already used by TCPProbe. Validation and persistence logic remain unchanged.

The independent reviewer approved the narrow correction and ran 13 focused target-store and host-validation tests on macOS, all passing with no skips. The native production Xcode build also passed. The original failure is recorded in [Linux job 107772835079](https://github.com/oliverames/ping-warden/actions/runs/36040992165/job/107772835079). The corrected hosted result is recorded in [#90](https://github.com/oliverames/ping-warden/issues/90).

## 2026-09-24 - Match Targets to native settings

Committed the Targets layout as fa2819e. Replaced its dashboard cards and manual columns with the same grouped Form and native sections used by General. Preserved the Targets tab, bindings, target refresh and selection, custom-target actions, validation, and keyboard shortcuts. The scroll-edge treatment stays at the existing settings call site.

The production Xcode build succeeds, and all 26 existing actual-source presentation checks pass. Separate native previews verify light/dark appearance, the minimum 760 × 520 layout, and the add-server form. Fixed a duplicate port label identified in that preview. See the [verification record and captures](docs/2026-09-24-targets-native-layout.md).

Oliver requested an independent regression reviewer before committing. The reviewer found no actionable regressions. All 18 focused existing tests passed with zero failures or skips, and root inspected the output. Target selection, persistence, validation, fallback, busy states, focus, and keyboard bindings were reviewed. Live keyboard and click checks remain in #90 after Computer Use initialization failed with -10005. No installed app, helper, licensing, or network configuration was changed.

## 2026-09-24 - Prepare Product Hunt launch

Prepared the [launch record](docs/2026-09-24-product-hunt-launch.md), machine-readable listing fields, maker comment, two generated explanatory gallery cards, and an ordered selection of existing screenshots and thumbnail. The launch copy emphasizes AWDL-related Mac cloud-gaming interruptions, the free dashboard, the $15 one-time protection license, and the nearby-device-sharing tradeoff. The account-review task coordinated ownership and preserved these launch files while integrating its app changes.

Verified the public landing page and Gumroad offer, and GitHub's current 4.2.0 release metadata. The tagline is 47 characters, description 419 characters, and maker comment 185 words. All five selected PNG files exist and are below 3 MB. The generated cards are 1621 × 970, the original screenshots 2978 × 2648, and the thumbnail 256 × 256. Copy and graphics were inspected. No performance benchmark, new-user protection trial, or newer app release is claimed.

Oliver subsequently chose the real landing-page dashboard screenshot to lead the gallery. Targets is omitted from the gallery, and its tab is retained in the app with a native grouped settings layout. Confirmed the live page uses `/dashboard-v4.png`, with a complete 2978 × 2648 image. The gallery caption clarifies that intervention counts record attempts. Oliver confirmed existing sales, and the maker comment presents this as an established paid app arriving on Product Hunt. The existing native-design review task received the Targets observation.

Product Hunt's sign-in dialog is open in the in-app browser. Chrome navigation timed out, and its recovery returned `Browser is not available: chrome`. Oliver was asked to sign in and select a launch date. No submission, Product Hunt draft, scheduled launch, outreach, discount, app release, or installed-app change occurred. These submission steps are now deferred by Oliver's later publication hold until the Claude handoff and review. #93 tracks authenticated duplicate/draft checking, profile and tag verification, gallery preview, date selection, submission, and resulting status.

---

## 2026-09-21 - Complete the macOS 27 UI review

Reviewed all main screens in a full isolated app on macOS 27.2, plus native menus, transition/welcome states, helper and maintenance dialogs, and the diagnostics sheet. The [dated review](docs/2026-09-21-macos27-ui-review.md) contains a 21-group source inventory, runtime coverage, 12 representative captures, Apple guidance from Xcode's local archive, and explicit untested boundaries. The actual title bar correctly follows the selected pane. The earlier fixture title was not production UI.

The main visual follow-up is content-layer glass on Dashboard and Targets. #90 tracks that change alongside reproduced pending-relaunch state/accessibility, license Return submission, target URL validation, and reminder-copy findings. #89 tracks chart accessibility misclassification. #91 tracks existing compiler actor-isolation warnings without claiming a runtime race. #88 is closed after its verified fix, and #78 now includes the repaired Help command but retains signed-app acceptance. #64 still requires eligible real-game and Ethernet observations. Both dependency PRs remain merged, with no open PRs.

The review preserved the installed app and production state. The two app fixes are committed on main and locally verified; they are not a new published release. Signed Control Center hosting, updater windows, production persistence, system accessibility settings, and spoken VoiceOver navigation remain outside this isolated review. No claim is made that every permutation in the source inventory was exercised.

**Wrap-up verification**: The repository was clean and matched remote `main` at `33a0818` before this documentation reconciliation. GitHub Build Verification passed for app commit `e315918` and review commit `33a0818`; their CodeQL analyses remained in progress. Earlier local verification passed all nine affected recap tests, 162 helper checks, and universal app/helper/widget builds. Latest published release remains 4.2.0. No new build, installation, or release occurred during wrap-up.

**Resolved this session**: [#88](https://github.com/oliverames/ping-warden/issues/88) is closed, both dependency PRs are merged, and the reproduced Help-menu defect is fixed on main. **Still open**: [#78](https://github.com/oliverames/ping-warden/issues/78) now explicitly carries publication of `8bad3e7` and `e315918`, final CI review, and signed-app acceptance. [#64](https://github.com/oliverames/ping-warden/issues/64) retains real-game and wired-hardware checks. **New review follow-ups**: [#89](https://github.com/oliverames/ping-warden/issues/89) for chart accessibility, [#90](https://github.com/oliverames/ping-warden/issues/90) for UI corrections and remaining design/host verification, and [#91](https://github.com/oliverames/ping-warden/issues/91) for compiler warnings. GitHub reports five open issues and no open PRs.

**Continuation**: Resolve and verify the bounded UI findings, inspect pending analysis results, then deliver the committed fixes through the maintained release process. Preserve the installed app and production preferences until the outstanding local-installation decision is answered. Only Wi-Fi is currently available. Settings, plugin configuration, skills, and Apple Notes were not changed, so configuration backups and Notes reconciliation did not apply. Memory was not modified.

---

## 2026-09-21 - Repair the Help menu's release-notes observation

The full isolated UI review reproduced a defect within #78 that the earlier policy/native-menu tests missed. The app published a 4.2.0 offer and created its AppKit status-menu entry, but SwiftUI Help still showed only static documentation links. Logging-only snapshots confirmed the mismatch one and five seconds after launch.

Moved the unchanged Help contents into a Commands type that directly observes AppDelegate. In the rebuilt full app, the release-notes item appears after launch and disappears after selecting it. The universal native Release build succeeds with no new warnings. Signing settings, entitlements, and dependencies are unchanged. This is an unsigned full-app interaction check with inert URL handling, not proof of signed preference persistence or external navigation. #78 remains open for its original signed-app acceptance and linked #64 field testing.

---

## 2026-09-21 - Describe intervention counters accurately

Resolved #88 across General settings, menu metrics, dashboard counters and timeline labels, accessibility text, and shared Latency Session recaps. Counts now describe intervention attempts. Recaps explain that attempts do not confirm successful interventions or latency spikes prevented. Zero no longer implies that no wireless interruptions occurred. Removed the counter's ambiguous “Since Launch” heading and success-checkmark symbols on attempt events. Counter storage, encoded keys, XPC methods, reset behavior, and helper operations are unchanged.

Verification: all nine affected session-summary tests pass, including zero, one, and multiple attempts. All 162 helper checks pass, retaining the injected failed-write case. A native universal Release build succeeds for the app, helper, and widget without changing signing settings or entitlements. The full isolated app renders the revised General and Dashboard labels, 128-attempt recap, and zero-count state at minimum width on macOS 27.2. Accessibility text reflects attempts. The build's existing settings-observer concurrency warnings are tracked separately in #91.

This fixes the source on main. Release 4.2.0 and the installed 4.1.8 copy remain unchanged. The ongoing macOS UI review is tracked in #89 and #90; signed discoverability checks and real-game/Ethernet validation remain in #78 and #64.

---

## 2026-09-21 - Resolve review metadata and public-copy gaps

Removed the unmaintained homepage aggregate rating for #87, preserving the attributed testimonials and purchase offers. Completed the remaining maintained-guide corrections for #78: Latency Session licensing, Game Mode's Ethernet scope, intervention-attempt counts, and unsupported timing claims. Rebuilt the site and its content security policy.

Website checks pass. The 21 existing What's New and Game Mode policy tests pass, and an isolated native menu fixture passes 24 checks against unchanged production methods. Fourteen isolated Settings/About captures confirm donation buttons are absent from those views. The temporary test-window title is not the production title. See [the verification record](docs/2026-09-21-open-issue-verification.md) for methods and limits.

The website fixes are deployed and verified live, and #87 is closed. Dependency PRs #75 and #86 were reviewed and merged as `31d6a26` and `cdb99e8`. Both updated versions passed integration checks, unchanged-page comparison, npm audit, and a Wrangler packaging check. The exact-commit Website workflow then deployed successfully with Wrangler 4.135.0. GitHub reports no open PRs.

Full signed-app interaction remains separate from isolated verification and awaits approval to update the installed copy for #78. #64 still requires an eligible real-game session and wired hardware; Oliver confirmed Wi-Fi only is available now. The separate in-app intervention-counter wording defect was recorded in #88 with the reproduced failure case and affected surfaces. The verification record notes the remaining CI and interaction limits.

---

## 2026-09-21 - Add attributed user reviews to the landing page

Added three public testimonials beneath the dashboard image, preserving the exact wording and public attribution. The anonymous verified buyer links to the [Gumroad product page](https://amesconsulting.gumroad.com/l/pingwarden), which exposes no individual review permalink. The Reddit comments link directly to [u/Rilot's daily-use report](https://www.reddit.com/r/GeForceNOW/comments/1w0a6x5/comment/p9txm7h/) and [u/SpirTBTX's lag-resolution report](https://www.reddit.com/r/macbookpro/comments/1qzlg19/comment/o4i3jgr/). All three sources were freshly verified on September 21. No private buyer details were used.

The responsive section displays three cards on desktop and stacks them on mobile. Verification covered exact quote and link matching, accessible link names, visible keyboard focus, hover state, and rendered layouts at 1440, 390, and 320 pixels wide without horizontal overflow. The website build and all existing page, link, sitemap, structured-data, and worker checks pass.

The pre-existing structured-data review count remains tracked separately in [#87](https://github.com/oliverames/ping-warden/issues/87). This change adds no rating claim.

---

## 2026-09-21 - Ping Warden 4.2.0 released and verified

Published [4.2.0](https://github.com/oliverames/ping-warden/releases/tag/v4.2.0), build 42000, from `2de6c9c`. It includes confirmed helper results, bounded interruption recovery, protection against stale callback ordering, opt-out crash reporting with saved choices preserved, and matching Sentry release identifiers. The README, app disclosures, website, and live Gumroad copy now agree on the reporting default and qualify the AWDL claims.

The release source passed [Build Verification](https://github.com/oliverames/ping-warden/actions/runs/35627812286), [CodeQL](https://github.com/oliverames/ping-warden/actions/runs/35627812283), and [Website deployment](https://github.com/oliverames/ping-warden/actions/runs/35627812352). Fresh post-analysis checks found zero open CodeQL or Dependabot security alerts. The full release workflow completed without skipping any publication step. Signing and notarization ran while a temporary publication gate waited for all three exact-source CI runs to pass.

Apple accepted the app and DMG for notarization, and both tickets are stapled. Verification of a freshly downloaded GitHub installer passed Developer ID identity, hardened runtime, app/helper/widget identifiers, App Group entitlements, universal architectures, and Gatekeeper acceptance. The downloaded installer matches both GitHub's recorded digest and the local artifact: 5,845,407 bytes, SHA-256 `568feed0f1052994a4292a5750f81b0b41a4001efe14f8a1e2c9ef03f01605eb`. Both public update feeds are byte-identical to the prepared signed feeds, verify against the app's public key, and offer 4.2.0/build 42000 with the correct enclosure size and URL.

Sentry uploaded six new debug-information files and finalized `com.amesvt.pingwarden@4.2.0+42000`, matching the runtime identifier. Its release API confirms finalization and IP scrubbing remains enabled. Gumroad delivery completed unattended. A fresh buyer-download check matches the exact installer bytes and confirms the license-key block and all non-download buyer content are preserved. The only other buyer-page change is its expected publication timestamp. Price, currency, publication, tags, refund policy, and updated public description remain correct.

Issues #82, #83, #84, and #85 are resolved. [#78](https://github.com/oliverames/ping-warden/issues/78) retains the installed-app What's New and donation-removal checks, and [#64](https://github.com/oliverames/ping-warden/issues/64) retains real-game and Ethernet verification. Routine dependency updates remain tracked in PRs #75 and #86. The installed copy on this Mac remains 4.1.8/build 41800. No app installation, production crash injection, or community outreach occurred during this release.

---

## 2026-09-21 - Prepare 4.2.0 reliability and crash-reporting release

Prepared 4.2.0, build 42000, for the authorized release. The helper confirms interface writes before reporting success (#82). The app recovers from interruption-only helper restarts, rejects stale replies and reconnects, and requires helper confirmation for newly adopted widget state (#83). Rechecking an already-confirmed state preserves active sessions and pending stop intent. App and widget continue using the existing XPC contract.

Crash reporting now defaults on when no preference is stored, preserves saved choices, and stops new reports when disabled (#85). Removal closes the SDK without re-enabling it when preferences are cleared. The welcome window, Settings, README, website, release notes, and storefront source disclose the change. Sentry publication now derives its release identifier from the app's version and build (#84). Current Sentry project settings confirm IP-address scrubbing remains enabled.

Qualified current product claims and clarified that a protected Latency Session requires a license or an active transition (#78). CodeQL action references now advance together, and Dependabot groups future CodeQL updates to prevent mismatched initialization and analysis versions.

Verification before publication: 149 core tests, 162 helper assertions across 12 scenarios, 31 crash-reporter assertions, 13 release-tool tests, native monitor callback and recovery tests, website validation, shell checks, and the native Xcode app build. The monitor fixture compiles production methods against inert transport dependencies and includes a negative-control check from the review. The actual welcome view renders without clipped actions or privacy text at 540 by 640 and 480 by 560. At the smaller size, the license row remains reachable by scrolling.

Publication, signed-artifact checks, and live delivery results will be recorded after the release completes. Existing live-game and Ethernet checks remain in #64. Full installed-app What's New and donation-removal checks remain in #78. These isolated tests do not establish physical game-session coverage or install the release on this Mac.

---

## 2026-09-21 - The license refusal says what it costs and offers to buy

Uncommitted work sitting in the tree was reviewed, verified, and shipped as `51284df`. Every message that turned protection down said a license was required and left the reader to discover the price and where to get one. The price is now in the message, and a Buy a License link sits under the error on the protected session card, the interventions card, General settings, and the License pane. Turning on persistent protection from the menu reads the result rather than discarding it, so a license refusal raises an alert offering Buy a License, Open License Settings, or Cancel instead of the menu item quietly snapping back. The widget's `licenseRequired` string points at Settings and License too.

Verification: the app builds with signing disabled, and all 145 core tests pass through `swift test`. The three references the new code depends on were confirmed to exist first, since the change starts reading a return value from `setPersistentProtection` that was previously discarded. The app scheme has no test action, so the core suite runs from the package rather than through `xcodebuild`.

No documentation drift followed. The README and the landing page already describe a one-time $15 license, and README line 80 already documents the behaviour this change improves, so the app now matches the docs rather than the other way round.

Still open: [#78](https://github.com/oliverames/ping-warden/issues/78) and [#64](https://github.com/oliverames/ping-warden/issues/64) are unchanged by this. #78's item about reviewing public wording that implies everything except the protection toggle is free is worth reading alongside this change, since the in-app copy is now more specific than it was while the public copy is not.

---

## 2026-09-14 - Ping Warden 4.1.9 released and session closed

Published [4.1.9](https://github.com/oliverames/ping-warden/releases/tag/v4.1.9), build 41900, from a301e5a. It ships What's New and removal of the in-app donation buttons. First launch records the What's New baseline; prompts begin with subsequent version changes. The donor-license instructions remain.

Verification: all 145 core tests, 10 release-tool tests, and website checks passed. The maintained release workflow completed successfully, including site preflight, universal app/archive validation, app and DMG notarization and stapling, mounted-payload Gatekeeper validation, Sentry publication, signed stable/beta feeds, and unattended Gumroad delivery with its license-key content preserved. The downloaded GitHub DMG matches the local artifact: SHA-256 `08e6c36719486cf132ca3a1cb6cc91813dac813f43bb6349792c7163f27974ea`, 5,835,662 bytes. Both public feeds are byte-identical to the local signed copies and verify against the built app's public key. The website deployment passed and its live release page contains the 4.1.9 anchor.

Resolved this session: end-to-end release verification for #74 and #76. Still open: [#78](https://github.com/oliverames/ping-warden/issues/78) tracks live What's New and donation-removal UI checks; [#64](https://github.com/oliverames/ping-warden/issues/64) tracks live-game and Ethernet behavior. Dependency PRs #72, #73, and #75 remain outside this release. The installed /Applications copy was checked and remains 4.1.8; publication does not imply this Mac was updated.

The website's fresh supplied screenshots and layout corrections are deployed, and legacy upgrade guidance is documented in the linked session records. Oliver confirmed he had answered the comments he wanted to answer, so the reply sweep is stopped. Earlier unsubmitted-draft descriptions below are historical snapshots; the community handoff records later publications. Review-request emails and other optional outreach have not been rechecked or sent during release closeout. No agent configuration or skills changed, so configuration backups and Notes configuration-tree reconciliation do not apply. No Codex memory was changed.

---

## 2026-09-14 - Session reconciliation and targeted community replies

Reconciled every requested workstream in [the session review](docs/2026-09-14-session-review-and-community-followup.md), separating shipped v4.1.8, changes committed after that release, earlier verification records, and unsubmitted drafts. Verified the current release, all twenty v2 opening banners, Discussion #77 contents, and closed issues #74/#76. Recorded remaining release validation and public-copy qualifications in [#78](https://github.com/oliverames/ping-warden/issues/78), alongside existing live-game issue #64.

The current Reddit profile confirms seven posts and one App Pile comment, including the later Luna and Steam Link submissions. Read the posted copy and corrected this log's weekday, download-population inference, unverified removal cause, and unverified modmail status. Searched both app-name spellings in Reddit comments and prepared three targeted replies in Chrome: Moonlight issue #159, the GeForce NOW intervention-counter question, and a comment mixing up Ping Warden with AWDLControl. Replies are saved in [the draft document](docs/2026-09-14-community-reply-drafts.md) and remain unsubmitted. The reply approach and diagnostic questions are editorial additions for Oliver to review.

Rechecked xCloud's self-promotion restriction and BoosteroidCommunity's explicit ban on AI-assisted posts and comments. Existing recommendations are evidence of audience relevance, not permission for developer promotion. The search is bounded and lower-priority context-review candidates remain listed in the audit.

Verification: 145 core tests passed, all 10 release-tool tests passed, and the website check passed for 13 HTML pages, structured JSON, local links/anchors, 12 sitemap URLs, and two worker tests. The first Swift attempt could not write its compiler cache under the sandbox, and succeeded with normal cache access. The initial Python unittest module invocation used the wrong import path, then the repository's direct script passed. No new app release or social publication occurred in this continuation.

---

## 2026-09-14 - Discoverability pass: announcements drafted, review follow-up, What's New, cask

**What changed**: Committed on main after the 4.1.8 release: a post-update "What's New in X.Y.Z" item in the status menu and Help menu that opens the releases page anchored to the running version (`Core/WhatsNewPolicy.swift`, seven tests, 145 total); the in-app Donate row in Settings and Donate button in About removed, since the app is paid; five fresh 4.1.8 screenshots under `docs/images/` with the README hero moved to the 4.x dashboard; the awdl0 guide retitled toward the words people search ("Mac Wi-Fi Ping Spikes and the awdl0 Fix"); a validated Homebrew cask kept at `Homebrew/ping-warden.rb`; and a download-count baseline snapshotted before any announcement.

**What the evidence showed**: Release downloads split 2.x 2,291, 3.x 1,041, 4.x 434, which describes download events, not the installed-user population or which notes anyone saw. Users recommend Ping Warden unprompted in r/GeForceNOW and r/macgaming threads from June through last week, but the project's last own post was the 2.0 announcement in February. The earlier listing check reported: served title and description are right, structured data carries a 5.0 rating from two reviews, and the account crossed the $100 Discover threshold (payout of $110.34 payable 2026-09-17), but Discover placement and the account-review outcome were not established. The earlier search-position observations were a single snapshot, not a stable ranking measurement.

**Reviews and requests**: Paul Nobert (Sep 3) and Rory Reed (Sep 5) left 5-star reviews. Rory's already had Oliver's response; Paul's did not, so a reply is typed into the Gumroad response box awaiting Submit. Gmail's Sent folder shows the "A quick favor for Ping Warden?" rating request went to eight buyers on 2026-09-10 (Paul, Alex, Rory, Olivier, Håkan, Michel, Dmytro, De Bovenkamer van Aart). Christophe Stenstrom (Sep 11) and Michael Grimm (Sep 12) never received it; identical drafts to both are in Gmail Drafts awaiting Send.

**Reddit**: Rules read on old.reddit for eleven subreddits. Drafts in Oliver's voice are filled into open Chrome tabs, nothing posted: a rule 6 approval modmail to r/GeForceNOW plus the post itself for after approval, and posts for r/macgaming (once-daily self-promotion allowed), r/cloudygamer, r/MoonlightStreaming, r/ParsecGaming, r/MacOS (promotional posts Saturdays UTC only, so it waits for 2026-09-19), and a PCP-format comment in r/macapps' September App Pile megathread (main-feed posting needs 10 local karma plus a 1-year or 100-star repo, neither met). Skipped: r/xcloud (no self-promotion), r/cloudgaming (no advertising), r/mac and r/macbookpro (no promotion of any kind). Drafts also saved at the scratch path for the session.

**Homebrew**: cask passes `brew style`, `brew audit --cask --new --online`, livecheck against the Sparkle feed, and `brew fetch`. Blocker: Homebrew triples notability thresholds for a self-submission by the repository owner (225 stars, or 90 forks or watchers) and the repo is at 86 stars, 3 forks, 2 watchers. The earlier audit reported a lower non-owner threshold, but passing a threshold does not establish acceptance. Do not arrange a proxy submission to bypass owner-specific review criteria. Alternative not yet taken: a personal tap under Oliver's GitHub account, which needs no notability review.

**Verification**: 145 core tests pass; unsigned Debug builds succeeded after each app change; `git status` clean after every commit; the new dashboard image serves from raw.githubusercontent.com with HTTP 200; the website check passed after the retitle rebuild. 4.1.8 is installed in /Applications and running for the screenshots (replaced the 4.1.7 copy; helper registration unaffected because the bundle path is unchanged). Not verified: the What's New item has not been exercised live, since the first build that ships it records a baseline and offers nothing until the release after it.

**Decisions made**: Announce 4.x only, not 3.0. The pre-4 donor note in the License pane stays because it tells donors how to claim a license.

**Follow-up the same afternoon, on Oliver's yes**: All twenty 2.x GitHub release bodies now open with a two-line banner pointing at Ping Warden 4 and the upgrade guide; v2.0.1 through v2.0.5 get the variant that says the build can't update itself and needs a manual download, v2.0.6 through v2.4.3 get the Check for Updates variant. Bodies were prepended, not rewritten. On a second yes, the standalone Buy Me a Coffee link lines were stripped from the v2.4.1, v2.4.3, v3.0.0, and v3.1.0 bodies; the 2.4.0 changelog bullet describing the old donation prompt and the v4.0.0 donor-honor sentence stay. Discussion #77 "Updating from Ping Warden 2 or 3" was created in Announcements to replace the pinned user post #30 ("I hope it works", April 2026); GitHub's GraphQL API has no pin mutation for discussions, so the pin swap was done in the browser. The README lost both Buy Me a Coffee badges and the "donations since version 4 still help" line, and `.github/FUNDING.yml` is gone; the Donors sentence under Pricing stays. Site rebuilt from the README (overview page dated 2026-09-14) and the check passed.

**Reddit audit, later the same day**: Oliver posted six items around 16:38 UTC. Live: the r/macgaming post (flaired Self promotion) and the r/macapps App Pile comment. Removed by r/MacOS moderators: the r/MacOS post, which went up on Monday. The rule limits promotional posts to Saturdays UTC, but no specific removal reason was verified. September 19 is the next Saturday, not authorization to repost. The earlier audit recorded Reddit-filter removals for: r/ParsecGaming, r/MoonlightStreaming, and r/cloudygamer, three near-identical posts with the same links inside sixty seconds. Approval modmails to those three mod teams are drafted in tabs. The r/GeForceNOW modmail body was refilled after being lost. Its sent status was not established. Round two, drafted into tabs after reading each sub's rules: r/Steam_Link post (32k, no posted rules), r/LunaCloudGaming post (7.6k, no posted rules), r/BoosteroidCommunity approval modmail (rule 4 needs prior approval; rule 3 bans AI-generated content), a comment on moonlight-qt issue #159 (open since 2019, 157 comments, active August 2026), and a Show HN (needs Oliver logged in). Skipped: r/amazonluna (rule 4, no other products), r/ShadowPC (rule 6, promotion is spam), MPU Talk (February 2026 thread shows the community treats drive-by developer posts as spam), MacRumors (rules page not reachable, unverified). Competing tools seen in the same threads: Keepresso (gyorgy.sh, free), "macOS Latency Fix" posted to r/GeForceNOW and r/BoosteroidCommunity in May 2026, and a July 2026 r/macgaming tool post.

**Left off at**: Everything above committed and pushed on September 14, 2026; browser tabs open for Oliver to publish.

**Open questions**: Whether to create a personal Homebrew tap now. Gumroad Discover eligibility and account-review outcome, with no verified completion date. Download counts a few days after the posts go up: `python3 scripts/download_stats.py --snapshot`.

---

## 2026-09-14 - Publish 4.1.8 with the review-pass fixes

**What changed**: 4.1.8 / 41800 from `d3a4cef`. Ships the six review-pass commits from earlier today: the session recap records only samples for the target it started with, a saved GeForce NOW target no longer falls back to another server while the zone list refetches on every pane reopen, protection state reported by the widget is confirmed with the helper, the license gate resolves the hardware UUID once and rewrites its clock mark at most every ten minutes, and the diagnostics `arch` line reports the running slice. The "New since 4.0" and upgrade sections carry forward in the notes. The bump commit also rebuilt `Site/public/docs/releases.html`, so the Website workflow passed and deployed instead of failing as it did for 4.1.7 ([#74](https://github.com/oliverames/ping-warden/issues/74)).

**What the release found**: Steps 1 through 8 of `release.sh` completed cleanly: fresh unsigned archive, Developer ID re-sign, app and DMG notarization both Accepted and stapled, Gatekeeper and mounted-payload validation, EdDSA update signature, both feeds re-signed and verified, GitHub release, Sentry dSYMs and release finalized, gh-pages publish. Step 9 failed: `publish_gumroad.py` gives Gumroad 60 seconds for the uploaded file's size and URL metadata to settle, and this run took longer. Buyer content was untouched by design. A few minutes later the metadata was ready and a manual rerun of the publisher completed with the license-key block preserved and 4.1.8 as the only embedded DMG. Filed as [#76](https://github.com/oliverames/ping-warden/issues/76).

**Verification**: Release v4.1.8 is published and not a draft or pre-release, targeting `d3a4cef`. The published DMG downloaded from GitHub is 5,815,586 bytes with SHA-256 `020cf60f...`, matching both the local artifact and GitHub's recorded digest. Gatekeeper accepts the DMG and the app inside as Notarized Developer ID, the ticket validates, the app and widget report 4.1.8 / 41800, the helper is signed by Developer ID Application: Oliver Ames (PV3W52NDZ3), and the app binary is universal (x86_64, arm64). Both live feeds lead with 4.1.8 / 41800 with an enclosure length matching the asset, verify against the app's embedded public key with `scripts/verify_sparkle.swift`, are byte-identical to the copies committed on main as `3e3b216`, and the enclosure URL returns 200 with the matching content length. Sentry finalized `com.amesvt.pingwarden@4.1.8`. Gumroad `products view` lists `PingWarden-4.1.8.dmg` with the correct size and the publisher verified the buyer download. pingwarden.app/docs/releases shows 4.1.8 at the top and the technical guide carries the corrected reminder wording. Before the build: 138 core tests, 9 release-tool tests, and the unsigned Release build all passed. For the review-pass push, Build Verification and the new website CodeQL job both passed; Dependabot has already opened its first npm update for `Site/`.

**Decisions made**: Kept the Gumroad fix out of this release and filed it instead, since the manual rerun resolved the deliverable and widening the readiness window is a tooling change worth its own commit. Did not exercise the Dashboard-open-during-a-session scenario live before shipping; the sample filter is a strict narrowing of what the recap accepts, so its failure mode is a shorter recap, not a wrong one.

**Left off at**: 4.1.8 live on both feeds, GitHub, Gumroad, and the website on September 14, 2026 at approximately 15:45 UTC. Signed feed copies committed on main as `3e3b216`.

**Open questions**: [#76](https://github.com/oliverames/ping-warden/issues/76) was fixed the same afternoon: the publisher now waits five minutes by default (`--wait-seconds` overrides it, `GUMROAD_WAIT_SECONDS` from `release.sh`), prints a heartbeat while it waits, and `release.sh` prints the exact rerun command if Step 9 still fails; verification is the next stable release completing Step 9 unattended. [#74](https://github.com/oliverames/ping-warden/issues/74) was closed the same afternoon: `release.sh` now rebuilds `Site/public` in pre-flight with the same commands the Website workflow runs and stops, before anything irreversible, if the committed pages are out of step; `SKIP_SITE_CHECK=1` opts out. [#64](https://github.com/oliverames/ping-warden/issues/64) still wants the live game session. Acceptance of 4.1.8 among 4.0.x installs: `python3 scripts/download_stats.py --snapshot` in a few days.

---

## 2026-09-14 - Security, performance, licensing, and advertised-functionality pass

**What changed**: A full review of the privileged helper, the XPC client, the license stack, the widget, the Sparkle configuration, the release scripts and CI, and every user-facing document against the code. Eight code fixes, two CI coverage additions, and six documentation corrections landed on main. No release was cut; these belong in the next release's notes.

**What the security pass found**: No high-severity issue. The helper enforces a Team ID plus bundle identifier code-signing requirement on its listener and refuses to serve when its own signature fails, the widget and app are the only permitted clients, the Sparkle feed is signed and verified before extraction with the defaults override cleared at startup, the Gumroad key never leaves the Keychain, and the git history contains no secret-shaped files or key material. One hardening was worth making: the app adopted a protection state from the shared App Group defaults whenever the widget's distributed notification arrived, and both the plist and the notification are writable by any process running as the user. The adoption is now provisional and the helper, the only authority on what it is enforcing, is asked to confirm; its answer wins on disagreement. The release scripts, workflows, and website were clean; two coverage gaps were closed by adding npm Dependabot for `Site/` (the one job that holds the Cloudflare token) and a CodeQL job for the worker, the site build, and the Python release tooling.

**What the performance pass found**: The app is already disciplined about idle polling, main-thread blocking, and history bounds. Two small costs were removed: the license gate walked the IORegistry for the hardware UUID on every sealed read, which happens on every menu refresh, and the one-minute entitlement tick rewrote and resealed the App Group plist every minute for the life of the process. The UUID is now resolved once per process (only a successful lookup is cached, so a transient IOKit failure cannot pin the fallback marker), and the clock mark is rewritten only when it is more than ten minutes stale, which is still far inside the 24-hour rollback tolerance.

**What the correctness pass found**: Two real bugs in how the dashboard and the session recorder share one probe stream. First, `DashboardViewModel` is rebuilt every time the Dashboard or Targets pane appears and kept its discovered GeForce NOW zones only in the instance, so a saved GFN target could not be matched until a fresh fetch of `status.geforcenow.com` finished; for those seconds the shared probe measured and displayed a fallback target. Discovered zone codes are now cached for the process and persisted across launches, and a new view model seeds its list from that cache before it registers a demand. Second, `ProtectedSessionCoordinator` recorded every sample the shared probe produced, but the dashboard registers at a higher priority and owns the target while it is open, so opening the dashboard mid-session folded samples from a different target into the session recap. Each probe result now carries the host and port it measured, and the session records only samples for the target it registered.

**What the documentation pass found**: The technical guide still said transition reminders were weekly (they fire at 30 and 7 days remaining since 4.1.5), pinned Sparkle 2.9.4 while the app ships 2.9.6, listed five Settings sections when there are six, and understated the Game Mode safety-timer tiers. Two site guides said Latency Sessions were free, but a session turns Ping Protection on and so needs a license or an active transition. The retired `landing.html` still described the pre-4.1.0 Screen Recording requirement. The Quick Start and Gumroad description now note that the welcome button reads Set Up Ping Warden until a key is verified. `Site/public` was rebuilt from the corrected Markdown and the site check passed. Everything else advertised, including the 14-day offline grace, the six-hour re-check, the 90-day transition, the 10-minute pause, the frontmost-app Game Mode detection, the Ethernet skip, the crash-reporting exclusions, and the removal flow, matched the code. The diagnostics snapshot's `arch` line, which only echoed whether the Mac had a CPU, now reports the running slice.

**Verification**: 138 core tests pass, 9 release-tool tests pass, the unsigned Debug build of the app, helper, and widget succeeds with every change applied, and the site build and check pass with the five regenerated pages matching their sources. The helper confirmation path, the GFN cache, and the session sample filter were verified by reading the code paths end to end; they have not yet been exercised in a live session with the Dashboard open during a Game Mode session, which is the scenario that produced the recap defect.

**Decisions made**: Did not bump the version or write release notes; the changes wait for the next release. Left the widget's Shortcuts-facing Toggle intent reading the saved preference rather than the effective state, since its description says it toggles the saved choice. Left `landing.html` in place with corrected copy rather than deleting it, since the repository records it as retired but the Gumroad page was not re-checked.

**Left off at**: All changes committed on main, September 14, 2026.

**Open questions**: Confirm the new CodeQL job runs green on the next push and that Dependabot opens its first npm pull request for `Site/`. Exercise the session recorder with the Dashboard open during a Game Mode session to confirm the recap now stays on the session's target. [#74](https://github.com/oliverames/ping-warden/issues/74) still wants the site rebuild folded into the release flow.

---

## 2026-09-12 - Publish 4.1.7 with the dialog-over-game fix

**What changed**: 4.1.7 / 41700 from `fe649da`. A system dialog appearing over a game no longer makes Game Mode auto-detect drop protection. The "New since 4.0" section carries forward in the notes.

**What the investigation found**: The observation logged earlier today on [#64](https://github.com/oliverames/ping-warden/issues/64) turned out to be a real defect. A listener on `NSWorkspace.didActivateApplicationNotification`, the same event the detector uses, saw GeForce NOW activate, then `com.apple.UserNotificationCenter` when its first-launch notification prompt appeared, then the game again. The detector took the prompt as the new frontmost app, so `frontmostIsGame` went false, and with Screen Recording absent the fullscreen path could not hold the game present. Two inactive samples at the 2-second cadence later, protection turned off, then flapped back on when the prompt closed. That is the interruption the feature exists to prevent, and a permission prompt or password sheet over a game is a normal event.

**Fix**: `GameModeActivationPolicy.shouldTrackActivation(bundleIdentifier:)` ignores activation from `UserNotificationCenter`, `SecurityAgent`, and the notification and Control Center overlays, mirroring `ignoredFullscreenOwners`. Only `UserNotificationCenter` was reproduced; the rest are the same family. Four new policy tests, 138 total.

**Stale-language scan**: Nothing in the app needed a copy change. The Automation pane, its permission alert, and the accessibility hints were fixed in 4.1.1 and read correctly. The "Before 4.1.6" lines on the homepage, README, and upgrade guide are accurate history. Donate surfaces were reviewed on 2026-09-06 and kept deliberately. The dated files under `docs/` are audit records and were left alone.

**Verification**: Release published and not a draft. Public DMG is 5,806,041 bytes with SHA-256 `cf561e9a...` matching GitHub's recorded digest; the app inside reports 4.1.7 / 41700, Gatekeeper accepts it as Notarized Developer ID, and the ticket validates. Both live feeds lead with 4.1.7, carry an enclosure length matching the asset, include the "New since 4.0" section in the 4.1.7 item, and verify against the app's embedded public key with `scripts/verify_sparkle.swift`. Gumroad buyer content embeds exactly one DMG, `PingWarden-4.1.7.dmg`, with the license-key block preserved. Sentry finalized `com.amesvt.pingwarden@4.1.7`. 138 core tests pass, 9 release-tool tests pass, and the unsigned Release build succeeded before the archive.

**Decisions made**: Did not ship 4.1.7 as a notes-only release. With no code change since 4.1.6 the update prompt would have cost every active install a restart for nothing, so the release waited until the live test produced a defect worth shipping. Left [#64](https://github.com/oliverames/ping-warden/issues/64) open: the engage handoff and the wired path in the field are still unexercised.

**Left off at**: 4.1.7 live on both feeds, GitHub, and Gumroad on September 13, 2026 at approximately 01:48 UTC (the evening of September 12 locally). Signed feed copies committed on main as `453516c`.

**Open questions**: [#64](https://github.com/oliverames/ping-warden/issues/64) still wants the interactive game session. Whether the 4.0 notice moves acceptance among 4.0.x installs; `python3 scripts/download_stats.py --snapshot` in a few days. The other four bundle identifiers in `transientSystemUIBundleIdentifiers` are inferred, not reproduced; a SecurityAgent password sheet over a game would confirm the second most likely one.

---

## 2026-09-12 - Verify game auto-detect and surface it to 4.0 users

**What changed**: Added a "New since 4.0" section to the 4.1.6 release notes describing the frontmost-app Game Mode detection and the Ethernet skip, re-rendered it into `appcast.xml` and `appcast-beta.xml`, re-signed both feeds, published to gh-pages, and updated the v4.1.6 GitHub release body from the same source text.

**Why**: Sparkle shows only the notes of the version it offers. Someone on 4.0.x is offered 4.1.6, whose notes were entirely about update checks, so the detection work that landed in 4.1.0 never reached them in the app. The website already documented it across setup, overview, technical, troubleshooting, and the GeForce NOW symptom guide, but the update dialog is where people actually read what changed.

**What the verification found**: The decision logic is correct against live system state. GeForce NOW declares `public.app-category.games`, so the shipping classifier matches it, confirmed against the live process rather than the bundle alone. A harness compiling `Core/GameModeActivationPolicy.swift` unmodified returns `shouldEngage: true` for a game on the live Wi-Fi path and `false` for a non-game frontmost. `NWPathMonitor` delivers a real first sample, so the `hasPathSample` gate from 4.1.4 has data. 134 core tests pass, 10 of them on this policy. Not verified: the `NSWorkspace` activation observer in the running app, the engage and disengage handoff, and the Ethernet skip in the field. Recorded on [#64](https://github.com/oliverames/ping-warden/issues/64).

**One thing to watch**: with GeForce NOW's first-launch notification alert on screen, `NSWorkspace.shared.frontmostApplication` returned `UserNotificationCenter` rather than the game. The detector reads `frontmostPID` from activation notifications rather than polling, so the impact depends on whether that alert posts one. If it does, a modal dialog over a game could cause a transient disengage after two inactive samples.

**Verification**: Both live feeds carry the new section and verify against the app's embedded `SUPublicEDKey` with `scripts/verify_sparkle.swift`. 30 items preserved in each feed, one copy each of the upgrade notice and the new section, every enclosure signature unchanged. GitHub Pages confirmed serving the new copy before accepting the change.

**Left off at**: Live on both feeds and on the v4.1.6 release page, September 12, 2026.

**Open questions**: Carry the "New since 4.0" section into the 4.1.7 notes when that release is cut, and keep carrying it while 4.0.x installs remain in the population; `python3 scripts/download_stats.py` shows where they sit. [#64](https://github.com/oliverames/ping-warden/issues/64) still needs the interactive game session for the engage handoff and the wired path.

---

## 2026-09-11 - Fix the 3.x upgrade path and publish 4.1.6

**What changed**: Rewrote the appcast upgrade notice, fixed update checks for helper-less installs ([#71](https://github.com/oliverames/ping-warden/issues/71)), published 4.1.6 / 41600, added a returning-user guide, and added download-count reporting. Also landed four mechanical SEO items: aggregateRating in the homepage schema, sitemap lastmod, homepage links to the symptom guides, and Moonlight/Parsec coverage.

**What the investigation found**: Delivery to 3.x installs is healthy. The feed URL and EdDSA public key are identical from 2.4.3 through 4.1.6, and minimumSystemVersion is 13.0 across 3.x and 4.x, so nothing in the feed excludes them. The barrier was copy plus one real defect. `update_appcast.py` stamps minimumAutoupdateVersion 40000 on every 4.x item, so a pre-4.0 install is never updated silently and the update dialog is the entire conversion event. That dialog opened with "now requires a one-time $15 license", buried the free transition behind two conditions, told the reader to check a Settings screen they could not have seen yet, and never mentioned that the 90 days starts whenever they update and the offer has no expiry. Separately, Sparkle only started when the privileged helper was registered, so installs that used the free dashboard and declined the helper never ran a scheduled check at all.

**Decisions made**: Did not build the Worker-served appcast for measurement. Existing clients have the GitHub Pages feed URL compiled in and GitHub Pages cannot redirect XML, so it could only ever measure 4.1.6 onward, which is not the population in question; it would also put the update channel on our Worker and sits against the app's no-usage-analytics promise. Used release asset download counts instead, which measure acceptance directly and collect nothing from users. Rejected the proposed "4.0 supports macOS 27" upgrade pitch: the macOS 27 fix shipped in 2.4.2 and the macOS 26-and-later Settings crash fix in 2.4.3, both already present in 3.x, so it is not a 3.x to 4.x differentiator. Also rejected a 3.x bridge release, since Sparkle always offers the newest applicable item and would serve 4.x regardless. Skipped competitor comparison content after confirming NVIDIA article 5801 links awdlcontrol.net, a free MIT app with feature parity on game auto-detect.

**Verification**: 4.1.6 published and not a draft, DMG accepted by Gatekeeper as Notarized Developer ID, enclosure length 5805195 matching the asset, both feeds verifying against the app public key. The rewritten notice was re-signed with sign_update and confirmed live on gh-pages, with every enclosure signature byte-identical to before. 134 core tests pass and the Xcode Release build succeeds. The returning-user guide returns 200 on the live site. Baseline download counts snapshotted to `docs/download-history.tsv` before 4.1.6 shipped.

**Left off at**: 4.1.6 live on both feeds September 11, 2026 at approximately 19:41 UTC.

**Open questions**: Whether the notice rewrite moves acceptance. The comparison to beat is v3.1.0 at 379 downloads against the 50 to 80 band each 4.x release has drawn; re-run `python3 scripts/download_stats.py --snapshot` in a few days. Note that #71 cannot reach the installs it fixes, since they are the ones not checking, so they need a manual check or a fresh download. [#64](https://github.com/oliverames/ping-warden/issues/64) live-game validation still needs an interactive session. Christophe Stenstrom bought on September 11 and has not had the ratings note the other eight buyers received.

---

## 2026-09-11 - Publish 4.1.4 and 4.1.5, fix the deploy gap, and add symptom guides

**What changed**: Two releases. 4.1.4 / 41400 from `2637dbd` ships the wired-path engagement fix and two diagnostic log additions. 4.1.5 / 41500 from `e5b7f96` replaces the weekly transition reminder with deadline-anchored ones at 30 and 7 days remaining, and rewrites the upgrade paragraph that reaches 3.x holdouts. Also: website deployment was repaired, issues #65, #66, #67, #68, #69 and #70 closed, and three symptom guides added to the site.

**Verification**: Both releases verified beyond the script's exit code. GitHub releases published and not drafts; enclosure lengths match the published assets exactly (5806558 for 4.1.4, 5804671 for 4.1.5); both feeds verify against the app public key with `scripts/verify_sparkle.swift`; both DMGs accepted by Gatekeeper as Notarized Developer ID. The live feed served 4.1.4 for about a minute after 4.1.5 published, which was a GitHub Pages build in progress, confirmed via the pages API and re-checked as `built` before accepting the release. 134 core tests pass. Website CI now deploys for real, confirmed by `Deployed ping-warden-site triggers` in the run log rather than by a green check.

**Decisions made**: Created a dedicated "Ping Warden Site Deploy" 1Password credential scoped to Workers Scripts Edit plus Workers Routes Edit on the pingwarden.app zone only, rather than widening the shared Personal MCP token. Made the deploy step exit 1 when the token is missing, since the previous `exit 0` reported success while deploying nothing and let the live site drift two commits behind main unnoticed. Declined the researched homepage copy that asserted AWDL channel switching "is the stutter" with specific millisecond figures, because `PingWarden/README.md` deliberately says transitions "can correlate with" latency jumps and disclaims per-spike causation.

**Left off at**: 4.1.5 published and live on both feeds September 11, 2026 at approximately 18:25 UTC, signed feed copies recorded on main. Site deploys automatically on push.

**Open questions**: [#64](https://github.com/oliverames/ping-warden/issues/64) live-game validation still needs an interactive session; the issue now carries a verified checklist, and the diagnosability blockers behind it are fixed and shipped. Gumroad still lists eleven attached DMGs at product level, but the buyer-facing rich content embeds only the current one, so the reported "menu of DMGs" problem is not visible to buyers; the CLI offers no per-file removal and this was left alone deliberately. Ratings outreach to the nine buyers and reading NVIDIA article 5801, which has refused automated fetches three times, both need Oliver.

---

## 2026-09-09 - Publish Ping Warden 4.1.3

**What changed**: Released 4.1.3 / 41300 from `2a23d0e` through the maintained signing, notarization, GitHub, Sparkle, Sentry, and Gumroad pipeline. This ships the obsolete donation-policy removal and dependency/build updates.

**Verification**: 131 core tests and nine release-tool tests passed. Independently downloaded the public DMG and verified its bytes, app/helper/widget signatures, notarization tickets, and Gatekeeper acceptance. Both live signed feeds match source and advertise 4.1.3. Gumroad has exactly one embedded DMG with matching bytes and preserves license-key delivery. Sentry symbols were accepted and the release finalized. See [release evidence](docs/2026-09-09-release-4.1.3.md).

**Left off at**: Published on GitHub and Gumroad September 9, 2026 at approximately 13:28 UTC. The signed feed copies are recorded on main. Website source pages were regenerated but not deployed to Cloudflare.

**Open questions**: Still tracked: [#63](https://github.com/oliverames/ping-warden/issues/63) hosted CodeQL completion, [#64](https://github.com/oliverames/ping-warden/issues/64) live-game validation, and [#65](https://github.com/oliverames/ping-warden/issues/65) the website development dependency advisory. No new blocker prevented app publication.

---

## 2026-09-09 - Resolve open issues and dependency pull requests

**What changed**: Resolved this session: merged #42, #53, #56, #59, and #60 in `0feb152`, then removed the unused donation-prompt policy and corrected documentation in `954f74b`. Issues #61 and #62 are closed. A new private 100% donor offer is active and stored in 1Password as "Ping Warden Private Donor Offer." The previously disclosed offer remains disabled.

**Decisions made**: Updated CodeQL initialization and analysis together to avoid their version mismatch. Preserved signed historical feeds and annotated the historical release notes instead. GitHub accepted the merge through the existing owner bypass and flagged its linear-history rule. No rules or permissions changed. Future dependency integration should preserve linear history.

**Verification**: 131 remaining core tests, nine release-tool tests, the complete unsigned Release build, and website build/check passed locally. Hosted build, Linux tests, and shell checks passed for `31fc177`. Website verification passed for `954f74b`. See [the review](docs/2026-09-09-issue-pr-review.md).

**Left off at**: Source changes are pushed. No new app release or website deployment occurred. NEW: hosted CodeQL completion is tracked in [#63](https://github.com/oliverames/ping-warden/issues/63), with run and commit evidence. Still open: the September 6 live-game validation is now tracked in [#64](https://github.com/oliverames/ping-warden/issues/64). This is a validation gap, not a confirmed defect.

**NEW security follow-up**: The wrap-up push surfaced Dependabot alert #1. Confirmed `wrangler -> miniflare -> sharp@0.35.2` in the website development dependencies. [#65](https://github.com/oliverames/ping-warden/issues/65) tracks GHSA-rgj7-g3m4-5g8c and the update to at least 0.35.4. Exploitability is unassessed and no fix was started.

**Open questions**: No product decision is needed. Inspect the CodeQL result and arrange a suitable interactive game session for the carried validation.

---

## 2026-09-06 - 4.1.1 UI review applied

Applied the ten UI recommendations from `docs/2026-09-06-repository-review.md` (commit `ec18e18`) and shipped them as 4.1.1 / 41100 from `5f2dd0c`. The Automation pane no longer claims Game Mode needs Screen Recording or fullscreen, and the toggle turns on without the permission; Donate left the dashboard and the menu; About uses the app icon; the dashboard opens at 1,000 points; session stats are coloured; Targets is its own Settings section; the welcome says cloud gaming. `LicenseGateParityTests` now asserts the widget's hand-copied licence gate matches the app's (132 tests).

Every changed screen was captured from an isolated Debug build (identifiers renamed to `pingwardenreview`, driven by `--show-window=` and System Events). The earlier "grey setup button" finding was a capture artefact from a non-key window and was dropped. Release verified: `stapler validate` and `spctl` accept the DMG as Notarized Developer ID, GitHub `v4.1.1` public, cache-busted feed leads with 4.1.1, Sentry finalized, Gumroad buyer download replaced with the licence-key block intact. Still unexercised in a live game.

## 2026-09-06 - 4.1.0 frontmost-app detection and Ethernet skip

Shipped the Game Mode detection change from `f122db0`. Protection now engages when a game is the frontmost app, with no Screen Recording permission, and stays off on a wired path. The decision is pure and tested in `Core/GameModeActivationPolicy.swift`. Built and tested, but not exercised in a live game before release; the first field report will be the real check.

The full stable 4.1.0 / 41000 release published from `ed2f913`. Verified: `swift test` 127/0, GitHub release `v4.1.0` public with the DMG, gh-pages and the cache-busted live feed lead with 4.1.0 (the Pages CDN served 4.0.4 for about a minute after publish), `stapler validate` and `spctl` accept the DMG as Notarized Developer ID, Sentry release finalized with four dSYMs, and the Gumroad buyer download replaced with the licence-key block intact.

Same day, the discovery pass: Gumroad listing renamed to lead with cloud gaming and moved to Software & Plugins, landing hero republished, GitHub homepage pointed at Gumroad, README rewritten, and the ames.consulting work page rebuilt as a product page with SoftwareApplication schema (ames-consulting `2484e42`). Record in `docs/2026-09-06-gumroad-discovery-plan.md`.

## 2026-09-05 - 4.0.4 welcome dismissal

Apple Developer access worked. The onboarding review found that an unregistered helper caused the welcome to repeat at every launch after dismissal. Added a persistent presentation marker without changing the welcome layout, protection intent, or license policy. Manual setup remains available, and app-data removal restores the introduction. Updated both READMEs, Quick Start, and release notes.

All 117 core tests and nine release-tool tests pass. A full Debug build with isolated settings and keychain identities was visually checked through first launch, **Not Now**, quit, relaunch, Settings, and the free dashboard. The welcome fits its normal window and does not repeat.

The full stable 4.0.4 / 40004 release published at 16:56 UTC from `2b3c46a`. Independently downloaded the public DMG, checked its bytes and Apple signature, and verified Gatekeeper and both stapled notarization tickets. Both live Sparkle feeds and their archive signatures verify against the app key, with the paid-upgrade boundary intact. Gumroad offers only the current DMG embed and preserves license keys. Sentry finalized the release and uploaded the missing symbols. Build Verification passed for the source commit; CodeQL was still running at 16:58 UTC. See `docs/2026-09-05-welcome-followup.md` for evidence and limits.

## 2026-09-05 - Landing polish and purchase verification

Published the second landing pass: app icon above the title, a shorter hero, complete phone navigation, a header purchase action, and a direct free download. Removed hidden reveal states and the floating button. Corrected contrast, feature labels, and the transition disclosure. Updated Gumroad's description for the version 4 donor cutoff, original transition deadline, and current setup labels. The description now has a tracked source in `docs/gumroad-product-description.html`.

Verified prepared layouts from 320 to 1440 pixels, live desktop and phone renders, keyboard controls, dark appearance, reduced motion, sanitizer output, and the US$15 checkout. Published HTML and description match their prepared sources. Buyer download and license-key content are unchanged. At Oliver's request, a new paid purchase passed Gumroad's non-incrementing license verification without changing its use count. Inbox delivery and activation on the buyer's Mac are not observable through the available sale record. See `docs/2026-09-05-landing-review.md` for evidence and limits.

## 2026-09-04 - Documentation verification after 4.0.3

Clarified the version 4 donor cutoff and the original 90-day deadline in both READMEs and Quick Start. Added the approved-helper eligibility condition and disclosed the Gumroad verification request in the privacy and License sections. Updated the detailed Sparkle guide for stable and beta feeds, paid-upgrade review, and current release publication. Reread the changed text against the release implementation, checked relative links, and passed `git diff --check`. This follow-up changes documentation only.

## 2026-09-04 - 4.0.3 native welcome follow-up

**What changed**: Rebuilt onboarding around the actual app icon, a centered introduction, three concise benefits, and native controls. Removed the settings-style cards and divider. Kept the price and license link visible, and retained the setup callbacks, keyboard shortcuts, and accessibility layout. Moved the view into `WelcomeView.swift`. Updated setup instructions to match the current labels and the Settings fallback. The tested Gumroad metadata wait from the 4.0.2 publication is included.

**Verification**: Release and Debug builds pass. The first welcome screen was visually checked in light appearance, and the minimum-size accessibility layout was checked in dark appearance. Escape dismisses the welcome, and its license link opens License settings. The app, helper, and widget shipped as 4.0.3 / 40003 from c6ddfbc at 21:09 UTC. The public DMG is 5,768,408 bytes, SHA-256 `5183f2477fffe14bd8e132153378b8928c9d7f1cfa3af13f8282c6ac0b51165a`. Its app signature, Gatekeeper assessment, and stapled notarization ticket pass. Both live feeds advertise 4.0.3 / 40003 with paid boundary 40000 and valid signatures. The installed 3.1.0 app fetched 4.0.3 and showed the price/transition notice before installation. Gumroad offers only the current DMG embed and preserves the key block; publication completed all nine steps with the bounded metadata wait. Sentry symbols and release are published. The landing page instructions are published and visually verified. Linux CI passed; GitHub macOS checks were queued at this observation.

## 2026-09-04 - 4.0.2 review and release preparation

**What changed**: Reviewed licensing, protection reconciliation, helper/widget lifetime, Gumroad delivery, Sparkle publication, and the landing page. Fixed license expiry bypasses, malformed-response handling, use-count increments, 4.0.0 transition migration, reconnect races, and misleading setup/license status. Refined the welcome window with a compact header, grouped license controls, and trailing footer actions. Its 560 by 600 point frame fits all ordinary text without scrolling. Hardened release preflights, independently verified feed signatures, added paid-upgrade boundaries, and restored stable releases to the beta feed. Gumroad publication now verifies DMG bytes and replaces old embeds while preserving license-key content. Restricted the exposed donor discount to zero redemptions and removed its value from current documents.

**Verification**: 112 core tests and six isolated release-tool tests pass. Release app and widget build successfully. Onboarding and License settings were visually inspected. The landing page passes sanitizer preview and desktop/phone layout checks. A customer-key activation probe was rejected by automatic approval review, so no customer key was submitted. Actual helper registration and a full Sparkle installation remain outside the completed checks. See `docs/2026-09-04-bug-review.md` for evidence and limits.

**Release status**: 4.0.2 published from 2675048 at 20:52 UTC. GitHub, both signed Sparkle feeds, and Gumroad's buyer download were verified. The public DMG matches SHA-256 `a9231ee131d0806dcce36132413c8ac34615a6ee351c088c910fe1b3f7543a40`; Gatekeeper and the stapled notarization ticket pass. Sentry symbols and release were published. Build Verification passed (33918212513). Gumroad initially returned incomplete size metadata; the safe stop left buyer content intact, and a retry completed delivery. Added a bounded wait and three regression tests, bringing release-tool coverage to nine tests. No customer email was sent.

**Follow-up**: Oliver requested a more deliberate Apple-style welcome after 4.0.2 became public. That redesign will ship in a new release.

## 2026-09-03 - 4.0.1 released

**What shipped**: The license-gate hardening and the storefront URL fix (see the 4.0.1 section of `RELEASE_NOTES.md`). Cut with `bash release.sh 4.0.1 ../../RELEASE_NOTES.md` per the runbook. First run aborted at the archive check because `PingWarden/PingWarden/Info.plist` hardcodes `CFBundleShortVersionString` and was still 4.0.0; the bump must touch six carriers: the four `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` pairs in the pbxproj, the app, helper, and widget `Info.plist` files, and `HELPER_VERSION` in `PingWardenHelper/main.m`. Second run completed all nine steps.

**Verification**: `gh release view v4.0.1` shows the single asset `PingWarden-4.0.1.dmg` (5,759,056 bytes), not a draft. The gh-pages `appcast.xml` serves `sparkle:shortVersionString="4.0.1"` / `sparkle:version="40001"` with an EdDSA signature ahead of 4.0.0. Mounted the DMG: `xcrun stapler validate` passes, `spctl --assess` reports `Notarized Developer ID`, codesign authority is `Developer ID Application: Oliver Ames (PV3W52NDZ3)`, the app reports 4.0.1, and the widget appex is present. Gumroad Step 9 attached `PingWarden-4.0.1.dmg` (file `bU750hiG5yh3ikgfEbK8Gw==`) but appended its embed after the license-key block, so the content page was reordered by CLI to: 4.0.1 DMG, activation note, license key. The 4.0.0 embed was then deleted through the dashboard editor (re-embedded via `content set`, selected by clicking the empty paragraph below it and pressing Backspace twice, then Save changes; the embed's ⋮ Delete menu item does not respond to clicks or keys). The buyer's content page offers only 4.0.1. The public API's `files` list still reports the 4.0.0 record afterward, though the product-level size attribute dropped from 5.46 MB to empty, so Gumroad keeps the file object even when nothing references it. Note for next time: a Backspace with the cursor in the paragraph *above* an embed deletes the embed *before* it; reload without saving to discard. Main-side `appcast.xml` committed as `a073ef5`.

**Left off at**: Nothing open on the release. Sparkle offer-to-update from 4.0.0 was not exercised on this Mac (installed copy is 3.1.0). Watch `Build Verification` on the two push commits.

## 2026-09-03 - Landing page rebuilt on the site's Ping Warden project page; license gate hardened

**What changed**: Second pass on `landing.html`. The page now mirrors ames.consulting directly: the `ames.consulting / Ping Warden` wordmark header with plain Barlow nav, the dark `#1c2929` software-hero tile from `/work/ping-warden/` (gold eyebrow, giant title with the real app icon, facts pills, gold primary and ghost buttons, the window-bar screenshot frame), the home page's red proof numbers, the three story cards with gold/red/deep top borders, uppercase kicker headings with the gold rule, practice cards for the README feature table, four setup steps, the featured-card pricing pair with the "Why a license" note from the README, an FAQ, the dark footer with the gold/red stripe and the OA colophon, and the floating "Get the license · $15" pill in place of the site's "Send me a note". Body sits on `--surface-page`. Dark mode follows the system preference only, like the site. Published and verified. Gotcha found on publish: both automation browsers (Claude in Chrome, the in-app pane) screenshot Gumroad's sandboxed cross-origin iframe as a blank tint until the first scroll, because Chrome defers painting cross-origin frames in a tab that is not the active window. A replica of the wrapper reproduced the blank at random regardless of CSS, so it is a capture artifact, not a page bug; a fresh Playwright browser renders the first paint. The root `scroll-behavior: smooth` rule was dropped along the way and stays out (plain anchor jumps). `data-gumroad-field="name"` moved off the H1 onto the pricing eyebrow, because Gumroad interpolates the product name ("Ping Warden License") and the hero should read "Ping Warden".

**Storefront URL**: `olivera40.gumroad.com` now 404s (the Gumroad username moved to `amesconsulting`). Replaced every reference in `README.md`, `PingWarden/QUICKSTART.md`, `PingWarden/README.md`, `RELEASE_NOTES.md`, and the two in-app Buy buttons in `PingWardenApp.swift`, which now use `LicenseManager.purchaseURL`. The 4.0.0 build in the wild still carries the dead link, which is one reason 4.0.1 needs to ship. `appcast.xml` (main and gh-pages) still carries it in the 4.0.0 release notes; the next release publishes a fresh appcast.

**README**: install flow is purchase-first (Gumroad receipt carries the DMG and key, GitHub Releases stays the free-features path), and the license step now comes before turning protection on.

**License audit and fixes** (see RELEASE_NOTES 4.0.1): the gate lived entirely in plain App Group defaults and `PingWardenMonitor.init` restored protection from `AWDLMonitoringEnabled` without consulting it. Fixed with `LicenseStateSeal` (HMAC-SHA256 over `LicensePolicy.sealPayload`, bound to IOPlatformUUID, secret duplicated in the widget gate), `LicenseManager.launchGateAllowsProtection` in the monitor's restore path, a launch reconcile in `applicationDidFinishLaunching` that clears a stale intent and explains why, `LicensePolicy.clockIsPlausible` against rollbacks, a keychain one-shot marker plus the approved-helper requirement for the transition grant, and a launch reverify. `swift test` passes (107 tests, six new). Release build of app and widget succeeds with `CODE_SIGNING_ALLOWED=NO`.

**Left off at**: 4.0.1 not yet cut. Everything is committed on `main`; the release runbook (`project-release-runbooks`) is the next step. Accepted limits: the seal secret is in the MIT source, so a reader can compute it, which is equivalent effort to building the free source; one key still works on unlimited Macs by design; 3.x installs that never update keep free protection.

## 2026-09-03 - Landing page restyled to the ames.consulting web system; license keys switched on

**What changed**: Rebuilt `landing.html` in the ames.consulting web family: Barlow Condensed and Lora embedded as base64 `@font-face` data URIs (latin subsets, about 170 KB), warm white `#faf8f5` light mode and the `#1c2929` Ames Shovels dark mode under both `prefers-color-scheme` and an explicit three-state toggle, gold at rest with red on hover, the Stripe-tier hero (eyebrow chip, red emphasis word, pill CTAs, facts-only proof strip), practice-style cards, numbered steps, the dark CTA band with a gold primary button, and the gold-rule section kickers. The real app icon (extracted from `Ping Warden.app`'s `AppIcon.icns`, unchanged since the project rename) replaces the CSS gradient mark in the nav and floats over the hero screenshot, and the same icon is now the product thumbnail on Gumroad. Dropped the fabricated live-latency badge. Added a 1.5 s safety timer so reveal sections never stay hidden if the sandbox's IntersectionObserver does not fire.

**License keys**: The product was live with no key generation. Gumroad's current editor has no Settings checkbox for this; a product issues keys only when its rich content carries a `licenseKey` node (Insert → License key on the Content tab). Added the node plus a one-line activation note via `gumroad products content set`, and the editor now shows the "License key (sample)" card with the product ID. Gotcha rewritten in `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` with the new check command.

**Verification**: Sanitizer preview and publish both clean (only head `meta`/`title` stripped; five woff2 data URIs, both icon data URIs, one `<style>`, one `<script>`, and six buy elements survived). Live page renders the embedded fonts and icon at `https://amesconsulting.gumroad.com/l/pingwarden`; clicking "Unlock Ping Protection" opens Gumroad checkout at US$15. Light, dark, desktop, and 800 px layouts checked in the in-app browser.

**Left off at**: First real purchase is still the end-to-end proof of key delivery. Sales count is 0.

## 2026-09-03 - Gumroad becomes the initial-install channel

**What changed**: Split distribution into two lanes. Gumroad now delivers the first install (DMG attached to the product plus the license key) and Sparkle via GitHub releases remains the update path. `PingWarden-4.0.0.dmg` attached to product `pingwarden` via `gumroad products update qthvm --file ...` (file id `57U--GuBwUarVbaI3OxkLA==`). Product description and custom summary rewritten: download from the Gumroad receipt/library, GitHub builds accept the same key. New `landing.html` (repo root, committed) published as the custom landing page at `https://amesconsulting.gumroad.com/l/pingwarden` and verified live, including a new "Can I use the GitHub download with my license?" FAQ. `release.sh` gained Step 9 (fail-soft Gumroad DMG upload, skipped for `BETA_CHANNEL=1`, `SKIP_GUMROAD=1` opts out, `GUMROAD_PRODUCT_ID` overrides, default `qthvm`); header comment, release summary, `AGENTS.md`, and `GEMINI.md` updated to match. Committed as `5e109b1` and pushed to `main`.

**Decisions made**: Kept Sparkle on GitHub releases rather than moving enclosures to R2 — the enclosure URL is public either way, so the host does not gate anything and the license key is the only enforcement point. Left the public GitHub DMG in place as a free funnel for the same reason. Chose fail-soft (Sentry precedent) over abort for the Gumroad upload since the GitHub release is already public by Step 9 and the upload is trivially retryable. Betas never touch the paid deliverable.

**Verification**: `bash -n` passes on the edited `release.sh` (Step 9 not yet exercised by a real release run). Sanitizer preview clean (`warning: null`, only head `meta`/`title` stripped, buy elements plus all five data fields plus inline script survive). Publish returned `success: true`. Live embed fetch shows the rewritten description, the new FAQ, and all six buy buttons carrying `data-gumroad-action="buy"` with checkout hrefs. DMG verified Developer ID signed (`Authority=Developer ID Application: Oliver Ames (PV3W52NDZ3)`) with silent `spctl -a -t install` accept before attaching. No Swift changes, so `swift test` was not re-run.

**Left off at**: Distribution split is live and committed. Still open: (1) the `is_licensed` (generate-a-key-per-sale) dashboard flag could not be confirmed — direct storefront fetches 404 outside a real browser, so if key generation is still off, buyers pay $15 and receive no key; check the product dashboard before the first sale. (2) `products update --file` appends, so each release adds one versioned DMG — prune superseded files in the dashboard periodically. (3) First real purchase remains the first end-to-end proof of key delivery, per the earlier open item.

**Open questions**: Carried forward — widget duplicates the 14-day grace constant with nothing catching divergence.

---

## 2026-09-03 - Ship 4.0.0: license-gated Ping Protection goes public

**What changed**: Cut and published 4.0.0, the first licensed build. Versions moved 3.1.0/30100 to 4.0.0/40000 across the four Xcode targets, the app, helper, and widget `Info.plist` files, and the helper's `HELPER_VERSION`. `release.sh 4.0.0` archived, re-signed with Developer ID `PV3W52NDZ3`, notarized and stapled both the app and `PingWarden-4.0.0.dmg` (5.5 MB), signed the Sparkle archive and appcast, published the GitHub release, uploaded six dSYMs to Sentry as `com.amesvt.pingwarden@4.0.0`, and pushed the `gh-pages` appcast as `347bb4b`. The main-side appcast copy is committed as `df99141`. The Gumroad product `Ping Warden License` (`FmGG0pxyEyzJqp_BG4itFQ==`, permalink `pingwarden`, $15) is published and purchasable.

**Decisions made**: Shipped as 4.0.0 rather than 3.2.0 because gating a previously free feature is a breaking change for existing installs, and the 90-day transition needs a version boundary users can point at. Did not mark the appcast item `criticalUpdate`, so Sparkle offers 4.0.0 normally rather than forcing it. Left the published GitHub release body and the signed appcast description as-is after correcting a refund-scope sentence in `RELEASE_NOTES.md`, so the two published artifacts stay consistent with each other; the correction applies to future renders.

**Verification**: `swift test` 101 of 101. Both Xcode schemes build clean in Release. GitHub `Build Verification` passed on the release commit `e49ebf5`. The app and DMG are Developer ID signed, notarized, stapled, and `spctl` accepts the mounted DMG as `Notarized Developer ID`. The live feed at `https://oliverames.github.io/ping-warden/appcast.xml` advertises 4.0.0 build 40000 with a macOS 13.0 minimum. The storefront returns `is_published:true`, `price_cents:1500`, `is_compliance_blocked:false`, and `?wanted=true` redirects into checkout. A live negative-path verify against the real product ID still returns HTTP 404 `success:false`, so the fail-closed path holds against production.

**Left off at**: 4.0.0 is public on the stable channel and the storefront sells. Post-release fixes are committed to `main` for the next release rather than forcing a 4.0.1 prompt: removed a non-functional concurrency guard in `LicenseManager`, dropped the unused `verifiedAt` payload so `LicensePolicy` is a pure function of its inputs, and corrected Settings copy that still called the app free.

**Post-release audit (same day)**: Found that the published product had `is_licensed:false`, meaning Gumroad would have taken $15 and issued no license key, leaving the buyer gated out of the feature they just paid for. Caught at zero sales, so nobody was charged. Neither the public API nor the `gumroad` CLI can toggle license-key generation, so the product was unpublished again to take it out of sale until the dashboard checkbox is on. The audit also cleared the branch-protection question: the `Protect main` ruleset grants the owner `bypass_mode: always` by design, which is what lets `release.sh` push the appcast commit, so the bypass line on every direct push is expected rather than a violation. `Build Verification` passed on all three shipped commits (`e49ebf5`, `df99141`, `dadc4bf`), so the bypass never hid a broken build.

**Open questions**: The widget's license gate still duplicates the 14-day constant because the Core file is not a member of the widget target; nothing catches divergence if the Core value changes. The purchase path is verified only as far as the checkout redirect, since a test purchase would put a synthetic sale record on the live store; the first real key remains the first end-to-end proof.

---

## 2026-09-02 - License-gated Ping Protection, Gumroad product, and public-surface update

**What changed**:

- Introduced the licensed-build model. The repository stays MIT and `LICENSE` is untouched. The prebuilt, signed, notarized app remains free to download; everything except enabling Ping Protection (the AWDL-down feature) stays free. Enabling Ping Protection in the prebuilt app now requires a one-time $15 Gumroad license. Nothing was shipped: no tag, no GitHub release, no `gh-pages` push, no DMG/notarization run.

- Gumroad product created as a draft via `gumroad products create`: **Ping Warden License**, price `$15.00` (1500 cents), permalink `pingwarden`, ID `FmGG0pxyEyzJqp_BG4itFQ==`, landing `https://olivera40.gumroad.com/l/pingwarden`, category Other, tags `macos, gaming`. The live storefront already serves the product. A hidden 100% off offer code [retired donor code] (`T2OE2dj5tyIlBWtWAEi8RA==`, `universal: false`) was added for honoring pre-release Buy Me a Coffee donations via `gumroad offer-codes create --product ... --name [retired] --percent-off 100`.

- Added `PingWarden/PingWarden/Core/LicensePolicy.swift` (pure Foundation, Linux-safe). Policy covers `offlineGraceInterval = 14d`, `grandfatherInterval = 90d`, `canEnableProtection(cachedLicenseValid:lastVerifiedAt:now:grandfatherDeadline:)`, `verifyResponse(_:)` mapping (refunded/chargebacked/subscription `*_at` → revoked, 404 success:false → revoked, 14-day grace boundary inclusive), `normalizeKey(_:)` and `verifyRequest(licenseKey:productID:)` form encoding. Wired as `isGrandfathered` / `grandfatherDaysRemaining` / `grandfatherWindowExpired` on the manager and a `donationConversionEmail = "oliver@ames.consulting"` constant.

- Added `PingWarden/PingWarden/LicenseManager.swift` (`@MainActor final class LicenseManager: ObservableObject, shared`). Stores the license key in the Keychain (service `com.amesvt.pingwarden.license`, account `gumroad-key`, `kSecAttrAccessibleAfterFirstUnlock`), and the cached-valid flag plus last-verified timestamp plus grandfather deadline plus a one-shot `transitionNoticeShown` flag in the App Group defaults (`PV3W52NDZ3.com.amesvt.pingwarden`) so the widget reads the same gate. Verification hits `POST https://api.gumroad.com/v2/licenses/verify` with `product_id` and `license_key` (form-encoded), 15 s timeout, treating 404 as a transportable fail-closed `.revoked` body. `establishGrandfatheringIfNeeded()` runs once per install: if protection was already enabled (`AWDLMonitoringEnabled`) before the licensed build first ran, it writes a 90-day deadline starting that day. Periodic re-verification fires every 6 hours while the app runs (`Timer`, tolerance 300 s) plus on each failed verify `reverify()` path. `onReverificationSettled` callback lets the coordinator disable protection immediately. Product ID is no longer a placeholder — `gumroadProductID = "FmGG0pxyEyzJqp_BG4itFQ=="` — so the live negative-path `echo "BOGUS" | gumroad licenses verify --product ... --no-increment` correctly returns 404 `success:false`.

- Added `Tests/PingWardenCoreTests/LicensePolicyTests.swift` — 25 tests covering grace (13 d valid, 15 d revoked, boundary inclusive), missing timestamps, grandfather windows, refunded/chargebacked/lapsed-subscription responses, disabled/not-found 404s, unparsable bodies, key normalization, and request encoding. Suite grows from 79 → 104 → 101 after the donation-sheet removal.

- Gated enabling in `PingWarden/PingWarden/ProtectionExperienceCoordinator.swift:99` (`setPersistentProtection(true)`) and `startSession` (all latency and Game Mode sessions funnel through these two). Both consult `LicenseManager.shared.canEnableProtection` and, when blocked, set `lastError` with donor wording (`Donated before? Email oliver@ames.consulting`) — wording splits on `grandfatherWindowExpired` vs never-licensed. Added `handleLicenseReverification()` which the manager invokes via `onReverificationSettled`: if protection is active and the license is no longer valid, it turns protection off through `monitor.setProtectionEnabled(false)` and sets the revocation notice. Periodic disables also flow here.

- Gated the Control Center widget in `PingWarden/PingWardenWidget/PingWardenToggleIntent.swift` via a new `PingWardenWidgetLicenseGate.swift`. The widget mirrors the app's `LicenseCachedValid` + `LicenseLastVerifiedAt` + `LicenseGrandfatherDeadline` keys from the same App Group and refuses `desiredState == true` with a new `AWDLError.licenseRequired` (`Ping Protection requires a license...`). Added `defaultsForLicenseGate` accessor in `PingWarden/PingWardenWidget/PingWardenPreferences.swift` to expose the suite without new entitlements.

- Added the Settings License pane in `PingWarden/PingWarden/PingWardenApp.swift`. New `SettingsSection.license = "License"` (`checkmark.seal`, between General and Automation) and `LicenseSettingsContent` (status with `checkmark.seal.fill` vs `seal`, transition-period caption, donor note with `mailto:oliver@ames.consulting` button, Buy… link now pointing to `https://olivera40.gumroad.com/l/pingwarden`, SecureField + Verify with `ProgressView`, `Buy a License...` button). Header `statusCaption` now reads `isGrandfathered → "Full Ping Protection continues free during the transition period."`. When the transition has `isGrandfathered`, the pane shows the moving-to-license explanation, the 90-day `Days remaining`, the donor-honoring paragraph with email button, and a full `Enter License Key` section. When `!canEnableProtection` and not grandfathered, it shows the key entry section plus a `Donated Before?` footer with the same donor wording and mailto. `establishGrandfatheringIfNeeded` + `onReverificationSettled` + `startPeriodicReverification()` are wired in `applicationDidFinishLaunching`, and a one-time `showLicenseTransitionNotice()` window (created once per install via `transitionNoticeShown`, delayed 1 s, with `LicenseTransitionNoticeView`, `licenseNoticeWindow`, and updated `updateDockIconVisibility`/`windowWillClose`) explains the paid-model move when `isGrandfathered` is true. `clearLocalDataForRemoval()` now also calls `LicenseManager.shared.resetForRemoval()`. Tweaked `WelcomeView.onSetup` to consider setup complete even when protection stays off due to the gate, and updated the `finishSetup` message.

- Ripped out the donation sheet in this follow-up pass per the 2026-09-02 instruction. Deleted `PingWarden/PingWarden/DonationPromptView.swift` and `PingWarden/PingWarden/Core/SupportPromptPolicy.swift` (file-system-synchronized groups drop them automatically). Cleaned `PingWarden/PingWarden/PingWardenApp.swift`: `donationWindow` property, `sessionCoordinator.onSessionCompleted` donation hook, `donationWindow` checks in `updateDockIconVisibility` and `windowWillClose`, the entire `showDonationPromptIfNeeded` / `presentDonationPrompt` / `closeDonationWindow` block, and the `donation` DEBUG case; rewrote `supportPingWarden()` and the remaining Donate buttons to open `https://buymeacoffee.com/oliverames` directly without touching preferences. Removed the four donation prefs from `PingWarden/PingWarden/PingWardenPreferences.swift` (`DonationPromptLastSeenVersion`, `DonationPromptDismissedPermanently`, `SupportPromptLastDate`, `SupportOpenedDate` and their accessors). Updated `DashboardView.swift:421` copy from "stays free" to "stays open source" and its Donate button to open the URL directly. Deleted `SupportPromptPolicyTests` from `Tests/PingWardenCoreTests/ProtectedSessionTests.swift` (suite 104 → 101).

- Mirrored the License pane in `PING_WARDEN_3_SPEC.md`. Replaced the `### Donations` section with `### License` (Gumroad verify, 14-day offline cache, 90-day grandfather starting on first licensed-build launch, hidden [retired donor code] 100% code, Settings License pane description, widget cached-entitlement gate, immediate disable on bad license with 6-hour re-verify). Removed the donation prompt bullet from `### Session recap`, updated the `Non-goals` paywall line to `No paywall beyond the Ping Protection license`, and updated the accessibility gate to mention license content.

- Updated public README surfaces (unshipped at the time; released the following day as 4.0.0):
  - `README.md:36` intro: source stays MIT and everything except enabling Ping Protection is free; prebuilt now requires the $15 license and existing users keep protection for 90 days. Added Gumroad badge (`README.md:20`) and a `Pricing` nav link, new install step 4 (buy at Gumroad, enter in Settings → License, 14-day offline, 90-day transition, donor email), new `## Pricing` section with why-a-license rationale, transition and donor terms, rewritten `## Support Ping Warden` and `## License` sections with MIT distinction, 14-day and grandfather details, and the honor path.
  - `PingWarden/README.md:144` settings list + `204` pane docs, expanded `21. License and Pricing` with pricing, verification cadence, rationale, transition, and donor honor note.
  - `PingWarden/QUICKSTART.md:23` inserted `3. Activate your license (prebuilt app)` ahead of turn-on/verify and shifted the latter to 4–5.
  - `PingWarden/PingWarden/DonationPromptView.swift:40` already updated to open-source wording; the follow-up pass then deleted the view entirely, so the stale line no longer ships. `docs/inventory-2026-09-02-licensing.md` captures the full file map and the next-ship checklist.

**Decisions made**:

- Keep source MIT and gate only the prebuilt binary's enable-protection path. The gate is a *prebuilt convenience* paywall, not a source license change, so forking and patching the gate is explicitly allowed. Fail closed on the Gumroad side: an unlicensed copy (and any placeholder product ID before this work) cannot enable protection, including after a 14-day offline grace or a 90-day grandfather expiry. Session and Game Mode enables funnel through the same two coordinator entry points, so no new enable path needs its own gate.

- 90-day grandfather keyed to `AWDLMonitoringEnabled` on first licensed-build launch, not to helper registration date or any calendar release date. Each existing protected install gets 90 days from *its own* first launch of the licensed build, which avoids a global deadline surprise. The transition notice window is shown exactly once per install (`transitionNoticeShown` flag, cleared on uninstall via `resetForRemoval()`), with a re-check after the 1 s delay so quitting before it appears does not set the flag.

- Donor honoring stays manual: donors email `oliver@ames.consulting` before the licensed build's first launch and receive the hidden offer code [retired donor code] (100% off, `universal: false`, `id T2OE2dj5tyIlBWtWAEi8RA==`). Manual honoring avoids minting license keys outside Gumroad and avoids auto-scraping donation receipts. The Settings License pane, the gate error, the new transition notice, and the updated `Support` section all carry the same wording so the promise is discoverable wherever the question could arise.

- Donation sheet removal rather than gating: licensed users still saw the sheet based on session/intervention counts, and gating `showDonationPromptIfNeeded` on entitlement would have kept the view and its tests in the build for no user-visible value. Deleting the view, the `SupportPromptPolicy` and its tests, and the four preference keys is simpler and keeps the menu/Settings/About Donate buttons as the remaining, non-intrusive donation surface.

- Spec mirroring is additive, not a rewrite: the architecture, telemetry, sessions, widget/XPC, and update/release sections stay as they shipped for 3.0. Only the user-experience and non-goals sections now mention the License pane and the grandfather/verify behavior.

**Verification**: `swift test` passed 101 of 101 (was 104 before the donation-sheet deletion: 25 new LicensePolicy tests included) on macOS and Linux via SwiftPM. `xcodebuild -project PingWarden/PingWarden.xcodeproj -scheme PingWarden -configuration Release -destination generic/platform=macOS CODE_SIGNING_ALLOWED=NO` and the `PingWardenWidget` scheme both report BUILD SUCCEEDED. Live `echo "BOGUS" | gumroad licenses verify --product FmGG0pxyEyzJqp_BG4itFQ== --no-increment` returns 404 `success:false` as the fail-closed path expects, and `gumroad offer-codes view T2OE2dj5tyIlBWtWAEi8RA== --product ...` confirms the hidden code. At the close of this entry there was no tag, no `git push`, no appcast or DMG publish, and `gumroad products list` still showed the product as a draft.

**Left off at**: As of the end of 2026-09-02 the licensed build was fully wired and the public docs matched it, with nothing published: the working tree held the licensing files uncommitted, `main` and `gh-pages` were clean, and the Gumroad product was still a draft. All of that shipped the next day; see the 2026-09-03 entry above.

**Open questions**: Whether the remaining Buy Me a Coffee buttons (menu → Support Ping Warden, Settings → Support → Donate..., About → Donate, Dashboard → Donate...) should be kept after the licensed model ships, or should be replaced by Gumroad license CTAs. Also whether the hidden offer code [retired donor code] should be capped (`--max-purchase-count`) or left unlimited for the manual honoring flow.

---

## 2026-08-26 - Cut and publish the 3.1.0 stable release

**What changed**: Released 3.1.0 to the stable channel. The version moved from 3.0.0 to 3.1.0 and build 30000 to 30100 across the four Xcode targets, the app, widget, and helper `Info.plist` files, and the helper's `HELPER_VERSION` define. `RELEASE_NOTES.md` gained a 3.1.0 section covering the persisted protection pause, the GeForce NOW refresh retry, the two idle-power reductions, the console-user XPC gate, Sparkle 2.9.6, and the helper version validation. `release.sh 3.1.0` then archived, signed, notarized, packaged, signed the feed, published the GitHub release, uploaded dSYMs to Sentry, and pushed `gh-pages` commit `8f3866e`.

**Decisions made**: Chose a semver minor rather than a patch because two user-facing features shipped alongside the fixes. Kept the release on the stable channel instead of staging a beta, since the changes are incremental on top of a 3.0 line that has been public since July.

**Verification**: `swift test` passed all 82 tests before the build. The DMG is Developer ID signed under Team `PV3W52NDZ3`, notarized, stapled, and `spctl` accepted as `Notarized Developer ID`; the app inside it carries the hardened runtime. The app, widget, and helper all report 3.1.0 and 30100, with the helper read out of its `__TEXT,__info_plist` section rather than trusted from the source tree. The DMG downloaded from the GitHub release has SHA-256 `5ac5df85...0bff265`, identical to the notarized local artifact, and validates its own staple. Sparkle's `sign_update --verify` accepts the live feed at `https://oliverames.github.io/ping-warden/appcast.xml`, and the enclosure `edSignature` in that feed reproduces exactly when recomputed against the downloaded DMG.

**Left off at**: 3.1.0 is public on both the GitHub release page and the stable appcast. `main` is clean at `cf91843` with the appcast copy committed.

**Open questions**: The update was verified by signature and feed rather than by installing an older build and taking the update through Sparkle's UI. That end-to-end install path is untested for this version.

---

## Earlier history (before 2026-08-23)

- 2026-07-22 - Consolidated four overlapping maintenance PRs into one merge, closed the superseded branches, and fixed mixed CodeQL action revisions; the 79-test suite, PR build, CodeQL, and post-merge build passed.
- 2026-07-22 - Signed the older `appcast-beta.xml` on gh-pages, which lacked a whole-feed signature and would fail Sparkle's `SURequireSignedFeed` check for beta users; kept signed-feed enforcement on, no rebuild needed; `e2bd556`.
- 2026-07-13 - Published stable v3.0.0 (build 30000, macOS 13 minimum): one persistent Ping Protection menu control, Latency Sessions in the dashboard, 79-test core suite, and a fix for a Bash 3.2 empty-array expansion failure in `release.sh`. Decisions: protection and measurement stay separate; windows use default sizes plus scrolling so actions never depend on monitor height; the widget stays unsandboxed by design. A real 2.4.3 client (Sparkle 2.8.1) installed 3.0.0.
- 2026-07-03 - 2.5.0 reliability audit (~30 files) across helper, XPC, widget, monitoring, and release tooling, including awdl0 restore through a direct ioctl fallback, XPC retry reset only after a validated helper response, and a Linux-portable core with a `linux-core-tests` CI job (tests 33 to 41). Decision: the widget toggle shows user intent, not effective state. Delivered through PR #34.
- 2026-06-22 - 2.4.3 fixed a fatal `NSGenericException` Update Constraints loop (Sentry issue 7567835289) caused by the hidden `Settings` scene's `EmptyView().frame(width: 1, height: 1)`. Hard-won fact: releases run headless with `xcodebuild archive CODE_SIGNING_ALLOWED=NO`, because `notarize.sh` re-signs with Developer ID and App Groups on a non-sandboxed app need no profile. Fix `e681eec`; appcast gh-pages `0e60f0d`, main `50eaa87`.
- 2026-05-27 - 2.4.0 cycle: accessibility pass (adaptive `LatencyPalette` passing WCAG AA, `@ScaledMetric` hero fonts, `AXChartDescriptor`), Liquid Glass gated on macOS 26 with one `GlassEffectContainer` for the six dashboard cards, a Sparkle beta channel (`BETA_CHANNEL=1`, `appcast-beta.xml` created on gh-pages as `137ed68`), and General/Automation settings moved to native `Form`. Decision: the macOS 13 deployment target stays.
- 2026-05-19 - v2.3.4: removed `notarize.sh` and `release.sh` from shipped app resources, added `LSApplicationCategoryType`, tightened "Ping Protection" copy, and fixed a Dashboard interventions-card state mismatch.
- 2026-05-19 - v2.3.3: fixed the Settings titlebar overlap, deferred Sparkle startup until the helper is registered, and hardened `release.sh` (no GPG signing on the gh-pages commit, App Store Connect API-key notarization accepted, explicit GitHub release `--target`).
- 2026-05-18 - v2.3.2 stability beta: wired the helper and widget `Info.plist` and entitlements into their targets (a Release build had produced a widget `.appex` with `CFBundlePackageType=APPL` and no `NSExtension`), and hardened XPC reconnects and PingMonitor probe gating.
- 2026-05-18 - v2.3.1 prep: added Sentry crash reporting to the main app only (helper not instrumented; token at `op://Development/PingWarden Sentry API Token/credential`; `enableNetworkBreadcrumbs = false` keeps probe hostnames out of payloads), then made it on by default with `enableAutoSessionTracking = false`. Enabled Sentry project IP scrubbing, added `scripts/render_release_notes.sh` and `CRITICAL_UPDATE=1` to the release flow, and moved Advanced settings to native `Form`; commits `f9413ff` through `566df00`.
