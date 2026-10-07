#!/usr/bin/env python3
"""Prepare a separate, licensed Control Center test app. Never edits shipping sources.

Build and sign the resulting project using the normal local tools. This command
does not install, launch, register a helper, or change a network interface.
The fixture's helper still controls the real awdl0 interface when enabled.
"""
import argparse
from pathlib import Path
import shutil


OLD_ID = "com.amesvt.pingwarden"
NEW_ID = "com.amesvt.pingwarden92test"
NAME = "Ping Warden 92 Test"


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise ValueError(f"Expected one fixture patch location in {path}: {old[:70]}")
    path.write_text(text.replace(old, new, 1))


def replace_body(path, declaration, body):
    text = path.read_text()
    if text.count(declaration) != 1:
        raise ValueError(f"Expected one declaration in {path}: {declaration}")
    start = text.index("{", text.index(declaration))
    depth = 1
    end = start + 1
    while depth:
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
        end += 1
    path.write_text(text[:start + 1] + "\n" + body + "\n    " + text[end - 1:])


def prepare(destination, license_state="paid"):
    repo = Path(__file__).resolve().parents[1]
    destination = destination.resolve()
    if destination == repo or repo in destination.parents:
        raise ValueError("Fixture must be outside the production checkout")
    destination.mkdir(parents=True, exist_ok=False)
    project = destination / "PingWarden"
    shutil.copytree(repo / "PingWarden", project, ignore=shutil.ignore_patterns(
        "build", "DerivedData", "xcuserdata", "*.dmg", "*.zip"))
    scripts = destination / "scripts"
    scripts.mkdir()
    shutil.copy2(repo / "scripts/release_validation.sh", scripts)

    # Include product-name storage paths, launchd filenames, signature
    # requirements, notifications, App Groups, and the helper's crash marker.
    for path in destination.rglob("*"):
        if path.is_file() and path.suffix in {
            ".swift", ".m", ".h", ".plist", ".entitlements", ".pbxproj", ".sh", ".xcscheme"
        }:
            text = path.read_text()
            path.write_text(text.replace(OLD_ID, NEW_ID).replace("Ping Warden", NAME)
                            .replace("PingWarden-Diagnostics-", "PingWarden92Test-Diagnostics-"))
    for path in list(destination.rglob(OLD_ID + "*.plist")):
        path.rename(path.with_name(path.name.replace(OLD_ID, NEW_ID)))

    app = project / "PingWarden"
    license_source = app / "LicenseManager.swift"
    initial_state = ("cachedLicenseValid: true, lastVerifiedAt: now, grandfatherDeadline: nil"
                     if license_state == "paid" else
                     "cachedLicenseValid: false, lastVerifiedAt: nil, grandfatherDeadline: now.addingTimeInterval(21 * 86400)")
    replace_body(license_source, "private init()", '''        defaults = Self.sharedDefaults()
        // Seed only once so same-identity upgrade tests exercise preservation.
        if defaults.object(forKey: Self.sealKey) == nil {
            let now = Date()
            Self.writeSealedState(SealedState(INITIAL_STATE, lastSeenAt: now), to: defaults)
        }'''.replace("INITIAL_STATE", initial_state))
    for declaration in [
        "func establishGrandfatheringIfNeeded(helperEnabled: Bool)",
        "func startPeriodicReverification()", "func reverifyAtLaunchIfNeeded()",
        "private func storeKeychainValue(_ data: Data, account: String)",
        "private func deleteKeychainItem(account: String)",
    ]:
        replace_body(license_source, declaration, "        // Isolated fixture: no external license or Keychain operations.")
    replace_body(license_source, "var storedLicenseKey: String?", "        nil")
    replace_body(license_source, "private func keychainMarkerExists(account: String)", "        false")
    replace_body(license_source, "private nonisolated static func performVerifyRequest(key: String)",
                 "        .failure(URLError(.notConnectedToInternet))")
    for declaration in ["static func startIfEnabled()", "static func stop()"]:
        replace_body(app / "CrashReporter.swift", declaration, "        // Isolated fixture: no Sentry activity.")
    replace_once(app / "PingWardenApp.swift", '''updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )''', "updaterController = nil // Isolated fixture: never starts Sparkle.")

    # The public widget title must be distinguishable in the Control Gallery.
    widget = project / "PingWardenWidget/PingWardenWidget.swift"
    widget.write_text(widget.read_text().replace('"Ping Protection"', '"Ping Protection 92 Test"'))

    remaining = license_source.read_text()
    for forbidden in ["SecItemCopyMatching(", "SecItemUpdate(", "SecItemAdd(", "SecItemDelete(",
                      "URLSession.shared.data("]:
        if forbidden in remaining:
            raise ValueError(f"Fixture still performs an external license operation: {forbidden}")
    print(project / "PingWarden.xcodeproj")
    print(f"App: {NAME}; bundle: {NEW_ID}; group: PV3W52NDZ3.{NEW_ID}")
    print("Before first launch, confirm the fixture has no saved protection intent.")
    print("The real AWDL interface is NOT isolated. Only enable protection during an approved test.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="New scratch directory, outside this checkout")
    parser.add_argument("--license-state", choices=["paid", "transition"], default="paid",
                        help="Initial synthetic entitlement; an existing sealed state is preserved")
    arguments = parser.parse_args()
    prepare(arguments.destination, arguments.license_state)
