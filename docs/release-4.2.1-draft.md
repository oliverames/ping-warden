<!-- Prepared by Oliver Ames on September 24, 2026. Draft only, not published.
Candidate version: 4.2.1. Proposed build: 42100, following the current 4.2.0/42000 and 4.1.9/41900 sequence.
Version carriers, RELEASE_NOTES.md, generated website pages, appcasts, tags, and release assets remain unchanged.
Move this section into RELEASE_NOTES.md only after the release review and publication hold are resolved. -->

# Ping Warden 4.2.1

This update brings Targets into line with the other settings pages and fixes several settings, keyboard, and accessibility details.

## Improvements

- Targets now uses native grouped settings, with consistent section headings, row spacing, and controls. The Targets tab and custom-server controls remain available.
- Dashboard cards use native content backgrounds that match the app's settings.
- Intervention counters and shared session recaps describe attempts to pause AWDL more clearly.

## Fixes

- The crash-reporting “Relaunch Required” state remains visible when you leave Advanced settings and return. Accessibility tools can also read that state.
- Custom servers reject complete URLs and show an error in the form. Enter a hostname or IP address, with its port in the separate Port field.
- Pressing Return in a license-key field starts verification, with the same empty-field and busy checks as the Verify button.
- Transition reminders describe only the reminders that remain. The final reminder no longer promises another one.
- The transition notice has one primary action, while retaining both purchase and existing-key options. Its text now follows one centered layout.
- The Help menu observes changes to the What's New offer, so the item appears and clears with its current state.
- The chart's accessibility summary identifies latency spikes without describing them as protection events.

## New since 4.0

- Game Mode can detect a recognized frontmost game without Screen Recording permission. Optional Screen Recording access also enables fullscreen-window detection. Automatic activation skips Ethernet and rechecks when the network changes.
- Latency Sessions record a protected game or call and produce a local recap. Starting a session requires a license or an active transition. The dashboard, diagnostics, and past recaps remain free.

## Updating

Use **Check for Updates**, or download the current DMG and replace the app in Applications. Version 2.0.5 and earlier require a manual download.

Ping Protection, including starting a Latency Session, requires a one-time $15 license or an active transition. Updates preserve eligible existing users' original 90-day transition deadline. The dashboard, diagnostics, and past session recaps remain free. The source remains MIT-licensed.
