#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your saved notarization Keychain profile}"
version=${VERSION:-1.2.3}
if [[ $SIGNING_IDENTITY == - ]]; then
  echo "Releases require a Developer ID Application signing identity" >&2
  exit 1
fi
VERSION="$version" MARGINAL_FEED_URL=https://raw.githubusercontent.com/acousland/marginal/main/appcast.xml scripts/build.sh
app="dist/Marginal.app"
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
# The archive is signed only after notarization and stapling have finished.
sparkle_bin=".build/artifacts/sparkle/Sparkle/bin"
public_key=$(tr -d '[:space:]' < Resources/sparkle-public-key)
if [[ $("$sparkle_bin/generate_keys" --account marginal -p) != "$public_key" ]]; then
  echo "The marginal Keychain signing key does not match the app's update key" >&2
  exit 1
fi
signature_line=$("$sparkle_bin/sign_update" --account marginal "$archive")
signature=$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$signature_line")
length=$(sed -E 's/.*length="([0-9]+)".*/\1/' <<<"$signature_line")
python3 scripts/update-appcast.py --version "$version" --signature "$signature" --length "$length" \
  --notes RELEASE_NOTES.md < appcast.xml > dist/appcast.xml
printf 'Signed, notarized release and Sparkle feed ready in dist/\n'
