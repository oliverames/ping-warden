#!/usr/bin/env python3
"""Publish one Ping Warden DMG while retaining license keys and other buyer content."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import math
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

PRODUCT_ID = "FmGG0pxyEyzJqp_BG4itFQ=="

# Gumroad can take several minutes to settle an uploaded file's size and URL.
# The 4.1.8 release (2026-09-14) needed more than the 60 seconds this used to
# allow and failed the release's final step; the file was ready a few minutes
# later. Five minutes covers that with margin, and --wait-seconds overrides it.
DEFAULT_WAIT_SECONDS = 300
POLL_DELAY_SECONDS = 5


def gumroad(*args):
    result = subprocess.run(["gumroad", *args, "--json", "--no-input", "--non-interactive"],
                            check=True, capture_output=True, text=True)
    if "--dry-run" in args:
        return None
    return json.loads(result.stdout)


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def validate(product, pages):
    if product.get("id") != PRODUCT_ID or not product.get("published"):
        raise ValueError("Expected the published Ping Warden license product")
    if not pages or not any(n.get("type") == "licenseKey" for n in nodes(pages)):
        raise ValueError("Buyer content must contain a licenseKey block before publishing")


def replace_download(pages, files, filename):
    matches = [f for f in files if f.get("name") == filename]
    if len(matches) != 1:
        raise ValueError("Expected exactly one uploaded file for this release")
    latest_id = matches[0]["id"]
    dmg_ids = {f["id"] for f in files if re.fullmatch(r"PingWarden-[\w.+-]+\.dmg", f.get("name", ""))}
    latest_nodes = [n for n in nodes(pages) if n.get("type") == "fileEmbed" and n.get("attrs", {}).get("id") == latest_id]
    if not latest_nodes:
        raise ValueError("Uploaded DMG is not embedded in buyer content")
    latest = copy.deepcopy(latest_nodes[0])

    def prune(value):
        if isinstance(value, list):
            return [prune(v) for v in value if not (isinstance(v, dict) and v.get("type") == "fileEmbed" and v.get("attrs", {}).get("id") in dmg_ids)]
        if isinstance(value, dict):
            return {k: prune(v) for k, v in value.items()}
        return value

    result = prune(pages)
    result[0]["description"].setdefault("content", []).insert(0, latest)
    return result, latest_id


def verify_download(file, path):
    if file.get("size") != path.stat().st_size:
        raise ValueError("Gumroad DMG size does not match the release artifact")
    digest = hashlib.sha256()
    with urllib.request.urlopen(file["url"], timeout=60) as response:
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.digest() != hashlib.sha256(path.read_bytes()).digest():
        raise ValueError("Gumroad DMG bytes do not match the release artifact")


def verify_current_delivery(product, pages, path):
    """Read-only gate: uploading a file is insufficient without buyer visibility."""
    validate(product, pages)
    matches = [f for f in product.get("files", []) if f.get("name") == path.name]
    if len(matches) != 1:
        raise ValueError("Expected exactly one uploaded file for this release")
    dmg_ids = {f["id"] for f in product["files"] if re.fullmatch(r"PingWarden-[\w.+-]+\.dmg", f.get("name", ""))}
    visible = [n.get("attrs", {}).get("id") for n in nodes(pages)
               if n.get("type") == "fileEmbed" and n.get("attrs", {}).get("id") in dmg_ids]
    if visible != [matches[0]["id"]]:
        raise ValueError("Buyer content does not offer exactly the current release")
    verify_download(matches[0], path)


def attempts_for(wait_seconds, delay=POLL_DELAY_SECONDS):
    """Poll count that covers wait_seconds at the given delay (at least one)."""
    if wait_seconds <= 0:
        return 1
    return max(1, math.ceil(wait_seconds / delay))


def wait_for_upload(product_id, filename, expected_size,
                    attempts=attempts_for(DEFAULT_WAIT_SECONDS), delay=POLL_DELAY_SECONDS):
    # Gumroad can return the uploaded file before its size/URL metadata settles.
    for attempt in range(attempts):
        product = gumroad("products", "view", product_id)["product"]
        matches = [f for f in product.get("files", []) if f.get("name") == filename]
        if len(matches) > 1:
            raise ValueError("More than one uploaded file has this release name")
        if len(matches) == 1 and matches[0].get("size") == expected_size and matches[0].get("url"):
            return product
        if attempt + 1 < attempts:
            # A visible heartbeat in the release log, so a slow Gumroad pass
            # reads as waiting rather than as a hung script.
            if (attempt + 1) % 6 == 0:
                print(f"Waiting for Gumroad to settle {filename} "
                      f"({(attempt + 1) * delay}s of {attempts * delay}s)", file=sys.stderr, flush=True)
            time.sleep(delay)
    raise ValueError("Gumroad upload metadata did not become ready; buyer content was not replaced")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("product")
    parser.add_argument("dmg", type=Path, nargs="?")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--verify-only", action="store_true", help="Verify the existing buyer download without publishing")
    parser.add_argument("--wait-seconds", type=int, default=DEFAULT_WAIT_SECONDS,
                        help="How long to wait for Gumroad to settle the upload's metadata "
                             f"(default {DEFAULT_WAIT_SECONDS})")
    args = parser.parse_args()
    product = gumroad("products", "view", args.product)["product"]
    pages = gumroad("products", "content", "get", args.product)
    validate(product, pages)
    if args.check:
        print("Verified product identity, publication, and license-key delivery")
        return
    if args.dmg is None or not args.dmg.is_file():
        parser.error("A release DMG is required")
    if args.verify_only:
        verify_current_delivery(product, pages, args.dmg)
        print(f"Verified existing buyer download: {args.dmg.name}")
        return
    if not any(f.get("name") == args.dmg.name for f in product.get("files", [])):
        gumroad("products", "update", args.product, "--file", str(args.dmg), "--file-name", args.dmg.name)
    product = wait_for_upload(args.product, args.dmg.name, args.dmg.stat().st_size,
                              attempts=attempts_for(args.wait_seconds))
    pages = gumroad("products", "content", "get", args.product)
    validate(product, pages)
    updated, latest_id = replace_download(pages, product["files"], args.dmg.name)
    verify_download(next(f for f in product["files"] if f["id"] == latest_id), args.dmg)
    with tempfile.TemporaryDirectory(prefix="pingwarden-content-") as directory:
        path = Path(directory) / "content.json"
        path.write_text(json.dumps(updated))
        gumroad("products", "content", "set", args.product, str(path), "--dry-run")
        # Re-read immediately before replacing the document to detect another editor.
        if gumroad("products", "content", "get", args.product) != pages:
            raise ValueError("Buyer content changed during publication; retry with current content")
        gumroad("products", "content", "set", args.product, str(path))
    verified = gumroad("products", "content", "get", args.product)
    validate(product, verified)
    dmg_ids = {f["id"] for f in product["files"] if re.fullmatch(r"PingWarden-[\w.+-]+\.dmg", f.get("name", ""))}
    visible = [n.get("attrs", {}).get("id") for n in nodes(verified) if n.get("type") == "fileEmbed" and n.get("attrs", {}).get("id") in dmg_ids]
    if visible != [latest_id]:
        raise ValueError("Buyer content does not offer exactly the current release")
    print(f"Verified buyer download: {args.dmg.name}, with license-key content preserved")


if __name__ == "__main__":
    main()
