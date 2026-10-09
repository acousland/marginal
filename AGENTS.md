# Local build and release workflow

Run all builds, tests, packaging, signing, and release preparation locally. Do not add or use GitHub Actions for this project.

Use `swift test` and `python3 scripts/test-appcast.py` for validation, `scripts/build.sh` for local development builds, and `scripts/publish-release.sh <version>` for releases. The release script builds, tests, signs, notarizes, and smoke-tests locally before uploading the finished artifacts and update feed. On this Mac, use `NOTARY_PROFILE=renoir-notary`.

The release checks include live-window display tests covering zoom, scrolling, word wrap, source mode, and table selection/editing. Run `dist/Marginal.app/Contents/MacOS/Marginal --display-smoke-test` and `--table-smoke-test` after changes to editor layout or drawing.

GitHub hosts source, release downloads, and the Sparkle update feed.
