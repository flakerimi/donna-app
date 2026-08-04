#!/usr/bin/env bash
# Sign (creating the distribution cert if needed) and upload the existing
# archive to TestFlight using an App Store Connect API key — no interactive
# Xcode login required.
#
# Usage: ASC_ISSUER_ID=<uuid> ./upload-testflight.sh
# The GODOT key (Q2KWKV5PY2) must have App Manager or Admin role.
set -euo pipefail
cd "$(dirname "$0")"

: "${ASC_ISSUER_ID:?paste the App Store Connect Issuer ID: ASC_ISSUER_ID=... ./upload-testflight.sh}"
KEY_ID="${ASC_KEY_ID:-Q2KWKV5PY2}"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
ARCHIVE="build/ios/archive/Runner.xcarchive"

[[ -f "$KEY_PATH" ]] || { echo "missing key: $KEY_PATH" >&2; exit 1; }
[[ -d "$ARCHIVE" ]] || { echo "missing archive: $ARCHIVE — run flutter build ipa first" >&2; exit 1; }

# -exportArchive with destination=upload both distribution-signs (creating the
# Apple Distribution cert + App Store profile via the API key) and uploads.
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions-appstore.plist \
  -exportPath build/ios/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "uploaded ✓ — App Store Connect → TestFlight (processing ~10 min)"
