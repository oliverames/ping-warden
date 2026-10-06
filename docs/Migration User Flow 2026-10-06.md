# Ping Warden Migration User Flow

Author: Oliver Ames

Date: October 6, 2026

Status: Proposed product flow. The migration is not released or fully implemented. The online-check requirement still needs Oliver's decision. All releases remain held until he verifies the candidate.

## What One Online Check Means

For an affected paid installation, the migration would verify the customer's existing license before switching to the new app. It would not require another purchase. The initial proposed flow asks the customer to enter their existing key because automatic access to the former app's saved key is not yet established. The customer can find the key in their original Gumroad receipt email. Offer help finding it if that email is unavailable, without suggesting another purchase. [Existing license instructions](https://github.com/oliverames/ping-warden/blob/bb4d519/README.md#1-get-the-app).

This addresses a specific historical gap. Version 4.0.0 stored its paid status and verification date as editable local settings. It saved the key, but no independently verifiable license receipt. Those settings cannot safely authorize a new installation by themselves. Version 4.0.1 introduced a local integrity seal. Eligibility must therefore inspect actual stored evidence, rather than assume every 4.x installation is affected.

"One" means one successful check for a completed migration attempt. An unavailable service, incorrect key, canceled attempt or interruption before accepted state is saved may require another attempt. It does not mean one internet request for the life of the product. Existing checks at launch and roughly every six hours while running continue afterward. A valid paid cache supports up to 14 days offline from its last successful verification, subject to the existing integrity and clock checks. The migration request should reuse the current verification request, including its instruction not to increment license-use counts. [Current verification implementation](https://github.com/oliverames/ping-warden/blob/bb4d519/PingWarden/PingWarden/LicenseManager.swift#L340), [Current policy](https://github.com/oliverames/ping-warden/blob/bb4d519/PingWarden/PingWarden/Core/LicensePolicy.swift).

Until migration can finish, the original app stays installed and follows its existing rules. The migration must not clear its settings, reset a licensing deadline, consume a transition marker or disable its protection merely because a new check failed. The original app can still make its own normal licensing decisions.

## Main Customer Journey

1. **Learn about the transition.** The customer sees an update notice or downloads migration instructions from the existing distribution channel. Explain the account transition briefly: "Move to the updated Ping Warden while keeping your settings and session history." Offer **Continue** and **Later**. Do not tell them to uninstall or drag a replacement over their working app.

2. **Check the existing installation.** The migration identifies the installed version and checks whether settings, history and licensing can be carried over. The original app remains the only protection controller. If required information is missing or inaccessible, show the specific problem and leave migration pending. Do not silently start fresh for a 4.0+ user.

3. **Confirm licensing when needed.** If the receiving app can validate and preserve the existing license evidence and credential access, continue without an extra migration-only prompt. If an affected paid installation cannot establish that evidence, show: "Enter your existing Ping Warden license key to continue. You won't need to purchase again." Offer **Verify License** and **Later**. A successful check is necessary for that route, but does not by itself authorize the switch.

4. **Prepare and review the transfer.** Show the saved preferences, custom ping targets, completed session records and counters that will carry over, together with any unresolved items. Store and verify the new copy before committing to the switch. Keep protection off in the new app during preparation. Preserve the customer's protection preference without blindly replaying a temporary pause or stale launch command. Do not promise transfer of an in-progress session or the full live latency chart history.

5. **Choose when to finish.** Recommend waiting until an active gaming or protected session has ended. Explain any required protection interruption before offering **Finish Migration**. At this point the migration must obtain a fresh, consistent source snapshot and validate every remaining requirement. The interface should make clear when cancellation remains safe. Do not promise uninterrupted protection during helper replacement until that behavior is established.

6. **Complete the handoff.** With the customer's final action, transfer control to one app, finish the approved installation route and request any macOS background-service approval that is actually necessary. Confirm access to the preserved settings and history, plus valid licensing before allowing protection. Completion must match the customer's intended mode: verified protection when enabled, or an intentionally off/free state. A successful license response or installed helper alone is insufficient.

7. **Return to normal use.** Show **Migration Complete** only after the handoff is confirmed. The customer should have one clearly identified active Ping Warden, their preserved settings and completed history, and a working update route. Keep a recoverable original until recovery has been verified. Any later cleanup must be scoped to obsolete installation components and must not use a removal action that deletes retained source data or credentials.

The customer-facing target is one guided flow, without exposing the internal capture and receiving components. The exact delivery mechanism remains unresolved. An automatic updater must not offer an unsafe replacement to an older version. The separate capture companion does not itself satisfy the required bridge-version gate. Installing two apps with the same identity and transferring helper approval across teams also need verification. These steps describe the intended experience, not an available installer.

## Differences by Existing Installation

| Existing installation | Expected licensing and migration route |
| --- | --- |
| Paid 4.x with valid, usable sealed evidence | Carry over existing valid licensing where the actual seal, device, dates and credential access can be verified. No new migration-only online requirement is imposed solely because the version is 4.x. This offline route is not yet operationally proven. |
| Paid 4.0.0 with unsealed cached authorization | Keep the original working app. Proposed route: enter the existing key and complete one successful online check before handoff. Offline or failed verification leaves migration pending. |
| A 4.x user using the free dashboard, diagnostics or update features | Preserve free use with protection off. Do not require a purchase or online license verification merely to migrate those features. Explain licensing only if the user chooses to enable paid protection. |
| A 4.x user relying on an existing transition period, without a paid key | Preserve the original eligible deadline and prior-use evidence. Do not send them to a nonexistent key or give another 90 days. If continuity cannot be established, retain the original installation and explain why migration cannot yet finish. |
| A 4.x user whose paid evidence is expired, inaccessible or inconsistent | Show the actual reason. A blocked credential read is not proof of no purchase. Offer existing-key verification or retry where appropriate. Any normal licensing restriction must be explained before the switch. |
| Earlier than 4.0 | These versions are outside the hard 4.0+ compatibility requirement. That is not a direction to break them deliberately. Users without an updater need a manual upgrade entry point. Explain the existing paid-product and transition rules before replacement. Do not promise automatic data conversion, a free license or a new transition period for every old installation. |
| Confirmed fresh installation | Follow normal first-run setup. Missing settings alone do not prove freshness or absence of a saved license. Do not manufacture migration history or an entitlement. |

## Failure and Recovery Experience

| Situation | What the customer sees and what must happen |
| --- | --- |
| Offline or licensing service unavailable | "We couldn't verify your license right now. Try again when you're online." Keep the original installation unchanged. Do not label the key invalid. |
| Incorrect or no-longer-entitled key | Explain that the supplied key could not be accepted. Offer correction or the existing support route. Do not modify the original app's cached license from the migration process. Its own normal enforcement still applies. |
| Key cannot be read or access is canceled | Distinguish access failure from an absent license. Offer entering the existing key or trying later. Never delete or overwrite the original credential to fix access. |
| Settings or history cannot be captured consistently | Leave migration pending and explain the affected item. Do not silently discard data or treat an unreadable store as empty. |
| App closes or power fails before accepted receiving state exists | Resume or restart the same migration safely. Another online check may be needed. A saved "verified" label alone is not sufficient proof. |
| Required macOS approval is declined | Keep migration pending. If a handoff has already begun, use the verified recovery path before claiming the old app is working again. |
| Older app or widget contacts the helper during handoff | The receiving controller yields to the older client, including for a background status or version request. Show migration as paused or incomplete. Never run competing protection controllers. |
| Failure after control or installation begins changing | Enter recovery and show the real state. Do not claim automatic rollback, restored protection or success until it is observed. This recovery path remains a release requirement. |

## What Oliver Needs to Verify Before Release

The visible journey must preserve a working 4.0+ installation through cancellation before handoff, lack of internet and preparation failures. After handoff begins, interruption requires the verified recovery path. Successful migration must retain saved settings, completed history, counters and valid licensing where applicable. Free-dashboard users must remain free. Migration must not require a second purchase or silently shorten an existing eligible transition period.

The final handoff must demonstrate one protection controller, understandable macOS approvals, working widget and update behavior, and reliable recovery after an interrupted switch. Opening or repairing an older supported version must not create competing controllers or damage the receiving installation. Any protection interruption must be disclosed.

These are acceptance outcomes for Oliver's candidate verification, not a request to restart automated app test suites. No release, feed publication or customer cutover is authorized by this document.

## Evidence and Open Decisions

The source was re-read at `bb4d519` on October 6. The historical 4.0.0 license manager, current licensing policy, continuity assessment, snapshot format and migration-feed guard support the distinctions above. The numbered screens, button labels, timing choices and recovery presentation are proposed product design, not existing UI.

- [Historical 4.0.0 license manager](https://github.com/oliverames/ping-warden/blob/e49ebf509b7e12d63a301f20d46a833bd354fa63/PingWarden/PingWarden/LicenseManager.swift) records the original key storage and local cached authorization.
- [Current licensing policy](https://github.com/oliverames/ping-warden/blob/bb4d519/PingWarden/PingWarden/Core/LicensePolicy.swift) defines existing paid, offline and transition rules and the verification request.
- [Current continuity assessment](https://github.com/oliverames/ping-warden/blob/bb4d519/PingWarden/PingWarden/LicenseContinuityAssessment.swift) retains unresolved requirements and distinguishes missing, blocked and unverified evidence.
- [Migration boundary review](https://github.com/oliverames/ping-warden/blob/bb4d519/docs/Migration%20Boundaries%20Review%202026-10-06.md) records the inactive receiving stores and guarded helper preparation.

**Recommended decision:** allow the successful online check for affected paid installations while preserving the original app until handoff is ready. If fully offline migration is required for those installations, defer their switch until another authoritative entitlement route exists. No such route is established today.
