#!/bin/zsh
# Archive a signed App Store build and upload it to App Store Connect (TestFlight).
#
#   scripts/testflight.sh ios     # iOS build
#   scripts/testflight.sh mac     # macOS build
#
# Prerequisites (one-time, see docs/TESTFLIGHT.md):
#   - Paid Apple Developer membership, agreements accepted in App Store Connect
#   - An App Store Connect app record for bundle ID com.mattreed.theoldpod
#     (one record hosts both iPhone and Mac).
#   - An App Store Connect API key. Point the script at it via env vars:
#       ASC_KEY_ID     the key's Key ID (e.g. from AuthKey_<KEYID>.p8)
#       ASC_ISSUER_ID  the team's Issuer ID (Users and Access → Integrations)
#       ASC_KEY_PATH   path to the .p8 (default: ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
#
# Bump the build number in project.yml (CFBundleVersion) before each upload —
# App Store Connect rejects a duplicate build number.
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:-}"
case "$PLATFORM" in
  ios)
    SCHEME="TheOldPod-iOS"
    DESTINATION="generic/platform=iOS"
    EXPORT_PLIST="scripts/ExportOptions-iOS.plist"
    ;;
  mac)
    SCHEME="TheOldPod-macOS"
    DESTINATION="generic/platform=macOS"
    EXPORT_PLIST="scripts/ExportOptions-macOS.plist"
    ;;
  *)
    echo "usage: scripts/testflight.sh [ios|mac]" >&2
    exit 1
    ;;
esac

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer id)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "API key not found at $ASC_KEY_PATH" >&2; exit 1; }

AUTH=(-authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

ARCHIVE=".build/${SCHEME}.xcarchive"

make gen

echo "▸ Archiving $SCHEME…"
xcodebuild -project TheOldPod.xcodeproj -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" \
  archive -allowProvisioningUpdates "${AUTH[@]}"

echo "▸ Exporting + uploading to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates "${AUTH[@]}"

echo "✓ Uploaded. It appears in App Store Connect → TestFlight after processing (~5–15 min)."
