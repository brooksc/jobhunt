# shellcheck shell=bash
# Ensure a full Xcode toolchain is active for xcodebuild.
#
# A common local state is that `xcode-select` points at the Command Line Tools
# (`/Library/Developer/CommandLineTools`), which makes xcodebuild fail with:
#   xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
#   '/Library/Developer/CommandLineTools' is a command line tools instance
#
# When that happens, auto-select an installed Xcode by exporting DEVELOPER_DIR for THIS process only
# — no sudo and no global `xcode-select -s` change. SOURCE this file (don't execute it) so the
# exported DEVELOPER_DIR reaches the caller's xcodebuild invocations.

# Already usable? (respects a valid `xcode-select -s` or an explicit DEVELOPER_DIR)
if xcodebuild -version >/dev/null 2>&1; then
    return 0 2>/dev/null || exit 0
fi

for _xc in \
    "${DEVELOPER_DIR:-}" \
    "/Applications/Xcode.app/Contents/Developer" \
    "/Applications/Xcode-beta.app/Contents/Developer"; do
    [ -n "$_xc" ] && [ -x "$_xc/usr/bin/xcodebuild" ] || continue
    if DEVELOPER_DIR="$_xc" xcodebuild -version >/dev/null 2>&1; then
        export DEVELOPER_DIR="$_xc"
        echo "→ xcode-select points at Command Line Tools; using Xcode at $DEVELOPER_DIR"
        return 0 2>/dev/null || exit 0
    fi
done

# Last resort: ask Spotlight for any installed Xcode.
_xc_found="$(mdfind 'kMDItemCFBundleIdentifier == com.apple.dt.Xcode' 2>/dev/null | head -1)"
if [ -n "$_xc_found" ] && [ -x "$_xc_found/Contents/Developer/usr/bin/xcodebuild" ]; then
    export DEVELOPER_DIR="$_xc_found/Contents/Developer"
    echo "→ Using Xcode at $DEVELOPER_DIR"
    return 0 2>/dev/null || exit 0
fi

echo "✗ No full Xcode toolchain found (xcode-select points at Command Line Tools)." >&2
echo "  Install Xcode, then either let this script find it or run once:" >&2
echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
return 1 2>/dev/null || exit 1
