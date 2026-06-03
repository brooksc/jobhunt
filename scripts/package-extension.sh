#!/bin/sh
# Package the Chrome extension into chromestore/.
# Usage: ./scripts/package-extension.sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_DIR="$REPO_ROOT/extension"
OUT_DIR="$REPO_ROOT/chromestore"

VERSION=$(node -e "console.log(require('$EXT_DIR/manifest.json').version)")
ZIP="$OUT_DIR/jobhunt-capture-${VERSION}.zip"

mkdir -p "$OUT_DIR"

# Remove stale zip for this version if present
rm -f "$ZIP"

cd "$EXT_DIR"
zip -r "$ZIP" . --exclude "*.DS_Store"

echo "Created $ZIP"
