# Ping Warden Release Reporting

## Linear release reporting

[Linear Releases](https://linear.app/ames-consulting/pipeline/ping-warden/releases)
records verified customer delivery for this app. Linear does not build, sign,
notarize, upload, or publish the app. Local builds, source-only GitHub releases,
and successful uploads do not complete a Linear release.
The reporting command can be rerun independently after a network or Linear failure.
It repeats receiving checks and targets the same explicit version.

The helper downloads the official `linear/linear-release` CLI at `v0.18.0` and
checks the pinned SHA-256 before every execution. It reads the pipeline credential
from `op://Development/Linear Release - ping-warden/credential` at runtime. An existing
`LINEAR_ACCESS_KEY` environment variable overrides that lookup. Credentials never
appear in command arguments or output. The cache contains only the public executable.

`--dry-run` verifies delivery without reading the Linear credential or writing a
release. Add `--check-access` to also run the official CLI's read-only API check.
A normal run syncs issues, attaches the published GitHub release notes when available,
and completes the scheduled release only after delivery passes. `--notes-file`
can supply reviewed notes explicitly.

Use the supported commit subject format `[AME-123] Describe the change` for
commits that deliver an issue. Preserve that reference in the final squash commit.
The release scanner uses commit references in the scanned history to associate
issues with a release. GitHub-to-project routing does not establish release
membership, and an existing-delivery baseline can legitimately have zero issues.

Attribution uses the release tag's exact source commit in a temporary metadata-only
clone. It does not switch the working checkout. Full local Git history is required, and
branch-reference inference is disabled to avoid unrelated local branch names. The first sync uses Linear's normal
baseline, which may inspect only the current commit. Use `--base-ref <previous-tag>`
for a deliberate initial history range. No historical backfill is implied.

`PingWarden/PingWarden/release.sh` calls the reporter after publication. The
reporter verifies the public GitHub DMG, both served update feeds for
stable releases, and the Gumroad buyer-visible current download before reporting.
A beta verifies only its beta feed and GitHub download, and never touches Gumroad.
`SKIP_GH_PAGES=1`, or stable `SKIP_GUMROAD=1`, defers Linear completion. Finish the
missing delivery before running the reporting-only command with those flags unset.

```sh
/opt/homebrew/bin/python3 scripts/report_linear_release.py \
  --version 4.3.1 --artifacts PingWarden --dry-run --check-access
```

Remove `--dry-run --check-access` to report the already delivered version. No assets,
feeds, or buyer content are published by this command. `publish_gumroad.py
<product> <dmg> --verify-only` is also a read-only receiving check. Published GitHub
notes are attached to the same Linear release on every retry.

Official CLI reference: https://github.com/linear/linear-release/tree/v0.18.0

## Keep delivery evidence

Record the built source's full SHA, version/build, artifact hashes, served feed
URLs and channel, verification result, and returned Linear release ID. Preserve
the original release notes and publication date. Before completing a report-only
retry, recheck receiving delivery and then read the Linear version, source SHA,
completed stage, and notes. Repeating the same version must retain one release.
If a tag follows the build, use the build receipt rather than assuming current
HEAD or the tag identifies the archived source.

## Historical baseline

Version 4.3.1 was published on 2026-09-29 and recorded in Linear on
2026-10-07 from source `c73050274ac868ae71ba1115d273ea76d55b74d3`. The October 7
completion date records the backfill, not a new app publication. Its existing
artifacts and feed were checked, and a reporting-only retry preserved the same
release and note. No historical issue backfill was requested.

The stable and beta feeds both offered 4.3.1 build 43100 when verified on
October 7, 2026. Neither the Linear baseline nor a documentation merge republishes
the app. Developer-account migration remains paused under its existing
authorization boundary.
