#!/bin/sh
# Build the Electron app. Outputs to dist/.
# Usage: ./scripts/build-electron.sh [--dist]
#   (no args)  Build unpacked app only (faster, good for local testing)
#   --dist     Also produce a distributable DMG
set -eu

cd "$(dirname "$0")/.."

if [ "${1:-}" = "--dist" ]; then
  echo "Building distributable DMG..."
  nice ./node_modules/.bin/electron-builder --mac
else
  echo "Building unpacked app..."
  nice ./node_modules/.bin/electron-builder --dir --mac
fi

echo ""
echo "Done. Output: dist/"
ls dist/
