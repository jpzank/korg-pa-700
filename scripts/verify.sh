#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"

cd "$ROOT"
bash "$ROOT/scripts/test.sh"
swift run --disable-sandbox ArrangerLabTestHarness
"$ROOT/scripts/build-app.sh"
