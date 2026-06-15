#!/usr/bin/env bash
# Bump the shared version across Project.swift (Tuist) and extension/manifest.json.
# Current version is read from Project.swift marketingVersion — no package.json needed.
#
# Usage (semver increment):
#   ./scripts/bump-version.sh patch   # z++
#   ./scripts/bump-version.sh minor   # y++, z=0
#   ./scripts/bump-version.sh major   # x++, y=0, z=0
#
# Usage (explicit version):
#   ./scripts/bump-version.sh 1.2.3
#
# Prints the new version to stdout. Does not auto-commit.
#
# This updates ONLY: Project.swift (.marketingVersion + .currentProjectVersion) and
# extension/manifest.json (.version). version-parity.yml checks these two agree.
# MUST be refreshed MANUALLY at release time (this script does NOT touch them):
#   - chromestore/store-listing.md   — the "Version" row and the "Extension zip" filename
#   - the built chromestore/jobhunt-capture-<version>.zip artifact
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO_ROOT/extension/manifest.json"
PROJECT_SWIFT="$REPO_ROOT/Project.swift"

ARG="${1:-patch}"

if [ ! -f "$PROJECT_SWIFT" ]; then
  echo "Project.swift not found at $PROJECT_SWIFT" >&2
  exit 1
fi

# Read current version from Project.swift marketingVersion field.
CURRENT=$(grep -o '\.marketingVersion("[0-9.]*")' "$PROJECT_SWIFT" | grep -o '"[0-9.]*"' | tr -d '"')
if [ -z "$CURRENT" ]; then
  echo "Could not read .marketingVersion from $PROJECT_SWIFT" >&2
  exit 1
fi

# Determine new version from argument.
if [[ "$ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  NEW="$ARG"
else
  MAJOR=$(echo "$CURRENT" | cut -d. -f1)
  MINOR=$(echo "$CURRENT" | cut -d. -f2)
  PATCH=$(echo "$CURRENT" | cut -d. -f3)
  case "$ARG" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "Usage: bump-version.sh [<x.y.z>|patch|minor|major]" >&2; exit 1 ;;
  esac
  NEW="${MAJOR}.${MINOR}.${PATCH}"
fi

BUILD=$(date +%Y%m%d%H%M)

# Update Project.swift marketing + build versions.
sed -i '' "s/\.marketingVersion(\"[0-9.]*\")/.marketingVersion(\"$NEW\")/g" "$PROJECT_SWIFT"
sed -i '' "s/\.currentProjectVersion(\"[0-9]*\")/.currentProjectVersion(\"$BUILD\")/g" "$PROJECT_SWIFT"

# Update extension manifest if present.
if [ -f "$MANIFEST" ]; then
  sed -i '' "s/\"version\": \"[0-9.]*\"/\"version\": \"$NEW\"/g" "$MANIFEST"
fi

echo "$NEW"
