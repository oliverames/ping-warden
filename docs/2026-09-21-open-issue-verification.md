# Open issue verification, September 21, 2026

## Website rating and public claims

For [#87](https://github.com/oliverames/ping-warden/issues/87), removed the unmaintained aggregate rating from the homepage schema. The three attributed testimonials and the free-dashboard and $15-license offers remain. Rebuilding updates the structured-data hash in the content security policy. All 12 generated structured-data scripts match the 12 allowed hashes.

For [#78](https://github.com/oliverames/ping-warden/issues/78), the README, setup guide, and technical guide now explicitly state that starting a Latency Session requires a license or an active transition. Game Mode's Ethernet rule applies to automatic activation and preserves manual protection intent. Remaining unmeasured timing promises were removed from the maintained guides. Counter explanations now describe intervention attempts rather than confirmed blocks or measured spikes prevented. The retired `landing.html` and dated historical records are outside the maintained website build.

Verification: the site builds successfully and passes checks for 13 HTML pages, structured data, local links and anchors, 12 sitemap URLs, and both worker tests. The 21 existing What's New and Game Mode policy tests pass.

## Isolated What's New verification

A temporary native fixture compiles the actual `WhatsNewPolicy.swift` with unchanged copies of `prepareWhatsNewOffer`, `openWhatsNew`, and the native menu-construction branch from `PingWardenApp.swift`. Preferences are in memory, the bundle version is injected, and URL opening is captured. No production defaults, license service, helper, or app lifecycle runs.

All 24 checks pass. They cover first-launch baseline, the prior-version offer, native menu selector dispatch, the `#ping-warden-420` URL, acknowledgement, removal of the offer, Combine publication, persistence of an unopened offer, and no repeated offer after acknowledgement. The release-notes anchor exists in the generated site.

The extracted blocks were compared with the current source byte for byte. SHA-256 values:

- `prepareWhatsNewOffer`: `284e93c04a4236250eed9d469c9639a5c3a55fc993d58693a87248966c44967b`
- `openWhatsNew`: `b3d08657c007f483986e9431c0e72b969a6cad15afdbdb41e5d819194470eddc`
- Native menu branch: `cbbaff29f9dc9e2a3b773a315f4134005ecbd2a6fa14a1a36b5adf0367a8bf73`

This does not establish the full signed-app launch lifecycle, real App Group persistence, or SwiftUI Help-menu interaction. Those checks remain distinct from this source-level result.

## Isolated Settings and About review

Fourteen captures render the actual unchanged General Settings and About views with inert service dependencies. Licensed and unlicensed states were checked. General detail-pane content was rendered at 780 by 700, 780 by 1000, and 580 by 520 points, including scrolled minimum-size captures. About was rendered at 420 by 480 and 380 by 420 points.

No donation buttons appear in these views. About shows the appropriate Licensed or Buy a License text, resource links, and credits. General's footer remains reachable at the minimum size. Root independently inspected representative captures. The fixture exited normally after rendering.

These are view-content checks on macOS 27.2, not signed-app interaction checks. The Settings sidebar, saved frame, toolbar, and window decorations were not reproduced. The temporary title beginning “Isolated view fixture” belongs only to the test host. The production window title is “Settings.” Real licensing, helper operations, updates, and network changes were disabled in the fixture.

## Real-game validation

[#64](https://github.com/oliverames/ping-warden/issues/64) remains a field-validation gap. The read-only readiness check found a validly signed installed 4.1.8 build, qualifying game clients, active Wi-Fi, and no connected Ethernet path. A license or active transition was not available in the checked app state. No foreground game session was running. Oliver confirmed that only Wi-Fi is available for now.

The system permission database showed no Screen Recording grant, but the user permission database could not be read. Therefore runtime operation without that permission still requires observation. No real-game engagement, focus-loss restoration, or Ethernet-skip result is claimed from the unit tests or fixtures. Completing the issue requires a licensed signed-app session and connected wired hardware.

## Publication and dependency merges

The website fixes were published in `f5f47f6`. Its [Website workflow](https://github.com/oliverames/ping-warden/actions/runs/35633824419) passed, and fresh browser inspection confirmed the removed rating, retained testimonials, and corrected overview, setup, and technical pages. #87 was closed with this evidence. A direct Python HTTP request received 403; browser verification succeeded.

[PR #75](https://github.com/oliverames/ping-warden/pull/75) and [PR #86](https://github.com/oliverames/ping-warden/pull/86) were reviewed and merged as `31d6a26` and `cdb99e8`. Integration retained markdown-it 15.0.2 and Wrangler 4.135.0 in both the manifest and lockfile. The only merge conflicts were the shared dependency declarations. Checks confirmed no duplicate JSON keys, matching resolved versions, zero reported npm vulnerabilities, passing website tests, unchanged generated pages, and successful Wrangler packaging.

The [exact-commit deployment](https://github.com/oliverames/ping-warden/actions/runs/35634307226) used Wrangler 4.135.0 and published Cloudflare version `297ccb0d-fae7-481a-a1ff-2420a707ec7f`. A fresh browser check after deployment confirmed the correct homepage. GitHub reports both PRs merged and no remaining open PRs. Linux tests, shell lint, and website/tooling CodeQL passed. The macOS build and Swift/Objective-C analysis were still running at this checkpoint. GitHub accepted the maintainer push while reporting pending-check and merge-history rule bypasses; no history rewrite was performed.

## Remaining issues

#78 retains the full signed-app interaction checks. Approval to replace the installed 4.1.8 copy with verified 4.2.0 and temporarily exercise/restore the release-notes preference was requested. Isolated results do not establish those acceptance criteria.

#64 remains open for the licensed real-game and Ethernet observations described above. Oliver confirmed Wi-Fi only is available now.

The UI review exposed a separate semantic defect, tracked in [#88](https://github.com/oliverames/ping-warden/issues/88): several app labels and shared recaps describe intervention attempts as successful blocks. An existing fault-injection helper test confirms that a failed write still increments the counter. The fresh helper run passed all 162 checks. Per the incidental-bug workflow, the issue records affected surfaces and verification steps without starting that separate app change.


## Later full-app UI review

The subsequent [macOS 27 UI review](2026-09-21-macos27-ui-review.md) preserves the evidence and limits above while adding a full isolated application host. It confirmed the native title/sidebar composition and reproduced a missing SwiftUI Help-menu release-notes item that the earlier method fixture did not cover. [e315918](https://github.com/oliverames/ping-warden/commit/e315918) fixes that observation boundary. The item now appears and disappears after acknowledgement in the full isolated app. Original signed-app acceptance remains open in #78.

The separate counter wording issue #88 is now fixed in [8bad3e7](https://github.com/oliverames/ping-warden/commit/8bad3e7) and closed. Its focused tests, helper tests, universal build, and minimum-width renders pass. New review findings are tracked in #89, #90, and #91. #64 still requires the real-game and wired observations described above. No installed app was replaced and no new release was published during this later review.
