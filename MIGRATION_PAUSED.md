# Developer-account migration is paused

Oliver requested this preserved branch and worktree on October 7, 2026. Do not resume migration implementation, packaging, account changes, merging or release work until Oliver explicitly resumes it. Keep this branch and worktree available.

- Branch: `migration/paused-developer-account`
- Worktree: `/Users/oliverames/Developer/Projects/ping-warden-migration-paused`
- Preserved source: `d57bb120d7edcd3860a090e499e0a2617043c56b`
- Preparation commits: `f83e625`, `dbad94e`, `af3219a`, `a2c6024`, `8187e1a`, `cbd4a60`, `2d94dae`, `bb4d519`, `78b665b`
- Tracking: [GitHub #109](https://github.com/oliverames/ping-warden/issues/109) and [Linear AME-90](https://linear.app/ames-consulting/issue/AME-90/verify-4x-continuity-before-signing-migration)

The preparation is incomplete and does not establish a customer handoff. Migration compiler flags remain disabled. Existing licenses, production signing, installed applications and public feeds are unchanged by this preservation step.

The preparation commits were already ancestors of `main`. Their changes are being removed from `main` with a normal revert, without rewriting shared history. This branch retains their source together with the later README refresh and release-reporting changes. Its only additional changes document the pause.

Do not merge this branch automatically. If Oliver resumes the migration, first inspect the revert on `main` and deliberately restore the required changes on a new working branch. Merging an old branch alone does not undo a revert of commits already in shared history. Preserve subsequent unrelated changes and verify the complete continuity requirements before any release.
