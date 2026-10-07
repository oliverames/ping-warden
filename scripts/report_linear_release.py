#!/usr/bin/env python3
"""Verify delivered artifacts, then report the scheduled Linear release.

Safe to rerun after a reporting failure. This command never publishes app files.
--dry-run performs receiving checks but reads no Linear credential and writes no release.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

import linear_release as lr

ROOT = Path(__file__).resolve().parent.parent
REPO = 'ping-warden'
TITLE = 'Ping Warden'


def verify_delivery(args):
    beta = '-' in args.version

    if os.environ.get('SKIP_GH_PAGES') == '1' or (not beta and os.environ.get('SKIP_GUMROAD') == '1'):
        raise ValueError('Skipped delivery cannot be completed in Linear; finish publication and run reporting only')
    name = f'PingWarden-{args.version}.dmg'
    release = lr.github_release(REPO, args.version, [name])
    artifact = args.artifacts / name
    asset_url = f'https://github.com/oliverames/{REPO}/releases/download/v{args.version}/{name}'
    lr.verify_download(asset_url, artifact)
    feeds = [('appcast-beta.xml' if beta else 'appcast.xml', args.feed)]
    if not beta:
        feeds.append(('appcast-beta.xml', ROOT / 'appcast-beta.xml'))
    for name, feed in feeds:
        lr.verify_feed(f'https://oliverames.github.io/{REPO}/{name}', feed, args.version, asset_url, artifact)
    if not beta:
        lr.run([sys.executable, ROOT / 'scripts/publish_gumroad.py', os.environ.get('GUMROAD_PRODUCT_ID', 'qthvm'),
                artifact, '--verify-only'])

    return release.get('body') or None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--feed', type=Path)
    parser.add_argument('--source-ref', help='Full built source SHA; otherwise resolve the remote release tag')
    parser.add_argument('--notes-file', type=Path, help='Reviewed notes; defaults to the published GitHub release body')
    parser.add_argument('--base-ref', help='Optional prior delivered source ref for an explicit first issue scan')
    parser.add_argument('--asset-name', help='Skylight Bridge release asset name override')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--check-access', action='store_true', help='With --dry-run, also verify Linear access using read-only API calls')
    parser.add_argument('--attempts', type=int, default=6, help='Receiving check attempts, 10 seconds apart')
    args = parser.parse_args(argv)
    lr.validate_version(args.version)
    if not 1 <= args.attempts <= 30:
        raise ValueError('--attempts must be between 1 and 30')
    if args.check_access and not args.dry_run:
        raise ValueError('--check-access requires --dry-run')
    beta = '-' in args.version
    args.feed = args.feed or ROOT / ('appcast-beta.xml' if beta else 'appcast.xml')
    sha = lr.source_commit(ROOT, REPO, args.version, args.source_ref)
    notes = lr.retry(lambda: verify_delivery(args), attempts=args.attempts)
    if args.notes_file:
        notes = args.notes_file.read_text()
    title = TITLE + (' Beta' if beta else '')
    link = f"https://github.com/oliverames/{REPO}/releases/tag/v{args.version}"
    lr.report(ROOT, REPO, title, args.version, sha, link, dry_run=args.dry_run, base_ref=args.base_ref, check_access=args.check_access, notes=notes)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError, KeyError, IndexError, ET.ParseError, subprocess.TimeoutExpired) as error:
        # Underlying subprocesses or signed URLs may contain credentials.
        if type(error) in (RuntimeError, ValueError):
            print(str(error), file=sys.stderr)
        print('Release reporting failed. Delivery or Linear completion was not confirmed. '
              'Retry this report-only command after checking delivery and credential access.', file=sys.stderr)
        sys.exit(1)
