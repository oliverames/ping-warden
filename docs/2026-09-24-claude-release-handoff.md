# Claude release-readiness handoff

Author: Oliver Ames  
Date: September 24, 2026  
Repository: `oliverames/ping-warden`  
Local checkout: `/Users/oliverames/Developer/Projects/ping-warden`

## Requested outcome and publication hold

Review the prepared Ping Warden changes before a new release reaches existing users or Product Hunt. This is an established paid app. Focus on regressions introduced since v4.2.0, remaining acceptance checks, and release readiness. Do not revalidate the business or invent sales figures.

Oliver requested this handoff before publication. Do not cut a release, publish update feeds, update Gumroad buyer downloads, deploy release notes, or submit Product Hunt until Oliver resumes publication after review. The existing installed app, licenses, helper, preferences, network configuration, and system accessibility settings were preserved.

## Current source and release candidate

The latest published release remains v4.2.0, build 42000. Verified September 24 through the GitHub release API, app/helper/widget plists, and both current appcasts. The installed /Applications/Ping Warden.app metadata also reports 4.2.0/42000. This read-only check does not establish signed-host interaction acceptance. No v4.2.1 tag existed when checked.

Candidate: **4.2.1, proposed build 42100**, following the current 4.2.0/42000 and 4.1.9/41900 sequence. Version carriers and feeds remain unchanged. [Draft release notes](release-4.2.1-draft.md) are ready and extract correctly with the maintained renderer. They are deliberately outside RELEASE_NOTES.md: `.github/workflows/site.yml` deploys the website when that file changes on main. Do not publish future release notes accidentally.

Relevant source commits, all pushed to main:

- 8bad3e7: intervention counters and recaps describe attempts.
- e315918: Help observes the existing What's New offer.
- 205bc5f: chart accessibility wording and actor transition for settings navigation.
- a344c0c: process-owned crash-reporting relaunch state, host validation, accurate reminder text, guarded Return submission for license fields, native content backgrounds, and one prominent transition action.
- fa2819e: Targets uses the same grouped settings form as General, retaining its tab and functions.
- 8d13d34: Darwin/Glibc conditional import restores Linux compilation of target validation. No validation or persistence logic changed.

Launch preparation commits are 5839f30 and 5905784. Read current Git status, worktrees, and recent history before editing. The other issue-review task owns no pending Targets edits at handoff. Coordinate any newly active writers.

## Evidence and boundaries

- Production native Xcode builds passed, including after the platform-import correction.
- All 26 existing actual-source presentation checks passed.
- An independent reviewer found no actionable regression in the two-file Targets diff. Eighteen focused storage, settings-correction, and telemetry-demand tests passed with zero failures or skips.
- The same reviewer approved the platform-import fix. Thirteen focused storage and host-validation tests passed on macOS with zero failures or skips.
- [Build Verification for 8d13d34](https://github.com/oliverames/ping-warden/actions/runs/36041456305) passed, including the complete app build, bundle validation, macOS tests, Linux tests, and shell checks.
- [CodeQL for 8d13d34](https://github.com/oliverames/ping-warden/actions/runs/36041456309) was still running when this document was prepared. Recheck its final status before publication.
- At the subsequent image-correction wrap-up on September 24, [Build Verification for ba9e285](https://github.com/oliverames/ping-warden/actions/runs/36042729444) had passed. CodeQL remained in progress for both 8d13d34 and [ba9e285](https://github.com/oliverames/ping-warden/actions/runs/36042729454).
- [Native preview record](2026-09-24-targets-native-layout.md) contains light/dark, minimum-size, and add-form captures. A duplicate port label caught in the preview was fixed and rendered again.

Previews used isolated identifiers, in-memory preferences, a separate file root, and inert external services. They are not installed-app or live-interaction evidence. Computer Use failed initialization with error -10005. The other issue-review task also encountered stale accessibility references during its interaction attempt. Do not infer a product bug from those tool failures or claim keyboard acceptance was completed.

## Finish the review

1. Recheck the exact source and current GitHub checks. Review the delta from v4.2.0 and compare the draft notes with the final behavior.
2. Complete the narrowly affected interaction checks in a safe isolated host: target and interval pickers, add/cancel/save, Return/Escape, invalid-input focus, saved custom-target persistence, and selected-target fallback after removal. Preserve the tab and current user data. Track results in [#90](https://github.com/oliverames/ping-warden/issues/90).
3. Review the existing signed-host acceptance in [#78](https://github.com/oliverames/ping-warden/issues/78), including What's New, real release-link behavior, installed preference persistence, embedded helper/widget, and updater surfaces. Existing [#64](https://github.com/oliverames/ping-warden/issues/64) records game/Ethernet checks, not a newly demonstrated regression. Give each remaining check a clear disposition without treating all historical items as new defects.
4. Report release readiness and remaining decisions to Oliver before publication. Keep independent review conclusions separate from observed installed-app behavior.

## Release workflow after publication is resumed

Use the installed `ames-dev-workflows-local:project-release-runbooks` skill and its Ping Warden reference. Re-read the current scripts. Native Xcode tooling is preferred. Do not copy old build-number examples from the runbook blindly; confirm a monotonic build against both feeds.

Update all current project/target version settings, app/helper/widget Info.plist values, helper HELPER_VERSION, and the top RELEASE_NOTES.md section together. Use Xcode's native build-setting tools for project settings. Preserve the New since 4.0 section. Regenerate Site/public and run the maintained site checks before committing, with timing coordinated so release-note publication does not precede the approved release.

From a clean, tested, committed, pushed source, the maintained release command is `cd PingWarden/PingWarden && bash release.sh 4.2.1 ../../RELEASE_NOTES.md`. This is a publishing command, not a dry run. It archives, signs, notarizes, creates the DMG, publishes GitHub/Sparkle/Sentry, and updates Gumroad buyer delivery. Do not bypass its required checks or replace it with an improvised release path. Credentials stay in the existing Keychain/1Password routes and out of output.

Verify the actual published DMG, embedded versions, signatures and notarization, both signed feeds, website release page, and buyer delivery. Commit any appcast copies that the release script leaves modified. Record artifacts and evidence in #78 and WORKLOG.md.

## Product Hunt after release readiness

Use [the launch record](2026-09-24-product-hunt-launch.md) and [listing JSON](product-hunt-2026-09-24/listing.json). Lead with the real `Site/public/dashboard-v4.png` screenshot. Oliver's final image correction is complete: `01-cloud-gaming.png` now shows the supplied dashboard inside the laptop display. This generated composite supplements the unchanged original screenshot. The final graphic is 1622 × 970 and below 3 MB. Never use the isolated review captures as released product imagery.

[Issue #93](https://github.com/oliverames/ping-warden/issues/93) tracks the remaining submission. No draft, schedule, or published launch exists. Authenticated maker access, duplicate/draft checking, preview verification, and a launch date remain. September 25 was suggested earlier but never selected. Refresh the copy's verified release metadata after any new app release. Submit only after publication resumes and record the actual resulting URL and status. No outreach or vote solicitation was authorized.
