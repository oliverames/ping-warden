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
