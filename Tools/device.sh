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

# Provisioning updates (registering the App ID's capabilities, minting profiles) authenticate with an App Store Connect
# API key when one is installed, so no Apple ID has to be signed into Xcode on this Mac.
AUTH=()
KEY=$(ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1 || true)
if [ -n "${KEY:-}" ]; then
  KEY_ID=$(basename "$KEY" .p8 | sed 's/^AuthKey_//')
  ISSUER="${ASC_ISSUER_ID:-f7b84198-2497-4bd0-9756-251815113d7a}"
  AUTH=(-authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
fi

xcodegen generate --quiet
xcodebuild \
  -project Poise.xcodeproj \
  -scheme Poise \
  -configuration "$CONFIG" \
  -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$DEST/DerivedData" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  CONFIGURATION_BUILD_DIR="$DEST/$CONFIG-iphoneos" \
  build -quiet

xcrun devicectl device install app --device "$COREID" "$DEST/$CONFIG-iphoneos/Poise.app" >/dev/null
xcrun devicectl device process launch --device "$COREID" --terminate-existing "$BUNDLE" >/dev/null
echo "Poise running on $DEVNAME."
