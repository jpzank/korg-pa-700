#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/Arranger Lab.app"

# Some Command Line Tools installations expose a preview SDK newer than their
# bundled Swift interfaces. Prefer the stable SDK that still supports our
# macOS 14 deployment target when full Xcode is not selected.
if [[ -z "${SDKROOT:-}" ]] \
    && [[ "$(xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]] \
    && [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
  export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT/.build/module-cache}"

cd "$ROOT"
swift build --disable-sandbox -c release --product ArrangerLabApp
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/ArrangerLabApp" "$APP/Contents/MacOS/Arranger Lab"
if [[ -d "$BIN_DIR/ArrangerLab_ArrangerLabCore.bundle" ]]; then
  cp -R "$BIN_DIR/ArrangerLab_ArrangerLabCore.bundle" "$APP/Contents/Resources/"
fi
codesign --force --deep --sign - --entitlements "$ROOT/Support/ArrangerLab.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
