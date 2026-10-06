# Ping Warden Capture Review

Author: Oliver Ames
Date: October 6, 2026

A separate persisted-data capture tool now builds and signs under the former Apple team. It does not replace or launch Ping Warden, contact its privileged helper, read Keychain credentials, change licensing policy, or publish an update. Every output retains the original installation and remains `notReady` for migration.

## Source and Packaging

The standalone project is `PingWarden/PingWardenCapture/PingWardenCapture.xcodeproj`, with scheme `PingWardenCapture`. Its explicit source list contains four capture files and eight existing or extracted model files. It has no production app, widget, privileged-helper or package dependency. Existing app source membership includes the extracted credential observation types automatically. The existing license harness received only the corresponding source-list and provenance adjustment, without execution or new cases.

The wrapper identifier is `com.amesvt.pingwarden.capture`, version 0.1.0 (1). Both Intel and Apple silicon slices use the former team's exact Developer ID certificate, hardened runtime and a secure timestamp. Its only access entitlement is the existing team-prefixed group `PV3W52NDZ3.com.amesvt.pingwarden`; the sandbox remains disabled as in the source app. No debugging entitlement or hardened-runtime exception is present.

Native Xcode built the universal capture tool successfully in 4.918 seconds after two pointer-conversion errors were corrected. The full existing Ping Warden app also built successfully in 6.85 seconds after the shared-source extraction. Strict deep signature verification, both architectures, exact certificate and entitlement checks passed. No app test suite ran. The capture tool has not been notarized or distributed.

## Capture Contract

The command requires explicit absolute paths for `--source-app`, `--shared-preferences`, `--standard-preferences`, `--recaps` and `--output`. The three stores must match the current account's exact expected locations. A selected app must have a valid original-team Developer ID signature, original identifier and group, and version metadata of 4.0 or newer. Validation does not launch that app.

The tool reads only approved preference keys and the original completed-session bytes. Missing values stay distinct from empty values and unavailable stores. Any shared or license key in the standard domain stops capture because fallback provenance is unresolved. Wrong types, malformed records and detected changes stop capture before output.

Each file receives bounded descriptor reads, no symlink traversal, and complete path revalidation. Two matching passes include directory identities and present or absent file observations. This detects observed changes but is not an atomic cross-process snapshot. A selected app's version does not prove it last wrote the stores. Active-session state remains explicitly unobserved.

Output must be a new directory outside every source store and both application wrappers. Filesystem identity checks cover case aliases. The new directory and files receive verified owner-only modes and empty extended access-control lists before payload writes. Existing paths are never overwritten. A failed write can leave partial output for deliberate review; it never automatically deletes paths. Success is reported only after both files are written and synchronized.

The receipt binds source metadata, file hashes and observation times to the snapshot. It records unobserved credentials, markers, device identity, helper state and source writer. Cached time-window claims retain their original dates and do not establish paid authorization. No license verification or seal generation occurs.

## Review and Remaining Work

Independent source review found four issues in the initial draft: case-alias output paths, inherited access rules, source ancestor replacement and cleanup by filename. All were corrected and independently re-reviewed with no remaining findings in that scope.

Build and signature checks do not establish runtime filesystem behavior or customer continuity. Unavailable source storage remains a blocking result, never a fresh-install assumption. The source app and its licensing service, updater trust, data and helper remain unchanged. Credentials, active-session finalization, reliable handoff freshness, import and rollback, and updater routing still need implementation or verification before a live account transition.

The hard requirement remains unchanged: Ping Warden 4.0 and newer must continue working. The tool does not authorize a cutover. Remaining work stays in [issue 109](https://github.com/oliverames/ping-warden/issues/109).
