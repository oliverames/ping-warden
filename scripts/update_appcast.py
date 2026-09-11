#!/usr/bin/env python3
"""Maintain paid-upgrade metadata and stable releases in both Sparkle feeds."""

import argparse
import copy
import re
from pathlib import Path
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
PAID_BUILD = "40000"
UPGRADE_NOTICE = (
    '<p><strong>Upgrading from Ping Warden 3 or earlier?</strong> '
    'Your protection keeps working when you update. If it was enabled with the helper '
    'approved, updating starts a 90-day transition that begins at your first launch of '
    'version 4. That offer has no expiry date, so it is the same 90 days whenever you '
    'update. After it ends, keeping Ping Protection in the signed app is a one-time $15. '
    'The dashboard, latency history, diagnostics, and updates stay free, and the source '
    'remains MIT. Licenses are what fund continued development, and the support means a lot. '
    'Donated through Buy Me a Coffee before version 4? Email '
    '<a href="mailto:oliver@ames.consulting">oliver@ames.consulting</a> with your receipt '
    'and it will be honored as a full license. '
    '<a href="https://pingwarden.app/docs/overview#pricing">Pricing and transition details</a>.</p>'
)
# Matches any previously injected notice so the text can be revised in place.
# Without this the "already present" check below would pin the first wording
# ever published and silently ignore every later edit.
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
        text = NOTICE_PATTERN.sub("", text, count=1).lstrip()
        text = UPGRADE_NOTICE + text
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


def update(stable_path, beta_path, item_path=None, beta_release=False):
    stable = load_feed(stable_path)
    beta = load_feed(beta_path, beta=True)
    additions = [ET.parse(item_path).getroot()] if item_path else []
    replace_items(stable, [] if beta_release else additions)
    replace_items(beta, stable.findall("channel/item") + (additions if beta_release else []))
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
    args = parser.parse_args()
    if args.check_build:
        existing = load_feed(args.beta if args.beta_release else args.stable).findall("channel/item")
        if any(build_key(value(item, "version")) >= build_key(args.check_build) for item in existing):
            parser.error("Release build must be newer than every published build in its channel")
        return
    update(args.stable, args.beta, args.item, args.beta_release)


if __name__ == "__main__":
    main()
