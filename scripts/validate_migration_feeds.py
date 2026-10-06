#!/usr/bin/env python3
"""Offline, conservative hold-first check of two complete Sparkle candidate feeds.

This checks metadata, not signatures, licenses, updater state or installation.
No bridge or other fallback is implicitly certified compatible by its version.
"""

import argparse
from dataclasses import asdict, dataclass, field
import io
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
PREFIX = "{" + SPARKLE + "}"
MAX_FEED_BYTES = 10 * 1024 * 1024
BASE_HOSTS = (40000, 40001, 43100)
NUMERIC_VERSION = re.compile(r"(?:0|[1-9][0-9]{0,8})(?:\.(?:0|[1-9][0-9]{0,8})){0,2}\Z")
RSS_METADATA = {"title", "link", "description", "pubDate"}
SPARKLE_METADATA = {
    "version", "shortVersionString", "minimumUpdateVersion",
    "minimumAutoupdateVersion", "minimumSystemVersion", "maximumSystemVersion",
    "releaseNotesLink", "fullReleaseNotesLink", "informationalUpdate",
}
ENCLOSURE_ATTRIBUTES = {"url", "length", "type"} | {
    PREFIX + name for name in ("version", "shortVersionString", "edSignature", "dsaSignature")
}


class Unsupported(ValueError):
    pass


def version(text):
    """Only canonical, bounded numeric versions, with at most three components."""
    if not isinstance(text, str) or not NUMERIC_VERSION.fullmatch(text):
        raise Unsupported("unsupported version syntax; use canonical numeric components")
    parts = tuple(int(part) for part in text.split("."))
    return parts + (0,) * (3 - len(parts))


def build_argument(text):
    if not re.fullmatch(r"[1-9][0-9]{0,8}", text):
        raise argparse.ArgumentTypeError("build must be a positive canonical integer, at most nine digits")
    return int(text)


def text_value(element):
    if element.attrib or list(element):
        raise Unsupported("attributes or nested elements on a scalar field")
    value = (element.text or "").strip()
    if not value:
        raise Unsupported("empty scalar field")
    return value


def web_url(text):
    try:
        parsed = urlsplit(text)
        return parsed.scheme in ("https", "http") and bool(parsed.netloc) and not parsed.username and not parsed.password
    except ValueError:
        return False


@dataclass(frozen=True)
class Item:
    build: str
    minimum: tuple | None
    has_enclosure: bool
    information_all: bool
    information_exact: frozenset
    information_below: tuple

    def informational_for(self, host):
        return (self.information_all or str(host) in self.information_exact
                or any(version(str(host)) < boundary for boundary in self.information_below))


@dataclass(frozen=True)
class Finding:
    feed: str
    code: str
    detail: str
    item: str | None = None
    host: int | None = None


@dataclass
class Report:
    candidate_build: int
    required_bridge_build: int
    hosts: list
    findings: list = field(default_factory=list)
    parsed_items: dict = field(default_factory=dict)

    def result(self):
        return {
            "status": "FAIL" if self.findings else "PASS_CONSERVATIVE_HOLD",
            "candidate_build": self.candidate_build,
            "required_bridge_build": self.required_bridge_build,
            "hosts": self.hosts,
            "host_coverage": "Boundary probes cover integer host builds from 40000 through candidate minus one under this restricted metadata model; explicit extra hosts are also checked.",
            "parsed_items": self.parsed_items,
            "findings": [asdict(finding) for finding in self.findings],
            "scope": "Metadata only. No license, signature, staged-update, link-destination or installation approval.",
            "selection": "Every newer entry is potentially reachable; OS limits and autoupdate thresholds never establish safety.",
        }


def parse_item(node):
    if node.attrib:
        raise Unsupported("item attributes are unsupported")
    fields = {}
    allowed = RSS_METADATA | {"enclosure"} | {PREFIX + name for name in SPARKLE_METADATA}
    for child in node:
        if child.tag not in allowed:
            raise Unsupported("unsupported item element: " + child.tag)
        if child.tag in fields:
            raise Unsupported("duplicate item element: " + child.tag)
        fields[child.tag] = child

    # Descriptions may contain escaped HTML, but nested XML is outside this profile.
    for tag, child in fields.items():
        if tag not in ("enclosure", PREFIX + "informationalUpdate"):
            text_value(child)
    enclosure = fields.get("enclosure")
    if enclosure is not None:
        if list(enclosure) or (enclosure.text or "").strip():
            raise Unsupported("nested enclosure content")
        if set(enclosure.attrib) - ENCLOSURE_ATTRIBUTES:
            raise Unsupported("unsupported enclosure attributes, including deltas, OS or installation types")
        if not web_url(enclosure.get("url", "")):
            raise Unsupported("enclosure needs an explicit HTTP(S) URL")

    element_build = fields.get(PREFIX + "version")
    element_build = text_value(element_build) if element_build is not None else None
    enclosure_build = enclosure.get(PREFIX + "version") if enclosure is not None else None
    if element_build is not None and enclosure_build is not None and element_build != enclosure_build:
        # Sparkle prefers the enclosure attribute. Reject disagreement instead of guessing intent.
        raise Unsupported("item and enclosure versions disagree")
    build = enclosure_build or element_build
    version(build)

    minimum_node = fields.get(PREFIX + "minimumUpdateVersion")
    minimum = version(text_value(minimum_node)) if minimum_node is not None else None
    for name in ("minimumAutoupdateVersion", "minimumSystemVersion", "maximumSystemVersion"):
        child = fields.get(PREFIX + name)
        if child is not None:
            version(text_value(child))

    info = fields.get(PREFIX + "informationalUpdate")
    link = fields.get("link")
    link_valid = link is not None and web_url(text_value(link))
    if (info is not None or enclosure is None) and not link_valid:
        # Sparkle ignores informationalUpdate without a usable info URL.
        raise Unsupported("informational update needs an explicit HTTP(S) item link")
    exact, below = set(), []
    information_all = enclosure is None
    if info is not None:
        if info.attrib or (info.text or "").strip():
            raise Unsupported("unsupported informationalUpdate attributes or text")
        information_all = information_all or not list(info)
        for scope in info:
            value = text_value(scope)
            if scope.text != value:
                raise Unsupported("informational scope whitespace differs from Sparkle's raw comparison")
            key = version(value)
            if scope.tag == PREFIX + "version":
                exact.add(value)  # Upstream exact scopes compare strings, not normalized versions.
            elif scope.tag == PREFIX + "belowVersion":
                below.append(key)
            else:
                raise Unsupported("unsupported informationalUpdate scope: " + scope.tag)
            if (scope.tail or "").strip():
                raise Unsupported("mixed informationalUpdate content")
    return Item(build, minimum, enclosure is not None, information_all, frozenset(exact), tuple(below))


def load_feed(path, label, findings):
    try:
        with Path(path).open("rb") as stream:
            data = stream.read(MAX_FEED_BYTES + 1)
        if len(data) > MAX_FEED_BYTES:
            raise Unsupported("feed exceeds the 10 MiB input limit")
        source = data.decode("utf-8-sig")
        if "\x00" in source:
            raise Unsupported("only UTF-8 XML is supported")
        if "<!DOCTYPE" in source.upper() or "<!ENTITY" in source.upper():
            raise Unsupported("DTD and entity declarations are unsupported")
        declaration = re.match(r"<\?xml\s+([^?]*)\?>", source)
        if declaration:
            encoding = re.search(r"\bencoding\s*=\s*(['\"])([^'\"]+)\1", declaration.group(1))
            if encoding and encoding.group(2).lower() != "utf-8":
                raise Unsupported("only an explicit UTF-8 XML encoding is supported")
        parser = ET.iterparse(io.StringIO(source), events=("start-ns",))
        for _, (prefix, uri) in parser:
            # Sparkle normalizes ordinary item fields, but compares literal
            # qualified child names inside informationalUpdate. Reject aliases
            # before ElementTree discards their spelling.
            if uri == SPARKLE and prefix != "sparkle":
                raise Unsupported("Sparkle namespace aliases are outside this profile")
        root = parser.root
        if root.tag != "rss" or root.attrib != {"version": "2.0"}:
            raise Unsupported("expected an unnamespaced RSS 2.0 root")
        if len(root) != 1 or root[0].tag != "channel" or root[0].attrib:
            raise Unsupported("expected exactly one unnamespaced channel")
        nodes = []
        for child in root[0]:
            if child.tag == "item":
                nodes.append(child)
            elif child.tag in RSS_METADATA | {"language", "lastBuildDate", "generator"}:
                text_value(child)
            else:
                raise Unsupported("unsupported channel element: " + child.tag)
    except (OSError, UnicodeError, ET.ParseError, Unsupported) as error:
        findings.append(Finding(label, "unsupported_feed", str(error)))
        return []

    items, seen = [], set()
    for index, node in enumerate(nodes, 1):
        try:
            item = parse_item(node)
            key = version(item.build)
            if key in seen:
                raise Unsupported("duplicate or numerically equivalent item build")
            seen.add(key)
            items.append(item)
        except Unsupported as error:
            findings.append(Finding(label, "unsupported_item", str(error), item=f"entry {index}"))
    return items


def host_probes(items, candidate, bridge, supplied):
    """Cover each predicate's change points, without enumerating every integer.

    For our numeric-only versions, integer-host comparisons change at a boundary's
    first component or its successor. Exact information scopes change only at
    their named integer. Neighbours also expose gaps between exact scopes.
    This covers our hold policy, not Sparkle's real update-selection algorithm.
    """
    hosts = set(BASE_HOSTS + (bridge - 1, bridge, candidate - 1) + tuple(supplied))
    for item in items:
        boundaries = [version(item.build)] + list(item.information_below)
        boundaries += [version(value) for value in item.information_exact]
        if item.minimum is not None:
            boundaries.append(item.minimum)
        for boundary in boundaries:
            for host in (boundary[0] - 1, boundary[0], boundary[0] + 1):
                if 40000 <= host < candidate:
                    hosts.add(host)
    return sorted(hosts)


def validate(stable, beta, *, candidate_build, required_bridge_build, extra_hosts=()):
    # API callers receive the same strict input validation as the command line.
    candidate = build_argument(str(candidate_build))
    bridge = build_argument(str(required_bridge_build))
    if not 40000 < bridge < candidate:
        raise ValueError("require 40000 < required bridge build < migration candidate build")
    supplied_hosts = [build_argument(str(host)) for host in extra_hosts]
    if any(host < 40000 for host in supplied_hosts):
        raise ValueError("this profile covers installed 4.x builds starting at 40000")
    report = Report(candidate, bridge, [])
    try:
        if Path(stable).resolve() == Path(beta).resolve() or Path(stable).samefile(beta):
            report.findings.append(Finding("both", "same_feed", "stable and beta must be separate full candidate feed files"))
    except OSError:
        pass  # Each input receives its own read-error finding below.
    feeds = {label: load_feed(path, label, report.findings)
             for label, path in (("stable", stable), ("beta", beta))}
    report.hosts = host_probes([item for items in feeds.values() for item in items], candidate, bridge, supplied_hosts)
    for label, items in feeds.items():
        report.parsed_items[label] = len(items)
        candidates = [item for item in items if item.build == str(candidate)]
        if len(candidates) != 1:
            report.findings.append(Finding(label, "candidate_missing", "exact candidate build must occur once in each feed", item=str(candidate)))
        for item in items:
            key = version(item.build)
            if key > version(str(candidate)):
                report.findings.append(Finding(label, "newer_than_candidate", "candidate must be the newest build in this profile", item=item.build))
            if item.build == str(candidate):
                if item.minimum != version(str(bridge)):
                    report.findings.append(Finding(label, "candidate_boundary", "candidate minimumUpdateVersion must equal the declared bridge build", item=item.build))
                if not item.has_enclosure or item.informational_for(bridge):
                    report.findings.append(Finding(label, "candidate_not_installable", "candidate must be installable by the declared bridge build", item=item.build, host=bridge))
            for host in report.hosts:
                host_key = version(str(host))
                if key <= host_key or (item.minimum is not None and host_key < item.minimum):
                    continue
                if item.informational_for(host):
                    continue
                if item.build == str(candidate) and host >= bridge:
                    continue
                code = "candidate_bypasses_bridge" if item.build == str(candidate) else "unreviewed_fallback"
                report.findings.append(Finding(label, code, "potentially installable replacement; an autoupdate threshold does not exclude it", item=item.build, host=host))
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stable", type=Path, required=True)
    parser.add_argument("--beta", type=Path, required=True)
    parser.add_argument("--migration-candidate-build", type=build_argument, required=True)
    parser.add_argument("--required-bridge-build", type=build_argument, required=True)
    parser.add_argument("--host-build", type=build_argument, action="append", default=[], help="additional host probe; cannot remove mandatory probes")
    args = parser.parse_args(argv)
    try:
        report = validate(args.stable, args.beta, candidate_build=args.migration_candidate_build,
                          required_bridge_build=args.required_bridge_build, extra_hosts=args.host_build)
    except (ValueError, argparse.ArgumentTypeError) as error:
        parser.error(str(error))
    print(json.dumps(report.result(), indent=2, sort_keys=True))
    return 1 if report.findings else 0


if __name__ == "__main__":
    sys.exit(main())
