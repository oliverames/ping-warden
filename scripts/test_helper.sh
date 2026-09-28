#!/bin/bash
# Compile the real helper against mocked interface operations. No root, helper
# installation, network changes, or live application preferences are involved.
# The suite runs three times: plain, under ThreadSanitizer, and under Address
# and Undefined Behavior Sanitizers, because the monitor is multithreaded.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingwarden-helper-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
SOURCE="$ROOT/Tests/PingWardenHelperTests/MonitorTests.m"

xcrun clang -fobjc-arc -fblocks -framework Foundation "$SOURCE" -o "$TEST_DIR/helper-tests"
"$TEST_DIR/helper-tests"

xcrun clang -fobjc-arc -fblocks -framework Foundation -g -fsanitize=thread \
    "$SOURCE" -o "$TEST_DIR/helper-tests-tsan"
TSAN_OPTIONS="halt_on_error=1" "$TEST_DIR/helper-tests-tsan" | sed 's/^/[tsan] /'

xcrun clang -fobjc-arc -fblocks -framework Foundation -g -fsanitize=address,undefined \
    -fno-sanitize-recover=undefined "$SOURCE" -o "$TEST_DIR/helper-tests-asan"
"$TEST_DIR/helper-tests-asan" | sed 's/^/[asan] /'
