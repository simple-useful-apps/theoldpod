#!/bin/zsh
# Archive a signed App Store build and upload it to App Store Connect (TestFlight).
#
#   scripts/testflight.sh ios     # iOS build
#   scripts/testflight.sh mac     # macOS build
#
# Prerequisites (one-time, see docs/TESTFLIGHT.md):
#   - Paid Apple Developer membership, agreements accepted in App Store Connect
#   - An App Store Connect app record for the bundle ID (iOS: com.mattreed.theoldpod,
#     mac: com.mattreed.theoldpod.mac)
#   - App-specific-password auth set up once:
#       xcrun notarytool store-credentials  (or the App Store Connect API key below)
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

ARCHIVE=".build/${SCHEME}.xcarchive"

make gen

echo "▸ Archiving $SCHEME…"
xcodebuild -project TheOldPod.xcodeproj -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" \
  archive -allowProvisioningUpdates

echo "▸ Exporting + uploading to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates

echo "✓ Uploaded. It appears in App Store Connect → TestFlight after processing (~5–15 min)."
