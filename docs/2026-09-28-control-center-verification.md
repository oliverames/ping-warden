# Control Center sandbox verification

Author: Oliver Ames

Date: September 28, 2026

## Result

The #92 implementation is committed on main as `7f87bbb`. The extension is sandboxed, retains its App Group, and can look up exactly the existing authenticated helper endpoint. A signed isolated fixture loaded and enabled protection through the real helper, including with its containing app initially quit. The installed production app was preserved. Nothing was notarized or published in this session.

Oliver approved resuming #92 implementation and creating an isolated app with a synthetic valid license. This supersedes the earlier implementation hold. The release hold remains in place under #99.

## Change and rationale

`PingWardenWidget.entitlements` enables App Sandbox and adds only `com.amesvt.pingwarden.xpc` to `com.apple.security.temporary-exception.mach-lookup.global-name`. Helper authentication, the helper plist, licensing, application preferences, and intent code are unchanged.

Apple documents the [Mach lookup exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html). [Apple DTS guidance](https://developer.apple.com/forums/thread/808940) supports a narrow exception for a directly distributed app when the service cannot be reached otherwise. This is the previously proposed option 1, including its explicit temporary-exception tradeoff.

The earlier service-renaming experiment did not update the existing helper registration. Retaining the endpoint avoids requiring users to approve a replacement helper registration. The earlier app-routing spike failed for its tested variants, including after notarization. Review found that `.background` plus `.main` was defined but not tested independently of the foreground-capable variants. The evidence therefore does not establish that every app-routing design is impossible. It does support keeping this fix narrow, without making an unverified routing redesign a release dependency.

Release validation parses the signed entitlement dictionaries for both arm64 and x86_64. It requires the exact sandbox Boolean, one App Group, and one helper service. It rejects additional security entitlements and unreadable signatures. Signing-identity metadata remains allowed.

## Build and automated evidence

- Native Xcode Debug build succeeded without reported warnings.
- Universal Release build succeeded without warnings. The canonical sign-only workflow produced a Developer ID candidate with hardened runtime.
- Full artifact validation passed, including both signed architecture slices. PlugInKit accepted the candidate after its containing app was registered.
- All 21 release-tool tests passed. They include eight widget-entitlement tests covering missing, malformed, expanded, and architecture-specific permissions and extraction failures.
- All five license-gate parity tests passed, without skips. Bash syntax, ShellCheck, Python syntax, and whitespace validation passed.
- A separately sandboxed diagnostic using unchanged production seal and widget-gate code accepted a synthetic valid seal and rejected tampered, expired, and unlicensed cases. No real license state was written.
- An independent source review found no additional blocker in the change or fixture isolation.

## Isolated live test

Host: macOS 27.2, build 26B5091g. The live runtime was Apple silicon. Intel was built and signed but not run.

`scripts/prepare_control_center_fixture.py` creates a scratch project outside the checkout. It uses the separate app `Ping Warden 92 Test`, bundle/helper namespace `com.amesvt.pingwarden92test`, and corresponding App Group, XPC service, restore marker, preferences, and session-history directory. It seeds a sealed synthetic license while preserving the widget gate. It removes license network requests, Keychain operations, Sentry startup, and Sparkle construction only from the scratch copy. The helper's network behavior remains real.

The fixture was signed with the canonical release workflow and installed alongside production. Oliver completed its Login Items approval and added its control. Computer Use could inspect the control's accessibility state, but later simulated clicks did not reliably invoke it and screenshots omitted its rendering. Oliver performed the decisive on-state clicks. Interface flags and widget logs verified the outcomes independently.

| Check | Observed result |
| --- | --- |
| Gallery and registration | Signed sandboxed extension accepted and control added by Oliver. |
| Shared license seal | Widget accepted the fixture's sealed valid cache. No license-gate bypass was added to widget code. |
| Control on, app running | At 10:06:54 EDT, widget logged authenticated enable and success. `awdl0` lost UP, app showed Active, and control accessibility value was on. |
| Control off | At 10:01:01 EDT, widget logged authenticated disable and success. `awdl0` returned to UP and the control displayed off. |
| Repair while on | Fixture reported “Helper Is Responding” and “Ping Protection is on.” `awdl0` remained down. This exercised an already responsive helper. |
| Hide older menu icon | Legacy Hide Menu Bar Icon removed the app's status item. The system control remained present and on. The pending Control Center Only mode was not part of this build. |
| Ordinary quit while on | App process exited, `awdl0` returned to UP, shared effective state became false, and the control updated to off after its refresh. Saved ongoing-protection intent remained true. |
| Control on, app quit | Before the click no fixture app process existed. At 10:10:30 EDT, widget logged successful enable, its containing app launched, and `awdl0` went down. Control accessibility value became on. Silent launch behavior for PR #95 was not assessed by this test. |
| Final Off and removal | App Off restored `awdl0` to UP. Prepare to Remove unregistered the fixture helper, cleared fixture state, and quit. |

No forced root-level interface re-raise, logout/login, actual game, Ethernet handoff, or crash reproduction was performed. These remain distinct from the passing checks above.

## Gray capsule and duplicate icons

Oliver reported that the gray capsule stayed visible around the menu-bar control when protection was on and the pointer was elsewhere. Protection worked during that observation.

The widget supplies a `ControlWidgetToggle`, symbols, labels, and blue tint. It draws no capsule. Apple explains that [controls adopt the appearance of their system location](https://developer.apple.com/videos/play/wwdc2024/10157/). Native documentation and SDK inspection found no background-removal modifier for `ControlWidgetToggle`. The retrieved documentation does not explicitly describe this particular macOS capsule, so its exact styling is an inference about system presentation, not a documented guarantee. No cosmetic workaround was added.

The adjacent plain icon comes from the app's `NSStatusItem`, a separate API. The existing Hide Menu Bar Icon preference removed that duplicate in the fixture. PR #95 adds an explicit Control Center Only choice that also hides the Dock icon while preserving older users' preferences. Adding a control alone does not currently select that app preference.

## Cleanup and remaining work

The fixture helper was absent from launchd after removal. Its control and extension registration were removed. The installed fixture app, generated App Group, widget container, diagnostic sandbox container, and fixture preference file were moved to the Trash. AWDL ended UP. SHA-256 comparisons confirmed unchanged production app executable, helper executable, app preferences, and App Group preferences. The production helper remained not running with its original registration version and run count.

Local build evidence remains in `/tmp/pingwarden-92-candidate`, `/tmp/pingwarden-92-fixture`, and the focused `/tmp/pingwarden-92-*` logs. These are temporary evidence paths, not release artifacts. The reproducible fixture preparation is committed in the repository.

- #92 remains open until delivery through the approved release process. macOS 26 runtime acceptance remains untested.
- #96 and PR #95 retain their combined-build and icon-free-mode acceptance checks. This fixture does not establish those checks passed.
- #78 retains forced interface re-raise, accessibility/appearance, and applicable live-game checks. Its Off, ordinary quit restore, and responsive-helper Repair checks now have signed isolated-fixture evidence.
- #101 tracks B10, stale control display after an unexpected app termination. The entitlement fix does not change that code. Crash reproduction was not repeated here.
- #99 retains the delta audit, release notes, notarization, distribution checks, and Oliver's publication approval.
