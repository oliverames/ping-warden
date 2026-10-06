# Ping Warden Handoff Review

Author: Oliver Ames

Date: October 6, 2026

The next migration increment prepares private staging and a dormant receiving app. It does not activate imported settings or replace the installed app. All release publication and update-feed changes remain on hold until Oliver verifies a concrete candidate.

## Staging and Recovery

The staging coordinator validates the existing snapshot format, retains its exact bytes and binds it to a transaction, owner token and snapshot identifier. A caller must retain those inputs before writing. Retrying the same transaction resumes an interrupted preparing record. Canceling a staged transaction removes its logical payload while retaining a cancellation record that prevents accidental reuse.

Each conditional update compares both the storage revision and complete record bytes. Readback must match before the coordinator reports success. Any error can follow an earlier committed phase, so recovery always revisits the same transaction. It never assumes that an error means nothing was written.

Staging is separate from live settings. Every receipt preserves the snapshot's `notReady` status and all original blockers. Cached licensing claims retain their original dates and do not become proof of purchase. There is no activation API, credential copying or production preference mapping.

The system SQLite adapter uses one dedicated private directory, exclusive creation and explicit reopening. It checks ownership, access rules, path identities, schema and database integrity. Conditional writes compare the revision and complete payload inside one writer transaction. Retained revision records prevent reuse within the intact database. Reads check the blob size before allocating its contents.

The adapter requests persistent rollback journaling, full synchronization and macOS full synchronization. These settings rely on the operating system and storage device. [SQLite synchronization documentation](https://www.sqlite.org/pragma.html#pragma_synchronous) and [transaction documentation](https://www.sqlite.org/lang_transaction.html) describe those guarantees and limits.

After a storage error, reopen a fresh adapter and revisit the same transaction. Reopening can perform journal recovery and is unsuitable for passive inspection of an unknown database. Logical cancellation does not securely erase prior journal or free-page bytes. Path checks do not provide a security boundary against other code running as the same user or restoration of an older database.

## Startup and Helper Ownership

Source review found that the ordinary app constructs its session and protection coordinators before its launch callback. A migration check inserted only into that callback would arrive too late. The widget also has its own settings and helper entry paths.

The app generations currently control the same privileged helper. An older app's quit or repair path could interfere with a new controller. Broadening the helper's team allowlist alone does not resolve ownership. Existing client identities, licensing, helper behavior and update trust therefore remain in place.

A disabled compile condition now selects a separate app entry and delegate that own only an informational window. Settings, About, updates and reopen show migration status. Termination performs no production cleanup. The dormant widget reads no settings, and both of its intents refuse action before accessing storage or the helper.

The ordinary app and widget source remains intact under the alternative branch. Current target settings do not enable the condition. Any future receiver build must apply it consistently to both targets. The shell has no activation method and does not establish safe installation alongside another app with the same identifier.

## Verification and Release Hold

The normal app built through native Xcode tooling in 14.624 seconds, with no errors. A separate unsigned build of the dormant app and widget passed in 34.335 seconds. Compiler commands confirmed the condition for both targets, and widget intent metadata extraction completed. This second build used a temporary command-line override because the native build tool has no setting-override argument. Project build settings remain unchanged.

Independent source review found one database validation defect: a wildcard filter could hide a user-defined trigger from the expected schema check. The corrected literal-prefix filter was re-read by the reviewer. No additional blocking source findings remained in that scope.

No app test suite, runtime database exercise, customer import, installed app launch or release occurred. Builds establish compilation, not operational handoff safety. The installed Ping Warden remains 4.3.1 (43100), signed by the former team.

The former account's notarization credentials authenticated successfully through a read-only Apple history request on October 6. No archive was uploaded. Authentication establishes access to that service, not acceptance of a future transition package.

Remaining customer work includes authoritative licensing continuity for offline paid 4.0.0 installations, signed credential access, current source capture, activation and operational rollback, helper ownership and update installation. Preserve the original working installation until those boundaries are resolved. Tracking remains in [issue 109](https://github.com/oliverames/ping-warden/issues/109).
