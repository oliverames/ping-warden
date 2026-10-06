#!/usr/bin/env python3
"""Compile the real LicenseManager against explicit synthetic dependencies.

Requires macOS and Xcode's Swift compiler. The production singleton, defaults
factory, HTTP request and periodic scheduling entry points become traps only
in the temporary compilation unit. Live dependency adapters are excluded.
All license decisions, persistence ordering, verification generation logic,
and removal behavior remain the source under review.

This is a license-manager characterization harness, not an app startup test.
It never launches Ping Warden, contacts a service, opens a Keychain or touches
the app's preferences, helper, device identifier or user data.
"""
from __future__ import annotations

import argparse
import hashlib
import platform
from pathlib import Path
import re
import subprocess
import tempfile


def replace_region(source: str, start: str, end: str, replacement: str) -> str:
    if source.count(start) != 1 or source.count(end) != 1:
        raise RuntimeError("License harness seam changed; review the source before execution")
    first = source.index(start)
    last = source.index(end, first)
    return source[:first] + replacement + source[last:]


def assemble(repo: Path, overlay: Path | None) -> tuple[str, dict[str, str]]:
    source_root = overlay or repo
    app = source_root / "PingWarden" / "PingWarden"
    manager = (app / "LicenseManager.swift").read_text()
    dependencies = (app / "LicenseDependencies.swift").read_text()
    marker = "// MARK: - Live adapters\n"
    if dependencies.count(marker) != 1:
        raise RuntimeError("Live dependency adapter boundary changed")
    interfaces = dependencies.split(marker)[0]

    source = replace_region(
        manager,
        "    private convenience init() {",
        "    /// Internal seam for isolated characterization.",
        '    private convenience init() {\n        fatalError("Production singleton is forbidden in license fixtures")\n    }\n\n',
    )
    source = replace_region(
        source,
        "    nonisolated private static func sharedDefaults() -> UserDefaults {",
        "    // MARK: - Sealed cache",
        '    nonisolated private static func sharedDefaults() -> UserDefaults {\n        fatalError("Production defaults are forbidden in license fixtures")\n    }\n\n',
    )
    source = replace_region(
        source,
        "    func startPeriodicReverification() {",
        "    /// Re-verify a stored key once at launch.",
        '    func startPeriodicReverification() {\n        fatalError("Periodic scheduling is outside this isolated harness")\n    }\n\n',
    )
    source = replace_region(
        source,
        "    private nonisolated static func performVerifyRequest(key: String) async -> Result<Data, Error> {",
        "    // MARK: - Teardown",
        '    private nonisolated static func performVerifyRequest(key: String) async -> Result<Data, Error> {\n        fatalError("Live HTTP is forbidden in license fixtures")\n    }\n\n',
    )

    legacy = subprocess.check_output([
        "git", "-C", str(repo), "show",
        "v4.0.0:PingWarden/PingWarden/Core/LicensePolicy.swift",
    ], text=True)
    if legacy.count("enum LicensePolicy {") != 1:
        raise RuntimeError("Tagged 4.0.0 policy declaration changed")
    legacy_fixture = legacy.replace("enum LicensePolicy {", "enum Legacy400LicensePolicy {", 1)

    fixtures = source_root / "Tests" / "PingWardenLicenseTests"
    core = repo / "PingWarden" / "PingWarden" / "Core"
    parts = [
        interfaces,
        (fixtures / "Stubs.swift").read_text(),
        (core / "LicensePolicy.swift").read_text(),
        (core / "LicenseReminderPolicy.swift").read_text(),
        legacy_fixture,
        source,
        (fixtures / "LicenseTests.swift").read_text(),
    ]
    unit = "\n".join(parts)
    forbidden = (
        r"\bSecItem(?:CopyMatching|Update|Add|Delete)\s*\(",
        r"\bUserDefaults\s*\(", r"\bUserDefaults\s*\.\s*standard\b",
        r"\bURLSession\s*\.", r"\bIOService\w*\s*\(",
        r"\b(?:NSXPCConnection|SMAppService|FileManager|Process)\s*[(.]",
        r"\bTimer\s*\(", r"\bTimer\s*\.\s*scheduledTimer\b",
        r"\bRunLoop\s*\.\s*main\b",
    )
    if any(re.search(pattern, unit) for pattern in forbidden):
        raise RuntimeError("An unisolated platform boundary remains in the license fixture unit")
    provenance = {
        "manager": hashlib.sha256(manager.encode()).hexdigest(),
        "dependencies": hashlib.sha256(dependencies.encode()).hexdigest(),
        "legacy_4_0_0_policy": hashlib.sha256(legacy.encode()).hexdigest(),
    }
    return unit, provenance


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--draft-root", type=Path, help="Optional source/test overlay; Core and v4.0.0 come from --repo")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("This native license harness requires macOS")
    repo = args.repo.resolve()
    overlay = args.draft_root.resolve() if args.draft_root else None
    unit, provenance = assemble(repo, overlay)
    for name, digest in provenance.items():
        print(f"License fixture source {name} SHA-256 {digest}", flush=True)
    with tempfile.TemporaryDirectory(prefix="pingwarden-license-tests-") as directory:
        scratch = Path(directory)
        source = scratch / "LicenseHarness.swift"
        binary = scratch / "license-tests"
        source.write_text(unit)
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", "-strict-concurrency=complete",
            "-parse-as-library", "-module-cache-path", str(scratch / "ModuleCache"),
            str(source), "-o", str(binary),
        ], check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=45)


if __name__ == "__main__":
    main()
