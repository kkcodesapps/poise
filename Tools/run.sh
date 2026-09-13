#!/bin/bash
# Builds, installs on the simulator, relaunches. Pass a path as $2 to also save a screenshot there.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
SHOT="${2:-}"
SIM="${POISE_SIM:-iPhone 16 Pro}"
BUNDLE="com.koliokolev.poise"

"$PWD/Tools/build.sh" "$CONFIG" -quiet
UDID=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "simulator '$SIM' not found"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$PWD/build/$CONFIG/Poise.app"
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
echo "Poise running on $SIM ($UDID)."
if [ -n "$SHOT" ]; then sleep 3; xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null; echo "→ $SHOT"; fi
