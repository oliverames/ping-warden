#!/bin/bash
# Compile the real helper against mocked interface operations. No root, helper
# installation, network changes, or live application preferences are involved.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingwarden-helper-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation \
    "$ROOT/Tests/PingWardenHelperTests/MonitorTests.m" -o "$TEST_DIR/helper-tests"
"$TEST_DIR/helper-tests"
