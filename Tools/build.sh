#!/bin/bash
# Builds Poise for the iOS Simulator and drops the .app at a stable path (build/<Config>/Poise.app).
# POISE_SIM picks the simulator by name (default: iPhone 17 Pro on iOS 26.4). Avoid the iOS 18.4 runtime on this Mac:
# its URLSession stalls every request after the first on HTTP/3 hosts (60 s timeouts against Supabase).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
DEST="$PWD/build"
SIM="${POISE_SIM:-iPhone 17 Pro}"
UDID=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "simulator '$SIM' not found — set POISE_SIM to one of:"; xcrun simctl list devices available | grep iPhone; exit 1; }

xcodegen generate --quiet
xcodebuild \
  -project Poise.xcodeproj \
  -scheme Poise \
  -configuration "$CONFIG" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DEST/DerivedData" \
  CONFIGURATION_BUILD_DIR="$DEST/$CONFIG" \
  build "${@:2}"

echo "→ $DEST/$CONFIG/Poise.app"
