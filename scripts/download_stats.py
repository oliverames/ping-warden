#!/usr/bin/env python3
"""Report release download counts, which are the only direct measure of how
many installs actually accept an update.

Sparkle downloads the DMG when a user accepts, so a release's asset
download count approximates the number of installs that moved to it, plus
manual downloads. Comparing releases tells you whether an upgrade-path
change worked, without collecting anything from users.

Counts are cumulative and keep climbing, so a release published today is
not comparable to one published a month ago. The per-day column exists to
make that explicit rather than inviting a bad comparison.

Usage:
    python3 scripts/download_stats.py                  # table
    python3 scripts/download_stats.py --snapshot       # append a dated row to docs/download-history.tsv
"""

import argparse
import datetime as dt
import json
import pathlib
import subprocess
import sys

REPO = "oliverames/ping-warden"
HISTORY = pathlib.Path(__file__).resolve().parent.parent / "docs" / "download-history.tsv"


def releases():
    out = subprocess.run(
        ["gh", "api", f"repos/{REPO}/releases", "--paginate"],
        capture_output=True, text=True, check=True,
    ).stdout
    # --paginate concatenates JSON arrays; normalise to one list.
    data = []
    for chunk in out.replace("][", "],[").split("\n"):
        if chunk.strip():
            data.extend(json.loads(chunk))
    rows = []
    for r in data:
        count = sum(a.get("download_count", 0) for a in r.get("assets", []))
        published = r.get("published_at", "")[:10]
        rows.append((r["tag_name"], published, count))
    return sorted(rows, key=lambda r: r[1], reverse=True)


def age_days(published, today):
    try:
        return max((today - dt.date.fromisoformat(published)).days, 0)
    except ValueError:
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--snapshot", action="store_true",
                    help="append today's totals to docs/download-history.tsv")
    args = ap.parse_args()

    today = dt.date.today()
    rows = releases()
    if not rows:
        sys.exit("No releases returned.")

    print(f"{'tag':10} {'published':11} {'downloads':>9} {'days':>5} {'per day':>8}")
    for tag, published, count in rows:
        days = age_days(published, today)
        per = f"{count / days:.1f}" if days else "-"
        print(f"{tag:10} {published:11} {count:>9} {days:>5} {per:>8}")

    totals = {}
    for tag, _, count in rows:
        major = tag.lstrip("v").split(".")[0]
        totals[major] = totals.get(major, 0) + count
    print("\nby major version")
    for major in sorted(totals, key=int):
        print(f"  {major}.x  {totals[major]}")

    if args.snapshot:
        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        new = not HISTORY.exists()
        with HISTORY.open("a") as fh:
            if new:
                fh.write("date\ttag\tpublished\tdownloads\n")
            for tag, published, count in rows:
                fh.write(f"{today.isoformat()}\t{tag}\t{published}\t{count}\n")
        print(f"\nAppended {len(rows)} rows to {HISTORY}")


if __name__ == "__main__":
    main()
