#!/usr/bin/env python3
"""Compile production monitor methods against inert native test dependencies.

Requires macOS and Xcode's Swift compiler. No copied production implementation
is stored in test fixtures. The startup initializer is bypassed only in the
temporary compilation unit. Platform boundaries use in-memory fixtures, so
these tests never register a service, contact the live helper, change radio
state, open alerts, or access the application's real preference stores.
"""
from __future__ import annotations

import argparse
import hashlib
import platform
from pathlib import Path
import subprocess
import tempfile


def replace_exactly_once(source: str, old: str, new: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one source seam {old!r}, found {count}. Review the harness against current production source.")
    return source.replace(old, new, 1)


def assemble(repo: Path, fixtures: Path) -> tuple[str, str]:
    app = repo / "PingWarden" / "PingWarden"
    original = (app / "PingWardenMonitor.swift").read_text()
    source = replace_exactly_once(original, "import AppKit\n", "")
    source = replace_exactly_once(source, "import ServiceManagement\n", "")
    source = replace_exactly_once(
        source,
        "    private init() {",
        "    private init(harness: Void) {}\n\n    private init() {",
    )
    parts = [(fixtures / "Stubs.swift").read_text(), source]
    for name in ("XPCReconnectPolicy.swift", "StateObserverRegistry.swift", "HelperBundleValidator.swift"):
        parts.append((app / "Core" / name).read_text())
    parts.append((fixtures / "MonitorTests.swift").read_text())
    return "\n".join(parts), hashlib.sha256(original.encode()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--fixtures-dir", type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("These native monitor tests require macOS.")
    repo = args.repo.resolve()
    fixtures = args.fixtures_dir or repo / "Tests" / "PingWardenMonitorTests"
    unit, digest = assemble(repo, fixtures)
    print(f"Testing production PingWardenMonitor.swift SHA-256 {digest}", flush=True)
    with tempfile.TemporaryDirectory(prefix="pingwarden-monitor-tests-") as directory:
        scratch = Path(directory)
        source = scratch / "main.swift"
        binary = scratch / "monitor-tests"
        source.write_text(unit)
        # The fixture registries are single-threaded mutable state. App code is
        # independently built with its normal strict-concurrency settings.
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5",
            "-module-cache-path", str(scratch / "ModuleCache"),
            str(source), "-o", str(binary),
        ], check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=45)


if __name__ == "__main__":
    main()
