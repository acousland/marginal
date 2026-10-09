#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${VERSION:-1.2.0}
configuration=${CONFIGURATION:-release}
mkdir -p dist
swift build -c "$configuration" --arch arm64
binary="$(swift build -c "$configuration" --arch arm64 --show-bin-path)/Marginal"
app="dist/Marginal.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Marginal"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $version" "$app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp .build/checkouts/swift-markdown/LICENSE.txt "$app/Contents/Resources/Swift-Markdown-LICENSE.txt"
cp .build/checkouts/swift-markdown/NOTICE.txt "$app/Contents/Resources/Swift-Markdown-NOTICE.txt"
cp .build/checkouts/swift-cmark/COPYING "$app/Contents/Resources/Swift-cmark-LICENSE.txt"
codesign --force --options runtime --timestamp=none --sign - "$app"
printf 'Built %s\n' "$app"
