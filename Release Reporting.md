# Ping Warden Release Reporting

## Linear release reporting

The scheduled Linear pipeline records verified customer delivery. Local builds,
source-only GitHub releases, and successful uploads do not complete a release.
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

Attribution uses the release tag's exact source commit in a temporary metadata-only
clone. It does not switch the working checkout. Full local Git history is required, and
branch-reference inference is disabled to avoid unrelated local branch names. The first sync uses Linear's normal
baseline, which may inspect only the current commit. Use `--base-ref <previous-tag>`
for a deliberate initial history range. No historical backfill is implied.

The release script now verifies the public GitHub DMG, both served update feeds for
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
