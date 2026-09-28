#!/usr/bin/env python3
"""Compile the production protection coordinator and monitor against inert
native test dependencies.

Requires macOS and Xcode's Swift compiler. No copied production implementation
is stored in test fixtures: ProtectionExperienceCoordinator.swift,
PingWardenMonitor.swift, and the Core policies they use are compiled as they
are. The startup initializer and the awdl0 interface read are replaced only in
the temporary compilation unit. Platform boundaries use in-memory fixtures, so
these tests never register a service, contact the live helper, change radio
state, open alerts or System Settings, or access the application's real
preference stores. The latency-session coordinator is a fixture because its
store writes to Application Support.
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


CORE_SOURCES = (
    "XPCReconnectPolicy.swift",
    "StateObserverRegistry.swift",
    "HelperBundleValidator.swift",
    "HelperRecovery.swift",
    "ProtectionFailureCopy.swift",
    "ProtectionExperiencePolicy.swift",
)


def assemble(repo: Path, fixtures: Path) -> tuple[str, str]:
    app = repo / "PingWarden" / "PingWarden"
    monitor = (app / "PingWardenMonitor.swift").read_text()
    coordinator = (app / "ProtectionExperienceCoordinator.swift").read_text()
    source = replace_exactly_once(monitor, "import AppKit\n", "")
    source = replace_exactly_once(source, "import ServiceManagement\n", "")
    source = replace_exactly_once(
        source,
        "    private init() {",
        "    private init(harness: Void) {}\n\n    private init() {",
    )
    # ifconfig would read this Mac's radio; the fixture supplies the line.
    source = replace_exactly_once(
        source,
        "    private func getAWDLInterfaceStatus() -> String {",
        "    private func getAWDLInterfaceStatus() -> String { HarnessInterface.flagsLine }\n\n"
        "    private func unusedInterfaceStatus() -> String {",
    )
    parts = [
        (fixtures / "Stubs.swift").read_text(),
        (fixtures / "SessionStubs.swift").read_text(),
        source,
        coordinator,
    ]
    for name in CORE_SOURCES:
        parts.append((app / "Core" / name).read_text())
    parts.append((fixtures / "Helpers.swift").read_text())
    parts.append((fixtures / "CoordinatorTests.swift").read_text())
    digest = hashlib.sha256((monitor + coordinator).encode()).hexdigest()
    return "\n".join(parts), digest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--fixtures-dir", type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("These native coordinator tests require macOS.")
    repo = args.repo.resolve()
    fixtures = args.fixtures_dir or repo / "Tests" / "PingWardenCoordinatorTests"
    unit, digest = assemble(repo, fixtures)
    print(f"Testing production coordinator and monitor SHA-256 {digest}", flush=True)
    with tempfile.TemporaryDirectory(prefix="pingwarden-coordinator-tests-") as directory:
        scratch = Path(directory)
        source = scratch / "main.swift"
        binary = scratch / "coordinator-tests"
        source.write_text(unit)
        # The fixture registries are single-threaded mutable state. App code is
        # independently built with its normal strict-concurrency settings.
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5",
            "-module-cache-path", str(scratch / "ModuleCache"),
            str(source), "-o", str(binary),
        ], check=True, timeout=240)
        subprocess.run([str(binary)], check=True, timeout=180)


if __name__ == "__main__":
    main()
