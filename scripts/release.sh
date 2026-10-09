#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your saved notarization Keychain profile}"
version=${VERSION:-1.2.0}
VERSION="$version" scripts/build.sh
app="dist/Marginal.app"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" dist/notarization.zip
xcrun notarytool submit dist/notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
rm dist/notarization.zip
archive="dist/Marginal-$version-macOS.zip"
rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive"
(cd dist && shasum -a 256 "Marginal-$version-macOS.zip" > "Marginal-$version-SHA256.txt")
printf 'Release files ready in dist/\n'
