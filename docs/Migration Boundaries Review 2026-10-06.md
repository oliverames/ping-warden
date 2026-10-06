# Ping Warden Migration Boundaries Review

Author: Oliver Ames

Date: October 6, 2026

The next source increment prepares separate receiving stores and a compatibility helper. The receiving app remains dormant. No signing identity, entitlement, installed application, privileged service or update feed has changed. Releases remain on hold until Oliver verifies the candidate.

## Receiving Data

The destination description names the new team's shared settings group, `84M4ZF255G.com.amesvt.pingwarden`, and a separate application settings domain, `com.amesvt.pingwarden.receiver`. Completed session history will live inside the receiving group's container. The captured source metadata remains unchanged.

An unused adapter opens only an existing, accessible destination directory. It checks ownership and directory identity and refuses to fall back to the former stores. It does not import data, create directories, change permissions or prove durable persistence. There is no production caller.

The dashboard now accepts explicit application and shared settings handles. Its existing constructor retains the ordinary stores. GeForce NOW cache reads, asynchronous completion and the in-memory cache follow the supplied application handle. A future receiving runtime must retain one handle per domain, including during removal. Separate handles for the same domain can leave an older in-memory cache entry.

These changes do not redirect the complete runtime. Session coordination, licensing, launch markers, window state, notifications, diagnostics and removal still need one reviewed receiving composition. The original Keychain service must remain untouched. Constructing the ordinary dashboard inside the dormant app would still start shared runtime dependencies.

Apple documents that macOS may return a group-container URL for an invalid group. Opening a URL or a named defaults object is therefore insufficient migration evidence. Import must preserve the snapshot's exact values and distinguish absence from an empty domain. [Container URL documentation](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)), [Named defaults documentation](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:)).

## Helper Ownership

A disabled compiler condition selects a compatibility service with one serialized control queue and a separate session for each connection. The existing six helper methods remain unchanged. Both the listener and each connection retain the former team's existing app and widget requirement. No receiving principal is admitted.

The future ownership path binds authority to the connection, helper lifetime and a random token. Older clients have priority. A valid older-client message retires receiving authority before performing its ordinary operation. Disconnect, release and shutdown also retire that authority. Passive receiver connections cannot extend the existing 60-second legacy disconnect grace.

Acquisition checks actual interface state and idle enforcement under the monitor lock. Relinquishment clears receiving enforcement before trying to restore the interface. A restoration failure prevents further acquisition in that helper lifetime. These paths remain unreachable by receiving clients while admission is closed.

The helper does not certify imported data, licensing or source freshness. Its supplied import identifier is only an ownership label. Exact receiving-client admission, receiving transport and activation remain separate work. Cross-team service approval, old-client Repair and same-identifier installation behavior require manual verification before release.

## Verification and Remaining Work

Independent source reviews found no blocking issue in either bounded increment. Native Xcode built the final ordinary source in 10.336 seconds. A separate unsigned build of the dormant app/widget and guarded helper passed in 10.207 seconds. Both results reported success. The helper had also compiled from its complete new source in the first 64.195-second variant build.

That first variant exposed a concurrency warning in the new cache injection. The discovery entry point now stays on the dashboard actor while the network wait remains asynchronous. The correction was independently reviewed and the final variant emitted no warning. Xcode’s incremental ordinary log retained prior diagnostics under unchanged batch members, while the changed dashboard and discovery sources recompiled. No additional app test suite, app launch, interface operation or real-store migration was run by this task.

Both migration conditions remain absent from project settings. The temporary variant used command-line overrides only. Xcode’s automatic navigator rewrite was inspected and removed after closing this task’s workspace. No target setting changed. The installed app was rechecked as 4.3.1 (43100), still signed by the former team.

The outstanding product decision is whether affected 4.0 installations may complete migration after one successful online license verification. Their original app must remain operational until handoff succeeds. No such requirement or verifier has been implemented while that decision is pending.

Source preparation is not a completed migration. Operational import, signed credential continuity, receiving helper admission, activation, rollback and updater handoff remain tracked in [issue 109](https://github.com/oliverames/ping-warden/issues/109). The installed product and its existing customers remain on their current path.

## Activation Integration Map

Before enabling a receiving runtime, wire these paths together and review them as one change:

- Application and widget preferences must require the receiving shared domain and skip source migration and fallback.
- Protected-session coordination must receive the recap store, receiving preferences and application defaults before it loads history or registers observers. Import must preserve recap bytes instead of loading and re-encoding them.
- Diagnostics, launch hints, welcome state, updater markers and menu choices must use the receiving handles. Window frame persistence needs an explicit receiving-domain solution.
- Removal must clear only receiving settings, caches, recaps and credentials. It must never call the ordinary source cleanup or infer its target domain from the retained bundle identifier.
- Licensing needs a separate credential service and checked persistence. Copying cache flags or constructing a manager cannot establish a valid entitlement.
- Distributed notifications, telemetry caches, updater persistence and same-identifier system bookkeeping remain separate coexistence concerns. Keep those runtime components inactive until reviewed.

These are implementation gates, not additional test-suite requirements. The current dormant entry constructs none of these production components.
