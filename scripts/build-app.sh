#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/Arranger Lab.app"

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
