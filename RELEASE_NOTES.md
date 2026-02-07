# Ping Warden 2.1.0

## Major improvements

- Added latency spike timeline with AWDL intervention markers.
- Added one-click diagnostics export to Desktop.
- Added menu bar quick actions to pause/resume blocking quickly.
- Expanded target presets and implemented auto-select nearest endpoint by baseline latency scan.
- Improved Game Mode auto-detect restore behavior to return to exact prior user state.
- Hardened widget toggle behavior so start/stop works when the app is not already running.

## Reliability and architecture

- Added effective monitoring state propagation across app and widget.
- Improved XPC reconnect behavior and state reassertion after reconnect.
- Centralized Control Center capability checks with macOS 26+ gating.
- Refactored ping statistics and reconnect policy into core testable utilities.
- Added monitor observer/state store cleanup to avoid callback overwrite issues.

## Tooling and release

- Added CI smoke checks for core logic.
- Added CI validation for appcast XML and cross-target version consistency.
- Strengthened release script validations for appcast and version matching.
