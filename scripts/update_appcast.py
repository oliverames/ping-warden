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


def merged_feeds(stable_path, beta_path, item_path=None, beta_release=False):
    stable = load_feed(stable_path)
    beta = load_feed(beta_path, beta=True)
    additions = [ET.parse(item_path).getroot()] if item_path else []
    replace_items(stable, [] if beta_release else additions)
    replace_items(beta, stable.findall("channel/item") + (additions if beta_release else []))
    return stable, beta


def write_feed(tree, path):
    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    with path.open("ab") as stream:
        stream.write(b"\n")


def update(stable_path, beta_path, item_path=None, beta_release=False):
    stable, beta = merged_feeds(stable_path, beta_path, item_path, beta_release)
    for tree, path in [(stable, stable_path), (beta, beta_path)]:
        write_feed(tree, path)


def prepare_migration_feeds(stable_path, beta_path, item_path, *,
                            candidate_build, required_bridge_build, output_dir):
    # Keep the ordinary updater independent of migration-only imports and policy.
    import hashlib
    import json
    import shutil
    import tempfile
    import validate_migration_feeds as guard

    candidate = guard.build_argument(str(candidate_build))
    bridge = guard.build_argument(str(required_bridge_build))
    if not 40000 < bridge < candidate:
        raise ValueError("require 40000 < required bridge build < migration candidate build")
    sources = {"stable": Path(stable_path), "beta": Path(beta_path), "item": Path(item_path)}
    if any(not path.is_file() for path in sources.values()):
        raise ValueError("both complete source feeds and the candidate item must be existing files")
    if sources["stable"].samefile(sources["beta"]):
        raise ValueError("stable and beta source feeds must be separate files")
    output = Path(output_dir).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError("output directory must not already exist")
    if not output.parent.is_dir():
        raise ValueError("output parent directory must already exist")

    # Bound all reads. Validate source syntax before merging can normalize XML
    # namespaces or replace an item, then validate the actual merged candidates.
    contents = {}
    for label, path in sources.items():
        with path.open("rb") as stream:
            contents[label] = stream.read(guard.MAX_FEED_BYTES + 1)
        if len(contents[label]) > guard.MAX_FEED_BYTES:
            raise ValueError(f"{label} exceeds the feed guard's 10 MiB input limit")
    fingerprints = {label: hashlib.sha256(data).hexdigest() for label, data in contents.items()}
    item_text = contents["item"].decode("utf-8-sig")
    declaration = re.match(r"<\?xml\s+([^?]*)\?>", item_text)
    if declaration:
        encoding = re.search(r"\bencoding\s*=\s*(['\"])([^'\"]+)\1", declaration.group(1))
        if encoding and encoding.group(2).lower() != "utf-8":
            raise ValueError("candidate item must use UTF-8 XML")
        item_text = item_text[declaration.end():]

    with tempfile.TemporaryDirectory(prefix="pingwarden-migration-") as temporary:
        staging = Path(temporary)
        staged_sources = {label: staging / (label + "-source.xml") for label in sources}
        for label, path in staged_sources.items():
            path.write_bytes(contents[label])
        item_feed = staging / "item-feed.xml"
        item_feed.write_text('<rss version="2.0"><channel>' + item_text + '</channel></rss>', encoding="utf-8")
        findings = []
        source_items = {label: guard.load_feed(staged_sources[label], label, findings) for label in ("stable", "beta")}
        new_items = guard.load_feed(item_feed, "item", findings)
        if findings:
            report = guard.Report(candidate, bridge, [])
            report.findings.extend(findings)
            result = report.result()
            result["preparationOnly"] = True
            result["publicationAuthorized"] = False
            return result
        if len(new_items) != 1 or new_items[0].build != str(candidate):
            raise ValueError("candidate item must contain the exact declared migration build")
        if any(guard.version(item.build) >= guard.version(str(candidate))
               for items in source_items.values() for item in items):
            raise ValueError("candidate build must be newer than every source-feed item")
        # The existing updater indexes releases by shortVersionString. Require
        # that metadata instead of guessing a name for informational entries.
        release_versions = {}
        source_entries = {}
        for label, path in staged_sources.items():
            tree = ET.parse(path)
            nodes = [tree.getroot()] if label == "item" else tree.findall("channel/item")
            versions = []
            entries = {}
            for node in nodes:
                enclosure = node.find("enclosure")
                short = node.findtext(f"{{{SPARKLE}}}shortVersionString")
                short = short or (enclosure.get(f"{{{SPARKLE}}}shortVersionString") if enclosure is not None else None)
                if not short or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-(?:alpha|beta|rc)\.[0-9]+)?", short):
                    raise ValueError(f"{label} requires release shortVersionString metadata on every item")
                versions.append(short)
                entry = copy.deepcopy(node)
                entry.tail = None
                entries[short] = ET.tostring(entry, encoding="utf-8")
            if len(versions) != len(set(versions)):
                raise ValueError(f"{label} has duplicate shortVersionString values that the updater would discard")
            release_versions[label] = set(versions)
            source_entries[label] = entries
        for short in release_versions["stable"] & release_versions["beta"]:
            if source_entries["stable"][short] != source_entries["beta"][short]:
                raise ValueError("stable and beta have divergent entries for the same shortVersionString; preserve both before preparation")
        if release_versions["item"] & (release_versions["stable"] | release_versions["beta"]):
            raise ValueError("migration candidate must use a new shortVersionString, preserving source-feed history")
        stable, beta = merged_feeds(staged_sources["stable"], staged_sources["beta"], staged_sources["item"])
        candidate_paths = {"stable": staging / "appcast.xml", "beta": staging / "appcast-beta.xml"}
        for tree, label in ((stable, "stable"), (beta, "beta")):
            write_feed(tree, candidate_paths[label])
        report = guard.validate(candidate_paths["stable"], candidate_paths["beta"],
                                candidate_build=candidate, required_bridge_build=bridge).result()
        report["preparationOnly"] = True
        report["publicationAuthorized"] = False
        report["sourceFiles"] = {label: {"path": str(path.resolve()), "sha256": fingerprints[label]}
                                 for label, path in sources.items()}
        if report["findings"]:
            return report
        for label, path in sources.items():
            with path.open("rb") as stream:
                current = stream.read(guard.MAX_FEED_BYTES + 1)
            if current != contents[label]:
                raise ValueError("a source file changed during preparation; no candidates were saved")
        report["outputDirectory"] = str(output)
        report["candidateFiles"] = {
            label: {"name": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "signed": False}
            for label, path in candidate_paths.items()}
        # mkdir is exclusive. Even a concurrently created destination is never
        # overwritten. A handled write failure removes only this new directory.
        output.mkdir()
        try:
            for path in candidate_paths.values():
                shutil.copyfile(path, output / path.name)
            (output / "Migration Feed Report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        except BaseException:
            shutil.rmtree(output)
            raise
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stable", type=Path, required=True)
    parser.add_argument("--beta", type=Path, required=True)
    parser.add_argument("--item", type=Path)
    parser.add_argument("--beta-release", action="store_true")
    parser.add_argument("--check-build")
    parser.add_argument("--prepare-migration-feeds", action="store_true",
                        help="prepare unsigned local candidates only; never sign or publish")
    parser.add_argument("--migration-candidate-build")
    parser.add_argument("--required-bridge-build")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    migration_values = (args.migration_candidate_build, args.required_bridge_build, args.output_dir)
    if args.prepare_migration_feeds:
        if not args.item or not all(value is not None for value in migration_values):
            parser.error("migration preparation requires --item, --migration-candidate-build, --required-bridge-build and --output-dir")
        if args.beta_release or args.check_build is not None:
            parser.error("migration preparation supports a candidate in both feeds, not --beta-release or --check-build")
        try:
            report = prepare_migration_feeds(args.stable, args.beta, args.item,
                candidate_build=args.migration_candidate_build,
                required_bridge_build=args.required_bridge_build, output_dir=args.output_dir)
        except (OSError, ValueError, ET.ParseError, argparse.ArgumentTypeError) as error:
            parser.error(str(error))
        import json
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if report["findings"] else 0
    if any(value is not None for value in migration_values):
        parser.error("migration options require --prepare-migration-feeds")
    if args.check_build:
        existing = load_feed(args.beta if args.beta_release else args.stable).findall("channel/item")
        if any(build_key(value(item, "version")) >= build_key(args.check_build) for item in existing):
            parser.error("Release build must be newer than every published build in its channel")
        return
    update(args.stable, args.beta, args.item, args.beta_release)


if __name__ == "__main__":
    sys.exit(main())
