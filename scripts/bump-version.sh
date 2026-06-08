#!/usr/bin/env bash
# Bump the shared version across package.json, extension/manifest.json, and Project.swift (Tuist).
#
# Usage (explicit version):
#   ./scripts/bump-version.sh 1.2.3
#
# Usage (semver increment, legacy):
#   ./scripts/bump-version.sh [patch|minor|major]   (default: patch)
#
# Prints the new version to stdout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO_ROOT/package.json"
MANIFEST="$REPO_ROOT/extension/manifest.json"
PROJECT_SWIFT="$REPO_ROOT/Project.swift"

ARG="${1:-patch}"

# Determine whether the argument is an explicit version or a semver bump keyword.
if [[ "$ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # Explicit version string (e.g. 1.2.3)
  NEW="$ARG"
  BUILD=$(date +%Y%m%d%H%M)

  # Update Tuist marketing + build versions if Project.swift exists.
  if [ -f "$PROJECT_SWIFT" ]; then
    sed -i '' "s/.marketingVersion(\"[0-9.]*\")/.marketingVersion(\"$NEW\")/g" "$PROJECT_SWIFT"
    sed -i '' "s/.currentProjectVersion(\"[0-9]*\")/.currentProjectVersion(\"$BUILD\")/g" "$PROJECT_SWIFT"
  fi

  # Update extension manifest if present.
  if [ -f "$MANIFEST" ]; then
    sed -i '' "s/\"version\": \"[0-9.]*\"/\"version\": \"$NEW\"/g" "$MANIFEST"
  fi

  # Update package.json if present (node not required for explicit-version path).
  if [ -f "$PKG" ]; then
    node -e "
      const fs = require('fs');
      const pkg = JSON.parse(fs.readFileSync('$PKG', 'utf8'));
      pkg.version = '$NEW';
      fs.writeFileSync('$PKG', JSON.stringify(pkg, null, 2) + '\n');
    " 2>/dev/null || sed -i '' "s/\"version\": \"[0-9.]*\"/\"version\": \"$NEW\"/g" "$PKG"
  fi

  git add "${PROJECT_SWIFT:-}" "${MANIFEST:-}" "${PKG:-}" 2>/dev/null || true
  git commit -m "chore: bump version to $NEW"

else
  # Legacy semver-increment mode (patch | minor | major).
  BUMP="$ARG"

  if [ ! -f "$PKG" ]; then
    echo "package.json not found; use explicit version: bump-version.sh <x.y.z>" >&2
    exit 1
  fi

  CURRENT=$(node -e "console.log(require('$PKG').version)")
  MAJOR=$(echo "$CURRENT" | cut -d. -f1)
  MINOR=$(echo "$CURRENT" | cut -d. -f2)
  PATCH=$(echo "$CURRENT" | cut -d. -f3)

  case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "Usage: bump-version.sh [<x.y.z>|patch|minor|major]" >&2; exit 1 ;;
  esac

  NEW="${MAJOR}.${MINOR}.${PATCH}"
  BUILD=$(date +%Y%m%d%H%M)

  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('$PKG', 'utf8'));
    pkg.version = '$NEW';
    fs.writeFileSync('$PKG', JSON.stringify(pkg, null, 2) + '\n');
  "

  if [ -f "$MANIFEST" ]; then
    node -e "
      const fs = require('fs');
      const m = JSON.parse(fs.readFileSync('$MANIFEST', 'utf8'));
      m.version = '$NEW';
      fs.writeFileSync('$MANIFEST', JSON.stringify(m, null, 2) + '\n');
    "
  fi

  if [ -f "$PROJECT_SWIFT" ]; then
    sed -i '' "s/.marketingVersion(\"[0-9.]*\")/.marketingVersion(\"$NEW\")/g" "$PROJECT_SWIFT"
    sed -i '' "s/.currentProjectVersion(\"[0-9]*\")/.currentProjectVersion(\"$BUILD\")/g" "$PROJECT_SWIFT"
  fi
fi

echo "$NEW"
