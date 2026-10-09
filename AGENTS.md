# Local build and release workflow

Run all builds, tests, packaging, signing, and release preparation locally. Do not add or use GitHub Actions for this project.

Use `swift test` and `python3 scripts/test-appcast.py` for validation, `scripts/build.sh` for local development builds, and `scripts/publish-release.sh <version>` for releases. The release script builds, tests, signs, notarizes, and smoke-tests locally before uploading the finished artifacts and update feed. On this Mac, use `NOTARY_PROFILE=renoir-notary`.

GitHub hosts source, release downloads, and the Sparkle update feed.
