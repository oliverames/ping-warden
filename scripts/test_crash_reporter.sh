#!/usr/bin/env bash
# Compile production crash reporting against a test-only SDK with no transport.
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FIXTURES_DIR="${2:-$REPO_ROOT/Tests/PingWardenCrashReporterTests}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingwarden-crash-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$BUILD_DIR/module-cache" -swift-version 5 -emit-library -emit-module -module-name Sentry \
  "$FIXTURES_DIR/FakeSentry.swift" \
  -emit-module-path "$BUILD_DIR/Sentry.swiftmodule" \
  -Xlinker -install_name -Xlinker '@rpath/libSentry.dylib' \
  -o "$BUILD_DIR/libSentry.dylib"

cat > "$BUILD_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.amesvt.pingwarden.tests.crash-reporter</string>
<key>CFBundleShortVersionString</key><string>9.8.7</string>
<key>CFBundleVersion</key><string>98765</string>
</dict></plist>
PLIST

xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$BUILD_DIR/module-cache" -swift-version 5 -parse-as-library \
  -I "$BUILD_DIR" -L "$BUILD_DIR" -lSentry \
  -Xlinker -rpath -Xlinker "$BUILD_DIR" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$BUILD_DIR/Info.plist" \
  "$REPO_ROOT/PingWarden/PingWarden/Core/CrashReportingPolicy.swift" \
  "$REPO_ROOT/PingWarden/PingWarden/CrashReporter.swift" \
  "$FIXTURES_DIR/CrashReporterTests.swift" \
  -o "$BUILD_DIR/CrashReporterTests"

"$BUILD_DIR/CrashReporterTests"
