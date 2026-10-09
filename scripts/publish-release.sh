#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:-}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: scripts/publish-release.sh major.minor.patch" >&2
  exit 1
fi
repo=acousland/marginal
tag="v$version"
if [[ -n $(git status --porcelain) ]]; then
  echo "Commit your changes before publishing a release" >&2
  exit 1
fi
if [[ $(git branch --show-current) != main ]]; then
  echo "Publish releases from main" >&2
  exit 1
fi
gh auth status >/dev/null
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  echo "Release $tag already exists" >&2
  exit 1
fi
git fetch --quiet origin main --tags
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag $tag already exists" >&2
  exit 1
fi
if [[ $(git rev-parse HEAD) != $(git rev-parse origin/main) ]]; then
  echo "Push main before publishing, so the release points to published source" >&2
  exit 1
fi
if [[ $(head -1 RELEASE_NOTES.md) != "# Marginal $version" ]]; then
  echo "RELEASE_NOTES.md must start with # Marginal $version" >&2
  exit 1
fi
identity=${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}
: "${identity:?No Developer ID Application signing identity found}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your saved notarization Keychain profile}"
swift test
python3 scripts/test-appcast.py
VERSION="$version" SIGNING_IDENTITY="$identity" scripts/release.sh
dist/Marginal.app/Contents/MacOS/Marginal --smoke-test
dist/Marginal.app/Contents/MacOS/Marginal --display-smoke-test
dist/Marginal.app/Contents/MacOS/Marginal --table-smoke-test
if [[ $(lipo -archs dist/Marginal.app/Contents/MacOS/Marginal) != arm64 ]]; then
  echo "The release app must be Apple silicon only" >&2
  exit 1
fi
# Upload the signed archive before making it discoverable through the feed.
git tag -a "$tag" -m "Marginal $version"
git push origin "$tag"
gh release create "$tag" "dist/Marginal-$version-macOS.zip" "dist/Marginal-$version-SHA256.txt" \
  --repo "$repo" --verify-tag --latest --title "Marginal $version" --notes-file RELEASE_NOTES.md
curl --fail --location --retry 5 --retry-all-errors --retry-delay 3 --range 0-0 --output /dev/null \
  "https://github.com/$repo/releases/download/$tag/Marginal-$version-macOS.zip"
cp dist/appcast.xml appcast.xml
git add appcast.xml
git commit -m "Publish Sparkle feed for Marginal $version"
git push origin main
printf 'Published %s and its signed Sparkle update feed\n' "$tag"
