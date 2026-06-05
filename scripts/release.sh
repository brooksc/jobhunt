#!/bin/sh
# Cut a release: bump minor version, commit + tag, build DMG and extension zip.
# Usage: ./scripts/release.sh
set -eu

cd "$(dirname "$0")/.."

NEW_VERSION=$(./scripts/bump-version.sh minor)
echo "Releasing v${NEW_VERSION}..."

git add package.json extension/manifest.json
git commit -m "chore: release v${NEW_VERSION}"
git tag "v${NEW_VERSION}"

echo ""
echo "Building Electron DMG..."
./scripts/build-electron.sh --dist

echo ""
echo "Packaging extension..."
./scripts/package-extension.sh

echo ""
echo "Release v${NEW_VERSION} complete. Artifacts:"
ls dist/*.dmg 2>/dev/null || true
ls chromestore/*.zip 2>/dev/null || true
