#!/bin/bash
# Builds Poise signed for a real iPhone, installs it, and launches it. USB or Wi-Fi — devicectl picks the transport.
# Requires: device paired to this Mac, Developer Mode on, unlocked. First run may prompt for the signing team in Xcode.
#   Tools/device.sh [Debug|Release]            (POISE_DEVICE overrides the device name; default: first available iPhone)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
DEST="$PWD/build"
BUNDLE="com.koliokolev.poise"
NAME="${POISE_DEVICE:-}"

LIST=$(xcrun devicectl list devices 2>/dev/null)
if [ -n "$NAME" ]; then LINE=$(echo "$LIST" | grep -F "$NAME" | head -1); else LINE=$(echo "$LIST" | grep -iE "iphone" | grep -iE "available" | head -1); fi
[ -n "$LINE" ] || { echo "no available iPhone — is it unlocked and paired?"; echo "$LIST"; exit 1; }
COREID=$(echo "$LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
DEVNAME=$(echo "$LINE" | awk -F'  +' '{print $1}')
UDID=$(xcrun devicectl device info details --device "$COREID" 2>/dev/null | grep -E "•\s*udid:" | sed -E "s/.*udid: *//")
[ -n "$UDID" ] || { echo "could not read the hardware UDID for $DEVNAME"; exit 1; }

# Debug device builds sign with the "Poise Dev" / "Poise Widgets Dev" profiles that Tools/profiles.js mints through the
# App Store Connect API (Xcode's own automatic signing with an API key stopped authenticating). If a profile is
# missing or a device was added, run `node Tools/profiles.js` first.
if ! ls ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision >/dev/null 2>&1 || ! grep -lq "Poise Finance Dev" ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null; then
  echo "→ minting development profiles"; node Tools/profiles.js
fi

xcodegen generate --quiet

# The Finance extension ships only once the "Poise Finance Dev" profile carries FinanceKit; App Store Connect rejects a
# background-delivery extension without the entitlement, so until then the app is built without it.
FIN_PROFILE=$(grep -l "Poise Finance Dev" ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)
if [ -z "$FIN_PROFILE" ] || ! security cms -D -i "$FIN_PROFILE" 2>/dev/null | grep -q "com.apple.developer.financekit"; then
  echo "note: the Poise Finance Dev profile has no FinanceKit yet — building without the Finance extension (enable FinanceKit on com.koliokolev.poise.finance in the portal, then node Tools/profiles.js)"
  mkdir -p "$DEST"
  awk '/- target: PoiseFinance/ {skip=2} skip>0 {skip--; next} {print}' project.yml > "$DEST/project.pending.yml"
  xcodegen generate --quiet --spec "$DEST/project.pending.yml" --project-root . --project .
fi
xcodebuild \
  -project Poise.xcodeproj \
  -scheme Poise \
  -configuration "$CONFIG" \
  -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$DEST/DerivedData" \
  CONFIGURATION_BUILD_DIR="$DEST/$CONFIG-iphoneos" \
  build -quiet

xcrun devicectl device install app --device "$COREID" "$DEST/$CONFIG-iphoneos/Poise.app" >/dev/null
xcrun devicectl device process launch --device "$COREID" --terminate-existing "$BUNDLE" >/dev/null
echo "Poise running on $DEVNAME."
