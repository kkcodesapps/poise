#!/bin/bash
# Archives Poise for the App Store (Release, "Apple Distribution" + the *Dist profiles from Tools/profiles.js), exports an
# App Store Connect package and uploads it to TestFlight with the ASC API key in ~/.appstoreconnect/private_keys.
#   Tools/testflight.sh [patch|minor|major]   bump MARKETING_VERSION in project.yml (default: patch), archive, upload,
#                                             then set What to Test from CHANGELOG.md once Apple has processed the build
#   Tools/testflight.sh --no-bump             keep the version (re-upload of the same version)
#   Tools/testflight.sh --no-upload           stop after the export (checks signing; no bump, no build number spent)
# Every change ships as a new version — write its CHANGELOG.md section first. The build number is the minute of the
# run (YYYYMMDD.HHMM), so every upload is newer than the last.
set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD=1; BUMP="patch"
case "${1:-}" in
  --no-upload) UPLOAD=0; BUMP="" ;;
  --no-bump) BUMP="" ;;
  patch|minor|major) BUMP="$1" ;;
  "") ;;
  *) echo "usage: Tools/testflight.sh [patch|minor|major|--no-bump|--no-upload]"; exit 1 ;;
esac
DEST="$PWD/build"
BUILD="$(date +%Y%m%d.%H%M)"

CURRENT=$(sed -nE 's/^ *MARKETING_VERSION: "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' project.yml | head -1)
if [ -n "$BUMP" ]; then
  IFS=. read -r MA MI PA <<< "$CURRENT"
  case "$BUMP" in major) MA=$((MA + 1)); MI=0; PA=0 ;; minor) MI=$((MI + 1)); PA=0 ;; patch) PA=$((PA + 1)) ;; esac
  VERSION="$MA.$MI.$PA"
  grep -q "^## $VERSION" CHANGELOG.md || { echo "CHANGELOG.md has no '## $VERSION' section — write what changed first"; exit 1; }
  sed -i '' -E "s/^( *MARKETING_VERSION: )\"$CURRENT\"/\1\"$VERSION\"/" project.yml
  echo "→ version $CURRENT → $VERSION"
else
  VERSION="$CURRENT"
fi
KEY=$(ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1)
[ -n "$KEY" ] || { echo "no AuthKey_*.p8 in ~/.appstoreconnect/private_keys"; exit 1; }
KEY_ID=$(basename "$KEY" .p8 | sed 's/^AuthKey_//')
ISSUER="${ASC_ISSUER_ID:-f7b84198-2497-4bd0-9756-251815113d7a}"

if ! grep -lq "Poise Finance Dist" ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null; then
  echo "→ minting profiles"; node Tools/profiles.js
fi

xcodegen generate --quiet

# The Finance extension ships only once the "Poise Finance Dist" profile carries FinanceKit; App Store Connect rejects a
# background-delivery extension without the entitlement, so until then the app is built without it.
FIN_PROFILE=$(grep -l "Poise Finance Dist" ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)
if [ -z "$FIN_PROFILE" ] || ! security cms -D -i "$FIN_PROFILE" 2>/dev/null | grep -q "com.apple.developer.financekit"; then
  echo "note: the Poise Finance Dist profile has no FinanceKit yet — building without the Finance extension (enable FinanceKit on com.koliokolev.poise.finance in the portal, then node Tools/profiles.js)"
  mkdir -p "$DEST"
  awk '/- target: PoiseFinance/ {skip=2} skip>0 {skip--; next} {print}' project.yml > "$DEST/project.pending.yml"
  xcodegen generate --quiet --spec "$DEST/project.pending.yml" --project-root . --project .
fi
rm -rf "$DEST/Poise.xcarchive" "$DEST/export"
xcodebuild \
  -project Poise.xcodeproj -scheme Poise -configuration Release -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DEST/DerivedData" \
  -archivePath "$DEST/Poise.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive -quiet

cat > "$DEST/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>D6937U28B4</string>
  <key>uploadSymbols</key><true/>
  <key>provisioningProfiles</key><dict>
    <key>com.koliokolev.poise</key><string>Poise Dist</string>
    <key>com.koliokolev.poise.widgets</key><string>Poise Widgets Dist</string>
    <key>com.koliokolev.poise.finance</key><string>Poise Finance Dist</string>
  </dict>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$DEST/Poise.xcarchive" -exportOptionsPlist "$DEST/ExportOptions.plist" -exportPath "$DEST/export" -quiet
IPA=$(ls "$DEST/export"/*.ipa | head -1)
echo "Exported $(basename "$IPA") — version $VERSION ($BUILD)"

if [ "$UPLOAD" = 1 ]; then
  xcrun altool --upload-app --type ios --file "$IPA" --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | grep -vE "^\s*$" | tail -5
  echo "Uploaded Poise $VERSION ($BUILD) — it shows in App Store Connect → TestFlight after processing (10–30 min)."
  node Tools/whatsnew.js "$VERSION" "$BUILD"
fi
