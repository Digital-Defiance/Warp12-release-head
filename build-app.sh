#!/usr/bin/env bash
# Build Warp 12 Release into a double-clickable .app (no Terminal key capture).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OPEN_APP=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN_APP=1 ;;
    -h|--help)
      echo "Usage: ./build-app.sh [--open]"
      echo "  Builds \"Warp 12 Release.app\" under this directory."
      echo "  Pass --open to launch it after packaging."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

echo "Building Warp12ReleaseHead (release)…"
swift build -c release

BIN="$ROOT/.build/release/Warp12ReleaseHead"
if [[ ! -x "$BIN" ]]; then
  echo "error: missing binary at $BIN" >&2
  exit 1
fi

APP_NAME="Warp 12 Release.app"
APP="$ROOT/$APP_NAME"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"

rm -rf "$APP"
# Drop the old longer name if a previous build left it around.
rm -rf "$ROOT/Warp 12 Release Head.app"

mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/Warp12ReleaseHead"
chmod +x "$MACOS/Warp12ReleaseHead"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Warp 12 Release</string>
  <key>CFBundleDisplayName</key>
  <string>Warp 12 Release</string>
  <key>CFBundleIdentifier</key>
  <string>org.digitaldefiance.warp12-release-head</string>
  <key>CFBundleExecutable</key>
  <string>Warp12ReleaseHead</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

# PkgInfo is optional but keeps Finder happier for homemade bundles.
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "Built: $APP"

if [[ "$OPEN_APP" -eq 1 ]]; then
  open "$APP"
  echo "Opened (password fields stay in the app window, not Terminal)."
fi
