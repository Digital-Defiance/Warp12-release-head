#!/usr/bin/env bash
# Launch Release Head without tying keyboard input to the launching Terminal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift build -c release >/dev/null
"$ROOT/.build/release/Warp12ReleaseHead" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
echo "Warp 12 Release Head started (click its window before typing passwords)."
