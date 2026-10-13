#!/usr/bin/env python3
"""Maintain the paid-upgrade boundary and stable releases in both Sparkle feeds."""

import argparse
import copy
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
PAID_BUILD = "40000"
# Feeds once opened every 4.x item with a paid-upgrade notice. Release notes
# now carry only each version's changes, so any earlier notice is removed.
NOTICE_PATTERN = re.compile(
    r"<p><strong>Upgrading from Ping Warden 3 or earlier\?</strong>.*?</p>", re.S
)


def value(item, name):
    return item.findtext(f"{{{SPARKLE}}}{name}") or item.find("enclosure").get(f"{{{SPARKLE}}}{name}", "")


def build_key(build):
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", build):
        raise ValueError(f"Invalid build number: {build}")
    return tuple(int(n) for n in build.split(".")) + (0,) * (3 - len(build.split(".")))


def normalize(item):
    version = value(item, "shortVersionString")
    if int(version.split(".")[0]) >= 4:
        tag = f"{{{SPARKLE}}}minimumAutoupdateVersion"
        boundary = item.find(tag)
        if boundary is None:
            boundary = ET.SubElement(item, tag)
        boundary.text = PAID_BUILD
        description = item.find("description")
        if description is None:
            description = ET.SubElement(item, "description")
        text = (description.text or "").replace("https://olivera40.gumroad.com/", "https://amesconsulting.gumroad.com/")
        # This coupon is no longer redeemable. Do not propagate it in updates.
        text = re.sub(r" via a hidden 100% off code \(<code\b[^>]*>[^<]+</code>\)", " after receipt verification", text)
        text = NOTICE_PATTERN.sub("", text).lstrip()
        description.text = text


def load_feed(path, beta=False):
    if path.exists():
        return ET.parse(path)
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Ping Warden Beta Updates" if beta else "Ping Warden Updates"
    ET.SubElement(channel, "link").text = "https://oliverames.github.io/ping-warden/" + path.name
    ET.SubElement(channel, "description").text = "Updates for Ping Warden"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(root)


def replace_items(tree, additions):
    channel = tree.find("channel")
    if channel is None:
        raise ValueError("Feed has no channel")
    items = {value(item, "shortVersionString"): item for item in channel.findall("item")}
    for item in additions:
        items[value(item, "shortVersionString")] = copy.deepcopy(item)
    for item in channel.findall("item"):
        channel.remove(item)
    for item in sorted(items.values(), key=lambda item: build_key(value(item, "version")), reverse=True):
        normalize(item)
        channel.append(item)


def missing_published_items(local_path, published_path):
    """Return "version (build N)" labels published remotely but absent locally.

    Items are keyed by sparkle:shortVersionString, the same key replace_items
    uses, so an item missing here is one the next rewrite would drop.
    """
    published = load_feed(published_path).findall("channel/item")
    local = {value(item, "shortVersionString") for item in load_feed(local_path).findall("channel/item")}
    return [f"{value(item, 'shortVersionString')} (build {value(item, 'version')})"
            for item in published if value(item, "shortVersionString") not in local]


def check_published(stable_path, beta_path, published_stable, published_beta):
    """Exit non-zero when a published item would be lost by the next rewrite."""
    problems = []
    for local, published in [(stable_path, published_stable), (beta_path, published_beta)]:
        if published is None:
            continue
        missing = missing_published_items(local, published)
        if missing:
            problems.append(f"  {local.name} is missing published item(s): {', '.join(missing)}")
    if not problems:
        return
    print("Error: the local appcasts are behind the feeds published on gh-pages.", file=sys.stderr)
    print("\n".join(problems), file=sys.stderr)
    print("Publishing now would delete those items from the live feeds.", file=sys.stderr)
    print("Fix: copy the published feeds from origin/gh-pages into the repo root, commit, push, then re-run:",
          file=sys.stderr)
    print("  git fetch origin gh-pages", file=sys.stderr)
    print("  git show origin/gh-pages:appcast.xml > appcast.xml", file=sys.stderr)
    print("  git show origin/gh-pages:appcast-beta.xml > appcast-beta.xml", file=sys.stderr)
    sys.exit(1)


def update(stable_path, beta_path, item_path=None, beta_release=False):
    stable = load_feed(stable_path)
    beta = load_feed(beta_path, beta=True)
    additions = [ET.parse(item_path).getroot()] if item_path else []
    replace_items(stable, [] if beta_release else additions)
    replace_items(beta, stable.findall("channel/item") + (additions if beta_release else []))
    # ElementTree drops XML comments, so this rewrite removes each feed's
    # <!-- sparkle-signatures: ... --> trailer. That is intended: the old
    # signature no longer matches the rewritten bytes, and release.sh always
    # re-signs both feeds with sign_update (which writes a fresh trailer)
    # immediately after this script. test_release_tools.py asserts that order.
    for tree, path in [(stable, stable_path), (beta, beta_path)]:
        ET.indent(tree, space="  ")
        tree.write(path, encoding="utf-8", xml_declaration=True)
        with path.open("ab") as stream:
            stream.write(b"\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stable", type=Path, required=True)
    parser.add_argument("--beta", type=Path, required=True)
    parser.add_argument("--item", type=Path)
    parser.add_argument("--beta-release", action="store_true")
    parser.add_argument("--check-build")
    parser.add_argument("--published-stable", type=Path,
                        help="published appcast.xml whose items must all exist in --stable")
    parser.add_argument("--published-beta", type=Path,
                        help="published appcast-beta.xml whose items must all exist in --beta")
    args = parser.parse_args()
    if args.published_stable or args.published_beta:
        check_published(args.stable, args.beta, args.published_stable, args.published_beta)
        return
    if args.check_build:
        existing = load_feed(args.beta if args.beta_release else args.stable).findall("channel/item")
        if any(build_key(value(item, "version")) >= build_key(args.check_build) for item in existing):
            parser.error("Release build must be newer than every published build in its channel")
        return
    update(args.stable, args.beta, args.item, args.beta_release)


if __name__ == "__main__":
    main()
