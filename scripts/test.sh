#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"
TESTING_FRAMEWORKS="$DEVELOPER_ROOT/Library/Developer/Frameworks"

cd "$ROOT"

SWIFT_TEST_ARGS=(--disable-sandbox)
if swift test --help 2>&1 | grep -q -- '--enable-swift-testing'; then
    SWIFT_TEST_ARGS+=(--enable-swift-testing)
elif swift test --help 2>&1 | grep -q -- '--enable-experimental-swift-testing'; then
    SWIFT_TEST_ARGS+=(--enable-experimental-swift-testing)
fi

if [[ -d "$TESTING_FRAMEWORKS/Testing.framework" ]]; then
    swift test "${SWIFT_TEST_ARGS[@]}" \
        -Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS"
else
    swift test "${SWIFT_TEST_ARGS[@]}"
fi
