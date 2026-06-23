#!/bin/sh
# Package the Chrome extension into chromestore/.
# Uses an explicit allowlist via a staging directory to exclude dev/test files.
# Usage: ./scripts/package-extension.sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_DIR="$REPO_ROOT/extension"
OUT_DIR="$REPO_ROOT/chromestore"

VERSION=$(node -e "console.log(require('$EXT_DIR/manifest.json').version)")
ZIP="$OUT_DIR/jobhunt-capture-${VERSION}.zip"

mkdir -p "$OUT_DIR"

# TASK-418: remove ALL previously-built extension zips so chromestore/ holds exactly the zip this run
# produces — a stale older-version zip can't be mistaken for the current submission artifact. The zip
# name is version-stamped from manifest.json, so the output is authoritative-by-construction.
rm -f "$OUT_DIR"/jobhunt-capture-*.zip

# Build into a clean staging directory so only allowlisted files are included
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Allowlisted files and directories
cp "$EXT_DIR/manifest.json"         "$STAGING/manifest.json"
# Strip the dev-only `key`: it pins the *unpacked* extension id so a release app build can be
# dogfooded with a locally-loaded extension (see JobhuntServer.developmentExtensionOrigin). The Web
# Store assigns the published id itself and rejects a non-matching manifest key, so the uploaded zip
# must not carry it.
node -e "const fs=require('fs'),p='$STAGING/manifest.json',m=JSON.parse(fs.readFileSync(p));delete m.key;fs.writeFileSync(p,JSON.stringify(m,null,2)+'\n')"
cp "$EXT_DIR/popup.html"            "$STAGING/popup.html"  2>/dev/null || true
cp "$EXT_DIR/Readability.js"        "$STAGING/Readability.js"
cp "$EXT_DIR/capture.js"            "$STAGING/capture.js"
cp "$EXT_DIR/service_worker.js"     "$STAGING/service_worker.js"
cp "$EXT_DIR/retry_queue.js"        "$STAGING/retry_queue.js"
cp "$EXT_DIR/export_csv.js"         "$STAGING/export_csv.js"
cp "$EXT_DIR/note.js"               "$STAGING/note.js"
cp "$EXT_DIR/note.html"             "$STAGING/note.html"
cp "$EXT_DIR/note.css"              "$STAGING/note.css"
cp "$EXT_DIR/status.js"             "$STAGING/status.js"
cp "$EXT_DIR/status.html"           "$STAGING/status.html"
cp "$EXT_DIR/status.css"            "$STAGING/status.css"
cp -r "$EXT_DIR/icons"              "$STAGING/icons"
cp "$REPO_ROOT/THIRD_PARTY_NOTICES.md" "$STAGING/THIRD_PARTY_NOTICES.md"

# Excluded: tests/, package.json, package-lock.json, node_modules/, *.test.js, *.spec.js

cd "$STAGING"
zip -r "$ZIP" . --exclude "*.DS_Store"

echo "Created $ZIP"
echo ""
echo "Package contents:"
unzip -l "$ZIP"
