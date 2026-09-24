#!/usr/bin/env python3
"""Exercise production presentation methods with inert, in-memory boundaries."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile


def block(source, signature):
    if source.count(signature) != 1:
        raise RuntimeError(f"Expected exactly one source seam: {signature}")
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
        cursor += 1
    return source[start:cursor]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    app = args.repo / "PingWarden/PingWarden"
    sources = {name: (app / name).read_text() for name in (
        "PingWardenApp.swift", "DashboardView.swift", "DashboardViewModel.swift")}
    seams = {
        "ADD_TARGET": ("DashboardViewModel.swift", "func addCustomTarget(displayName:"),
        "SUBMIT": ("PingWardenApp.swift", "private func submitLicenseKey()"),
        "OBSERVER": ("PingWardenApp.swift", "private func installSettingsSectionObserver()"),
        "SECTION": ("PingWardenApp.swift", "enum SettingsSection: String, CaseIterable, Identifiable"),
        "SUMMARY": ("DashboardView.swift", "private var chartAccessibilityValue: String"),
        "TIMEFRAME": ("DashboardView.swift", "private func timeframeLabel(for minutes: Int)"),
        "EVENTS": ("DashboardViewModel.swift", "var filteredTimelineEvents: [LatencyTimelineEvent]"),
        "REFRESH": ("DashboardViewModel.swift", "private func refreshFilteredHistory()"),
        "DOWNSAMPLE": ("DashboardViewModel.swift", "private static func downsample("),
        "KIND": ("DashboardView.swift", "enum Kind"),
    }
    unit = Path(__file__).with_name("PresentationTests.swift").read_text()
    for key, (filename, signature) in seams.items():
        fragment = block(sources[filename], signature)
        unit = unit.replace("// INSERT_" + key, fragment)
        print(f"{key} SHA-256 {hashlib.sha256(fragment.encode()).hexdigest()}", flush=True)
    with tempfile.TemporaryDirectory(prefix="pingwarden-presentation-tests-") as folder:
        scratch = Path(folder)
        source = scratch / "Presentation.swift"
        binary = scratch / "presentation-tests"
        source.write_text(unit)
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                        "-strict-concurrency=complete", "-warnings-as-errors",
                        "-module-cache-path", str(scratch / "ModuleCache"),
                        str(app / "Core/CustomPingTargetStore.swift"), str(source), "-o", str(binary)], check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
