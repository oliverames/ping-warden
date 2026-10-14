# Contributing to Ping Warden

Bug reports and focused pull requests are welcome. Ping Warden includes a privileged helper, so changes that cross the app-to-helper boundary need especially careful review.

## Before writing code

Open an issue for a large feature or architecture change. For a small bug fix, a pull request with a clear reproduction is enough.

Keep macOS 13 compatibility unless the issue explicitly changes the supported versions. User-facing language should say "Ping Protection" rather than "AWDL monitoring."

## Build and test

Run the core test suite from the repository root:

```bash
swift test
```

Build the complete unsigned Release app:

```bash
xcodebuild build \
  -project PingWarden/PingWarden.xcodeproj \
  -scheme PingWarden \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

For this project, test helper registration with a Release build copied to `/Applications`. Builds launched from Xcode are suitable for UI work, but they do not exercise the project's helper registration flow.

Add focused tests for behavior that can run without AppKit or root privileges. For helper, XPC, signing, packaging, or update changes, include the exact manual validation you performed.

## Crash and error reporting

`CrashReporter.swift` owns the Sentry configuration, and `Core/DiagnosticReporting.swift` defines everything an event may carry: enum problem names and breadcrumbs, allowlisted error domains, numeric codes, and the rate limit. Keep new reporting inside those closed sets. Never put a host, target, address, network name, license key, or free-form error description in an event. If what Ping Warden sends changes, update the disclosure in the same pull request: the Advanced toggle caption and hint in `PingWardenApp.swift`, the Welcome footnote in `WelcomeView.swift`, the README privacy section, `PingWarden/QUICKSTART.md`, `Site/home.html`, `landing.html`, and `docs/gumroad-product-description.html`.

Run the reporting tests with `bash scripts/test_crash_reporter.sh`. It compiles the production reporter against a fake SDK that never sends anything, once as Release and once with `DEBUG`.

To prove delivery end to end, build Debug and launch it with `--sentry-test-event`. Debug builds report under the `development` environment, so the event and its session stay out of production data. A Debug launch uses the same bundle identifier and preferences as the installed app and connects to its registered helper, so quit the installed copy first. Then check receipt with the read-only API token (the token is read from 1Password and passed on standard input, so it never appears in the process list):

```bash
op read 'op://Development/PingWarden Sentry API Token/credential' \
  | sed 's/^/Authorization: Bearer /' \
  | curl -sS -H @- "https://us.sentry.io/api/0/organizations/ames-consulting-llc/events/?project=4511410888704000&dataset=errors&environment=development&query=delivery_test:true&field=id&field=title&field=timestamp&field=release&statsPeriod=24h"
```

One row titled `Delivery verification` proves the event arrived. Replace the path with `sessions/?project=4511410888704000&field=sum(session)&groupBy=session.status&environment=development&statsPeriod=24h&interval=1d` to confirm the session was counted. `sentry-cli` 3.4.2 can't list organizations, so pass `--org ames-consulting-llc --project ping-warden` explicitly if you use it instead.

## Pull requests

Keep each pull request to one logical change. Explain the user-visible result, list the tests you ran, and call out changes to the privileged helper, XPC authorization, entitlements, diagnostics, or update delivery.

Do not commit credentials, private signing keys, provisioning profiles, notarization data, exported diagnostics, or personal network information.

## Linear release reporting

See [Release Reporting](Release%20Reporting.md) for the delivery checks, scoped
credential reference, AME commit references, and reporting-only retries. Linear
records a verified delivery after the existing publisher completes.
