# Ping Warden Feed Guard Draft Review

Author: Oliver Ames  
Date: October 6, 2026  
Status: Offline validator with a preparation-only release entry point. Live feed publication remains unchanged.

The draft consists of `validate_migration_feeds.py` and `test_migration_feeds.py`. It reads two local XML files and emits a JSON report. It does not change files, contact services, inspect applications, sign artifacts or publish feeds.

## Required Inputs and Assumptions

The command requires both full candidate feeds, the migration candidate's build, and its required bridge build:

```text
python3 -B validate_migration_feeds.py --stable PATH --beta PATH \
  --migration-candidate-build BUILD --required-bridge-build BUILD
```

`--host-build BUILD` adds probes without removing mandatory coverage. Exit status is 0 for `PASS_CONSERVATIVE_HOLD`, 1 for findings, and 2 for invalid command arguments. A pass concerns only the restricted metadata policy below.

The caller must provide the actual, complete stable and beta candidates. The validator cannot detect items omitted before it receives those files. This first profile requires the same candidate build once in each feed, with no newer build. It does not support a beta-only release candidate. Candidate and bridge inputs are positive integers satisfying `40000 < bridge < candidate`.

The candidate must have a download enclosure and `minimumUpdateVersion` numerically equal to the declared bridge. It must be installable, rather than informational, for that bridge build. Build numbers do not establish license eligibility, artifact identity, signature validity or helper compatibility. Those remain separate checks.

## Conservative Hold Policy

The validator examines every item in both feeds. It treats every newer item as potentially reachable, instead of predicting which one Sparkle will select. An item is excluded only by its supported minimum-update boundary or a supported informational rule for that source build.

Any other potentially installable item is reported as `unreviewed_fallback`, including the designated bridge itself. No list of approved older replacements is inferred. This deliberately supports retaining older applications while a separate preflight route is prepared. Automatic installation of a bridge would need an independently reviewed compatibility policy before this restriction could change.

`minimumAutoupdateVersion` never establishes exclusion. Operating-system restrictions are parsed but never used to dismiss a fallback. Exact informational scopes compare source-build strings, matching Sparkle, while `belowVersion` uses numeric version ordering. An informational item must have an explicit HTTP(S) information link. The validator neither opens that link nor certifies that it leads to a safe migration route.

Host probes include 40000, 40001, 43100, the bridge and its predecessor, and the candidate's predecessor. Probes around every supported build boundary and exact informational scope cover the other integer host intervals. This catches holes between named versions without enumerating every integer. It covers this restricted hold policy, not the complete Sparkle selection algorithm. Noninteger installed 4.x builds are outside the profile.

The default shipped builds come from inspected source tags. This is not a customer-installation inventory. Fixture builds **50000** and **60000** are hypothetical values and are not release-number proposals.

## Unsupported Cases Fail Closed

Unsupported constructs produce findings rather than a success with skipped items. These include deltas, explicit channels, hardware requirements, phased rollout, critical-update tags, enclosure OS/installation-type attributes, unknown elements and attributes, and ambiguous duplicates.

The accepted version subset is one to three canonical numeric components, with at most nine digits each. Historical numeric versions such as `3.1.0` are accepted. Prerelease suffixes, leading zeros, URL-inferred versions and disagreement between item and enclosure versions are rejected. The XML profile is UTF-8 RSS 2.0 with one unnamespaced channel and a 10 MiB input limit. DTDs, entity declarations and non-UTF-8 encoding declarations fail closed. Namespace aliases for the Sparkle URI and whitespace around informational scope values also fail closed, preserving the pinned parser’s literal scope behavior.

No pass verifies EdDSA signatures or enclosures, licensing, actual installed state, skipped-update preferences, currently staged or resumed updates, updater delegates, manual downloads, atomic replacement or rollback. In particular, it does not close the known resumed-update delegate bypass. Native Sparkle integration and signed installation fixtures remain required before any release claim.

## Verification Evidence

Executed on October 6, 2026:

```text
python3 -B scripts/test_migration_feeds.py
Ran 32 tests in 0.047s
OK
```

All 32 tests ran, with no skips. Cases include unsafe older fallbacks, stable/beta differences, required explicit inputs, source-build scope boundaries and gaps, missing informational links, unsupported constructs, version ambiguity, malformed XML, and command-line JSON/exit behavior. Fixture reads compare both input hashes before and after validation to assert immutability.

The independent review identified unsafe normalization of informational scope whitespace and namespace aliases. Parent corrections reject both, and three additional regression methods cover those cases and unsupported encoding declarations.

A separate read-only negative control used the repository's existing `appcast.xml` and `appcast-beta.xml` with hypothetical candidate 60000 and bridge 50000. It parsed **37 items per feed**, returned `FAIL`, reported the missing candidate in each feed, and identified **18 unreviewed fallbacks per feed for host 40000**. Across all boundary probes it reported 762 fallback findings. These counts concern checked-in files, not live endpoints. The absent hypothetical candidate is expected and is not a release failure.

No Swift compiler, native build, app launch, account, Keychain, installed data or live feed was used. The repository and its release workflow were not edited.

## Pinned Source Basis

The model follows locally inspected upstream Sparkle commit `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`, the 2.9.6 dependency pinned by Ping Warden 4.0.0 and current source:

- [Minimum-update filtering](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Sparkle/SUAppcastDriver.m#L481) and [minimum-autoupdate semantics](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Sparkle/SUAppcastItem.h#L310).
- [Exact and below-version informational scopes](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Sparkle/SPUAppcastItemStateResolver.m#L98), including [the information-link prerequisite](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Sparkle/SUAppcastItem.m#L578).
- [Numeric component balancing](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Sparkle/SUStandardVersionComparator.m#L174). The draft intentionally rejects the comparator's more complex formats.

The two scripts are available for manual offline review. No release workflow calls them. Compatible-bridge classification and native validation remain separate requirements.

## Preparation Entry Point Added October 6

The existing release script now accepts `--prepare-migration-feeds` before any credential, build, signing or publication step. It requires an explicit candidate item, migration build, required bridge build and a new output directory. The ordinary release invocation remains unchanged and still requires the former signing team.

```text
./PingWarden/PingWarden/release.sh --prepare-migration-feeds \
  --item CANDIDATE_ITEM_XML --migration-candidate-build ACTUAL_BUILD \
  --required-bridge-build ACTUAL_BRIDGE_BUILD --output-dir NEW_DIRECTORY
```

This mode reads both complete source feeds, checks their raw structure, uses the maintained updater merge in a temporary directory, and validates both merged candidates. Only a passing preparation writes a new output directory containing unsigned feeds and a report. Existing destinations are rejected. No candidate or bridge version is selected by this implementation.

The report explicitly sets `preparationOnly` to true and `publicationAuthorized` to false. A metadata pass does not establish licensing, helper, staged-update, installation or rollback continuity. Beta-only migration candidates remain unsupported.

Independent review caught two draft issues. Divergent stable/beta entries sharing a marketing version are now rejected before merging, and every source freshness read retains the 10 MiB input bound. Strict comparison may hold differently formatted source entries for review. The corrected source passed focused independent re-review.

Bash syntax, ShellCheck, Python syntax and the preparation command's help route passed. No further tests, candidate-feed execution, signing, release or feed publication ran, following Oliver's October 6 scope instruction. Earlier 32-case evidence above applies to the standalone validator before this integration.
