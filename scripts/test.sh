#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_ROOT="$(xcode-select -p)"
TESTING_FRAMEWORKS="$DEVELOPER_ROOT/Library/Developer/Frameworks"

cd "$ROOT"

if [[ -d "$TESTING_FRAMEWORKS/Testing.framework" ]]; then
    swift test --disable-sandbox --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS"
else
    swift test --disable-sandbox --enable-swift-testing
fi
