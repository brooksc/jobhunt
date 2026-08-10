#!/usr/bin/env bash
# Build the Firefox add-on artifact (TASK-619).
#
# Same source as the Chrome extension — the capture, queue and payload code is plain JS that both
# browsers run — with the Firefox manifest swapped in. Two differences it encodes:
#
#   * Firefox MV3 has no `service_worker`; it uses `background.scripts` (an event page).
#   * Chrome's `key` is dropped. That field pins the *unpacked Chrome* extension id and means nothing
#     to Firefox, whose identity comes from `browser_specific_settings.gecko.id`.
#
# Produces an unsigned zip. Signing is AMO's job and needs an account this repo doesn't have — see
# TASK-619 for what remains.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="build"
STAGE="$OUT_DIR/firefox-extension"
VERSION=$(python3 -c "import json;print(json.load(open('extension/manifest.firefox.json'))['version'])")
ARTIFACT="$OUT_DIR/jobhunt-firefox-${VERSION}.zip"

rm -rf "$STAGE"
mkdir -p "$STAGE"

# Copy the shared sources, then overwrite the manifest. Explicit list rather than `cp -r` so a stray
# file in extension/ can't end up in a published artifact.
for file in capture.js export_csv.js note.html note.js Readability.js retry_queue.js \
    launch_app.js service_worker.js status.html status.js; do
    cp "extension/$file" "$STAGE/"
done
cp -R extension/icons "$STAGE/icons"
[ -d extension/styles ] && cp -R extension/styles "$STAGE/styles"
cp extension/manifest.firefox.json "$STAGE/manifest.json"

# Version parity with the Chrome manifest — shipping two browsers on different versions makes every
# future bug report ambiguous.
CHROME_VERSION=$(python3 -c "import json;print(json.load(open('extension/manifest.json'))['version'])")
if [ "$VERSION" != "$CHROME_VERSION" ]; then
    echo "ERROR: firefox manifest is $VERSION but chrome is $CHROME_VERSION" >&2
    exit 1
fi

rm -f "$ARTIFACT"
(cd "$STAGE" && zip -qr "../../$ARTIFACT" .)
echo "Built $ARTIFACT"
