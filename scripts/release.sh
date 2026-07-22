#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
INFO_PLIST="$ROOT/Support/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP="$ROOT/outputs/Arranger Lab.app"
ARCHIVE_NAME="Arranger-Lab-$VERSION.zip"
CHECKSUM_NAME="$ARCHIVE_NAME.sha256"

cd "$ROOT"
bash "$ROOT/scripts/test.sh"
swift run --disable-sandbox ArrangerLabTestHarness

"$ROOT/scripts/build-app.sh"

cd "$ROOT/outputs"
rm -f "$ARCHIVE_NAME" "$CHECKSUM_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE_NAME"
shasum -a 256 "$ARCHIVE_NAME" > "$CHECKSUM_NAME"

echo "$ROOT/outputs/$ARCHIVE_NAME"
echo "$ROOT/outputs/$CHECKSUM_NAME"
