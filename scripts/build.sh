#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${VERSION:-1.3.0}
configuration=${CONFIGURATION:-release}
feed_url=${MARGINAL_FEED_URL:-https://raw.githubusercontent.com/acousland/marginal/main/appcast.xml}
public_key=$(tr -d '[:space:]' < Resources/sparkle-public-key)
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be major.minor.patch" >&2
  exit 1
fi
mkdir -p dist
swift build -c "$configuration" --arch arm64
bin_dir=$(swift build -c "$configuration" --arch arm64 --show-bin-path)
app="dist/Marginal.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/Marginal" "$app/Contents/MacOS/Marginal"
ditto "$bin_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $version" "$app/Contents/Info.plist"
# Set MARGINAL_FEED_URL=none to build a trial copy without update checks.
if [[ $feed_url != none ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $feed_url" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$app/Contents/Info.plist"
fi
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp .build/checkouts/swift-markdown/LICENSE.txt "$app/Contents/Resources/Swift-Markdown-LICENSE.txt"
cp .build/checkouts/swift-markdown/NOTICE.txt "$app/Contents/Resources/Swift-Markdown-NOTICE.txt"
cp .build/checkouts/swift-cmark/COPYING "$app/Contents/Resources/Swift-cmark-LICENSE.txt"
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
# Sign Sparkle's nested helpers from the inside out. Ad-hoc builds omit the hardened runtime.
identity=${SIGNING_IDENTITY:--}
if [[ $identity == - ]]; then
  sign=(codesign --force --timestamp=none --sign -)
else
  sign=(codesign --force --options runtime --timestamp --sign "$identity")
fi
sparkle="$app/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
"${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
"${sign[@]}" "$sparkle/Versions/B/Autoupdate"
"${sign[@]}" "$sparkle/Versions/B/Updater.app"
"${sign[@]}" "$sparkle"
"${sign[@]}" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
