#!/bin/sh
# Increment the shared version in package.json and extension/manifest.json.
# Usage: ./scripts/bump-version.sh [patch|minor|major]
#   patch (default) — z++
#   minor           — y++, z=0
#   major           — x++, y=0, z=0
# Prints the new version to stdout.
set -e

BUMP="${1:-patch}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO_ROOT/package.json"
MANIFEST="$REPO_ROOT/extension/manifest.json"

CURRENT=$(node -e "console.log(require('$PKG').version)")

MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "Usage: bump-version.sh [patch|minor|major]" >&2; exit 1 ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"

node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('$PKG', 'utf8'));
pkg.version = '$NEW';
fs.writeFileSync('$PKG', JSON.stringify(pkg, null, 2) + '\n');
"

node -e "
const fs = require('fs');
const m = JSON.parse(fs.readFileSync('$MANIFEST', 'utf8'));
m.version = '$NEW';
fs.writeFileSync('$MANIFEST', JSON.stringify(m, null, 2) + '\n');
"

echo "$NEW"
