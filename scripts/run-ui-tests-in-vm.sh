#!/usr/bin/env bash
# run-ui-tests-in-vm.sh
#
# Runs the AppUITests XCUITest suite inside an isolated Tart macOS VM so the
# test runner never hijacks focus or the mouse on the host machine.
#
# Strategy: build on the host (native Apple Silicon speed), then copy the
# pre-built test artifacts into the VM and run `xcodebuild test-without-building`.
# This is significantly faster than building inside the VM.
#
# ASSUMPTIONS:
#   - Host: Apple Silicon (M1/M2/M3/M4)
#   - Tart CLI:      brew install cirruslabs/cli/tart
#   - sshpass:       brew install hudochenkov/sshpass/sshpass
#   - VM image:      ghcr.io/cirruslabs/macos-sequoia-xcode:latest
#   - VM credentials: admin / admin  (default for all cirruslabs images)
#   - Code signing is disabled for the test build (no provisioning needed)
#
# USAGE:
#   ./scripts/run-ui-tests-in-vm.sh [--scheme <scheme>] [--only-testing <target>] [--class <Class>] [--test <Class/method>] [--no-shutdown] [--regen]
#
# FLAGS:
#   --scheme <name>         Xcode scheme (default: Jobhunt-DMG)
#   --only-testing <target> Test target filter (default: AppUITests)
#   --class <Class>         Run only AppUITests/<Class>     (e.g. --class BehaviorUITests)
#   --test <Class/method>   Run only one method             (e.g. --test BehaviorUITests/testSidebarNav)
#   --no-shutdown           Leave the VM running after tests (useful for debugging)
#   --regen                 Run tuist generate --no-open before building
#
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

VM_NAME="jobhunt-uitest-env"
# Pinned to an immutable digest for reproducibility (TASK-403) — :latest silently drifts to new
# Xcode/macOS patches on each `tart clone`, breaking tests with no code change.
#   Image:  ghcr.io/cirruslabs/macos-sequoia-xcode  (macOS Sequoia 15.x, bundled latest Xcode)
#   Digest: sha256:31413f28df83c37b94e76f8feea8046fb1950b3ed42195523408477189a3f76d
#           (resolved from :latest on 2026-06-17)
# To upgrade: re-resolve `docker manifest inspect ghcr.io/cirruslabs/macos-sequoia-xcode:latest`
# (or `crane digest …`), update this digest + the date, and confirm the bundled Xcode/macOS in
# docs/vm-testing.md. Override per-run with `VM_IMAGE=…:26 ./scripts/run-ui-tests-in-vm.sh`.
VM_IMAGE="${VM_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-xcode@sha256:31413f28df83c37b94e76f8feea8046fb1950b3ed42195523408477189a3f76d}"

# Results (xcresult + screenshots) are copied back here before the VM is torn down.
HOST_RESULTS="build/vm-results"
GUEST_RESULT_BUNDLE="/tmp/jobhunt-uitest.xcresult"
GUEST_SCREENSHOTS="/tmp/jobhunt-screenshots"

# TASK-405: hard cap on the in-VM xcodebuild run so a launch crash / hung test host can't wedge the
# script forever. On timeout the guest exits 124 and the host EXIT trap shuts the VM down.
XCODEBUILD_TIMEOUT=900   # 15 minutes

SCHEME="Jobhunt-DMG"
ONLY_TESTING="AppUITests"
CONFIG="Debug-DMG"
PROJECT="Jobhunt.xcodeproj"

SSH_USER="admin"
SSH_PASS="admin"
# sshpass options: no host-key checking (new VM every clone), short connect timeout
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o PreferredAuthentications=password"

MOUNT_NAME="project"
GUEST_SRC="/Users/admin/src"
# Host-built test products land here (inside project dir so virtiofs shares them).
HOST_PRODUCTS="build/Jobhunt-testing"
# VM copies artifacts here before running test-without-building.
GUEST_PRODUCTS="/tmp/jobhunt-testing"

SHUTDOWN=true
REGEN=false
BUILD_ON_HOST=true   # Build on host (fast); VM only runs tests
MAX_IP_WAIT=120   # seconds to wait for VM to get an IP

# ── Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme)           SCHEME="$2"; shift 2 ;;
        --only-testing)     ONLY_TESTING="$2"; shift 2 ;;
        # TASK-404: convenience filters that expand to -only-testing under AppUITests, so iterating
        # on one class/method doesn't run the whole ~8-min suite.
        --class)            ONLY_TESTING="AppUITests/$2"; shift 2 ;;
        --test)             ONLY_TESTING="AppUITests/$2"; shift 2 ;;
        --no-shutdown)      SHUTDOWN=false; shift ;;
        --regen)            REGEN=true; shift ;;
        --build-in-vm)      BUILD_ON_HOST=false; shift ;;  # fall back to building inside VM
        *) echo "Usage: $0 [--scheme <scheme>] [--only-testing <target>] [--class <Class>] [--test <Class/method>] [--no-shutdown] [--regen] [--build-in-vm]" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
step() { echo; echo "▶ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

# Run a command inside the VM over SSH, streaming stdout/stderr to the host.
vm_ssh() {
    sshpass -p "$SSH_PASS" ssh $SSH_OPTS "${SSH_USER}@${VM_IP}" "$@"
}

# ── Optional: regenerate Xcode project ───────────────────────────────────────

if [ "$REGEN" = true ]; then
    step "Regenerating Xcode project (tuist generate)"
    command -v tuist >/dev/null 2>&1 || fail "tuist not found — cannot use --regen"
    tuist generate --no-open
    log "Project regenerated"
fi

# ── Preflight checks ─────────────────────────────────────────────────────────

step "Preflight"

command -v tart    >/dev/null 2>&1 || fail "tart not found. Install: brew install cirruslabs/cli/tart"
command -v sshpass >/dev/null 2>&1 || fail "sshpass not found. Install: brew install hudochenkov/sshpass/sshpass"

log "tart:    $(tart --version 2>/dev/null | head -1)"
log "project: $REPO_ROOT/$PROJECT"
log "scheme:  $SCHEME"

# ── Build on host (fast native compilation) ───────────────────────────────────

if [ "$BUILD_ON_HOST" = true ]; then
    step "Building for testing on host"
    log "Output: ${HOST_PRODUCTS}/"
    nice xcodebuild build-for-testing \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -derivedDataPath "$HOST_PRODUCTS" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_IDENTITY="" \
        CODE_SIGN_ENTITLEMENTS="" \
        2>&1 | grep -E "(error:|warning:.*error|BUILD SUCCEEDED|BUILD FAILED|Test Build Succeeded|Test Build Failed)" || true

    # Verify the xctestrun file was produced
    XCTESTRUN_HOST="$(ls "${HOST_PRODUCTS}/Build/Products/"*.xctestrun 2>/dev/null | head -1)"
    [ -n "$XCTESTRUN_HOST" ] || fail "Build succeeded but no .xctestrun found in ${HOST_PRODUCTS}/Build/Products/"
    log "xctestrun: $(basename "$XCTESTRUN_HOST")"
fi

# ── VM provisioning ──────────────────────────────────────────────────────────

step "VM provisioning"

if tart list 2>/dev/null | awk '{print $2}' | grep -q "^${VM_NAME}$"; then
    log "VM '$VM_NAME' already exists — reusing"
else
    log "Cloning $VM_IMAGE → $VM_NAME (this can take several minutes the first time)..."
    tart clone "$VM_IMAGE" "$VM_NAME"
    log "Clone complete"
fi

# ── Start VM ─────────────────────────────────────────────────────────────────

step "Starting VM"

# Kill any stale instance of this VM before starting fresh
if tart list 2>/dev/null | awk '{print $2, $NF}' | grep -q "^${VM_NAME} running"; then
    log "VM is already running — stopping stale instance..."
    tart stop "$VM_NAME" 2>/dev/null || true
    sleep 2
fi

log "Launching headlessly with project directory mounted..."
# --no-graphics: headless (no VM window on host)
# --dir:         virtiofs share; inside guest appears as /Volumes/My Shared Files/<MOUNT_NAME>
tart run "$VM_NAME" \
    --no-graphics \
    --dir="${MOUNT_NAME}:${REPO_ROOT}:ro" \
    &
TART_PID=$!

# Ensure VM is stopped on script exit unless --no-shutdown was passed
cleanup() {
    local exit_code=$?
    # Retrieve results before the VM is destroyed (best-effort; never fail teardown).
    if [ -n "${VM_IP:-}" ]; then
        step "Retrieving results to $HOST_RESULTS/"
        mkdir -p "$HOST_RESULTS"
        if sshpass -p "$SSH_PASS" scp $SSH_OPTS -r \
                "${SSH_USER}@${VM_IP}:${GUEST_RESULT_BUNDLE}" "$HOST_RESULTS/" 2>/dev/null; then
            log "xcresult → $HOST_RESULTS/$(basename "$GUEST_RESULT_BUNDLE")"
        else
            log "(no xcresult to retrieve)"
        fi
        if sshpass -p "$SSH_PASS" scp $SSH_OPTS -r \
                "${SSH_USER}@${VM_IP}:${GUEST_SCREENSHOTS}" "$HOST_RESULTS/" 2>/dev/null; then
            log "screenshots → $HOST_RESULTS/$(basename "$GUEST_SCREENSHOTS")"
        else
            log "(no screenshots to retrieve)"
        fi
    fi
    if [ "$SHUTDOWN" = true ]; then
        step "Teardown"
        log "Stopping VM '$VM_NAME'..."
        tart stop "$VM_NAME" 2>/dev/null || true
        log "VM stopped"
    else
        log "(--no-shutdown: VM '$VM_NAME' left running)"
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

# ── Wait for SSH ─────────────────────────────────────────────────────────────

step "Waiting for VM network"

log "Waiting up to ${MAX_IP_WAIT}s for IP address..."
# tart ip --wait blocks until the VM reports an IP (via ARP / vmnet)
VM_IP=$(tart ip "$VM_NAME" --wait "$MAX_IP_WAIT") \
    || fail "VM did not get an IP within ${MAX_IP_WAIT}s"
log "VM IP: $VM_IP"

log "Waiting for SSH to become stable (3 consecutive successes)..."
# On fresh VM clones, the macOS first-boot setup restarts sshd multiple times,
# causing intermittent auth failures even after SSH first accepts connections.
# Wait until we get 3 consecutive successful password-auth connections.
SSH_CONSEC=0
for i in $(seq 1 120); do
    if sshpass -p "$SSH_PASS" ssh $SSH_OPTS -o ConnectTimeout=5 \
            "${SSH_USER}@${VM_IP}" 'echo ready' 2>/dev/null | grep -q ready; then
        SSH_CONSEC=$((SSH_CONSEC + 1))
        if [ "$SSH_CONSEC" -ge 3 ]; then
            log "SSH stable (attempt $i, $SSH_CONSEC consecutive successes)"
            break
        fi
    else
        SSH_CONSEC=0
    fi
    if [ "$i" -eq 120 ]; then
        fail "SSH did not stabilize within 120 attempts (240s)"
    fi
    sleep 2
done

# ── Guest setup ───────────────────────────────────────────────────────────────

step "Configuring guest environment"

vm_ssh bash -s <<'GUEST_SETUP'
set -euo pipefail

# Disable sleep, display sleep, and screen-saver so UI automation elements
# remain hittable even if the test run is long.
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 >/dev/null
defaults write com.apple.screensaver idleTime 0
defaults write com.apple.screensaver askForPassword 0

# Clear any persisted window state from a prior run on this reused VM. A stale
# "no windows" saved state otherwise makes the app launch windowless even with
# -ApplePersistenceIgnoreState; removing it guarantees a clean first window.
rm -rf "$HOME/Library/Saved Application State/com.jobhunt-app.jobhunt.savedState" 2>/dev/null || true

# Mount the virtiofs share from the host.
# Tart exposes it under /Volumes/My Shared Files/<name> automatically on
# macOS 13+; we create a predictable symlink so xcodebuild can use a
# stable path that matches what the host reported.
GUEST_SRC="$HOME/src"
mkdir -p "$GUEST_SRC"

# Tart auto-mounts virtiofs shares at /Volumes/My Shared Files/<tag> on macOS 13+.
# The path contains spaces so we use null-delimited find and avoid xargs.
SHARE_ROOT="/Volumes/My Shared Files/project"
if [ ! -d "$SHARE_ROOT" ]; then
    echo "  auto-mount not found, mounting manually..."
    mkdir -p "$SHARE_ROOT"
    sudo mount -t virtiofs project "$SHARE_ROOT"
fi

# Walk down to find Jobhunt.xcodeproj — tart sometimes nests an extra level.
# Using -print0 + tr avoids word-splitting on the space in "My Shared Files".
XCODEPROJ="$(find "$SHARE_ROOT" -maxdepth 3 -name "Jobhunt.xcodeproj" -type d -print0 \
    2>/dev/null | tr '\0' '\n' | head -1)"
if [ -z "$XCODEPROJ" ]; then
    echo "ERROR: Jobhunt.xcodeproj not found under $SHARE_ROOT (depth 3)" >&2
    find "$SHARE_ROOT" -maxdepth 3 >&2 || true
    exit 1
fi
PROJ_DIR="$(dirname "$XCODEPROJ")"

# Write the resolved path to a temp file so GUEST_TEST can read it
# without having to re-discover it across a separate SSH session.
echo "$PROJ_DIR" > /tmp/jobhunt_proj_root

echo "  xcodeproj:    $XCODEPROJ"
echo "  project root: $PROJ_DIR"
echo "  Guest setup complete"
GUEST_SETUP

# ── Copy test artifacts to VM (build-on-host mode) ────────────────────────────

if [ "$BUILD_ON_HOST" = true ]; then
    step "Copying pre-built test artifacts to VM"
    log "Source (virtiofs): ${HOST_PRODUCTS}/Build/Products/"
    log "Destination (VM):  ${GUEST_PRODUCTS}/"

    # NOTE: single-quoted delimiter prevents host-side variable expansion in heredoc;
    # HOST_PRODUCTS and GUEST_PRODUCTS are hardcoded in the VM script below.
    vm_ssh bash -s <<'GUEST_COPY'
set -euo pipefail

SHARE_ROOT="/Volumes/My Shared Files/project"
HOST_PRODUCTS="build/Jobhunt-testing"
SRC="$SHARE_ROOT/$HOST_PRODUCTS/Build/Products"

if [ ! -d "$SRC" ]; then
    echo "ERROR: pre-built products not found at $SRC" >&2
    exit 1
fi

GUEST_PRODUCTS="/tmp/jobhunt-testing"
echo "  Removing old guest copy..."
rm -rf "$GUEST_PRODUCTS"
echo "  Copying $(du -sh "$SRC" | cut -f1) of build artifacts (using ditto for framework symlink compatibility)..."
# ditto is macOS-native and handles framework bundle symlinks correctly;
# plain cp -R fails on virtiofs with "Too many levels of symbolic links" for xattrs.
ditto "$SRC" "$GUEST_PRODUCTS"
echo "  Copy complete: $(du -sh "$GUEST_PRODUCTS" | cut -f1)"

# Re-sign all .xctest bundles with a fresh ad-hoc signature.
# Virtiofs + ditto can produce a binary whose host-built signature the VM's
# dyld rejects with "code signature invalid (errno=85)".  Force-signing with
# the local ad-hoc identity (-s -) gives dyld a signature it trusts.
echo "  Re-signing .xctest bundles with ad-hoc identity..."
find "$GUEST_PRODUCTS" -name "*.xctest" -type d | while read -r bundle; do
    codesign -f -s - "$bundle" 2>&1 | sed 's/^/    /'
done
echo "  Re-signing complete."
GUEST_COPY
fi  # BUILD_ON_HOST

# ── Run tests ─────────────────────────────────────────────────────────────────

step "Running XCUITest suite: $SCHEME"

log "Streaming test output from guest..."
echo "────────────────────────────────────────────────────────────────────────"

vm_ssh bash -s <<GUEST_TEST
set -uo pipefail

# Read the project root written by GUEST_SETUP (used in build-in-vm mode)
PROJ_DIR="\$(cat /tmp/jobhunt_proj_root)"

# TASK-405: a timeout wrapper so a hung xcodebuild can't run forever. macOS has no \`timeout\` by
# default, so fall back to coreutils' \`gtimeout\`; if neither is present, run unguarded with a warning.
TIMEOUT_BIN="\$(command -v timeout || command -v gtimeout || true)"
if [ -n "\$TIMEOUT_BIN" ]; then
    TIMEOUT_CMD="\$TIMEOUT_BIN ${XCODEBUILD_TIMEOUT}"
else
    echo "WARNING: no 'timeout'/'gtimeout' in the VM — xcodebuild runs without a time cap." >&2
    TIMEOUT_CMD=""
fi

if [ "${BUILD_ON_HOST}" = true ]; then
    # test-without-building from host-built artifacts
    XCTESTRUN="\$(ls "${GUEST_PRODUCTS}"/*.xctestrun 2>/dev/null | head -1)"
    if [ -z "\$XCTESTRUN" ]; then
        echo "ERROR: no .xctestrun file found in ${GUEST_PRODUCTS}" >&2
        ls "${GUEST_PRODUCTS}" >&2 || true
        exit 1
    fi
    echo "  xctestrun: \$XCTESTRUN"
    rm -rf "${GUEST_RESULT_BUNDLE}"
    \$TIMEOUT_CMD xcodebuild test-without-building \\
        -xctestrun "\$XCTESTRUN" \\
        -destination 'platform=macOS' \\
        -only-testing "${ONLY_TESTING}" \\
        -resultBundlePath "${GUEST_RESULT_BUNDLE}" \\
        -retry-tests-on-failure -test-iterations 3 \\
        -test-timeouts-enabled YES \\
        -default-test-execution-time-allowance 600 \\
        -maximum-test-execution-time-allowance 600 \\
        2>&1 | tee /tmp/xcodebuild-test.log
else
    # Legacy: build and test inside the VM
    echo "  cd \$PROJ_DIR"
    cd "\$PROJ_DIR"
    rm -rf "${GUEST_RESULT_BUNDLE}"
    \$TIMEOUT_CMD xcodebuild test \\
        -project "${PROJECT}" \\
        -scheme "${SCHEME}" \\
        -configuration "${CONFIG}" \\
        -destination 'platform=macOS' \\
        -only-testing "${ONLY_TESTING}" \\
        -derivedDataPath "/Users/admin/Library/Developer/Xcode/DerivedData/Jobhunt-vm" \\
        -resultBundlePath "${GUEST_RESULT_BUNDLE}" \\
        -retry-tests-on-failure -test-iterations 3 \\
        -test-timeouts-enabled YES \\
        -default-test-execution-time-allowance 600 \\
        -maximum-test-execution-time-allowance 600 \\
        CODE_SIGNING_ALLOWED=NO \\
        CODE_SIGNING_IDENTITY="" \\
        CODE_SIGN_ENTITLEMENTS="" \\
        2>&1 | tee /tmp/xcodebuild-test.log
fi
XC_EXIT=\${PIPESTATUS[0]}

# Replay summary lines from the captured log
echo
grep -E "(Test Suite|Test Case 'test|error:|FAILED|PASS|Executed [0-9])" \
    /tmp/xcodebuild-test.log || true

echo
if [ "\$XC_EXIT" -eq 0 ]; then
    echo "✓ All tests passed"
elif [ "\$XC_EXIT" -eq 124 ]; then
    # TASK-405: timeout exit code. Surface clearly; the host trap stops the VM.
    echo "✗ TIMEOUT: xcodebuild exceeded ${XCODEBUILD_TIMEOUT}s and was killed (exit 124)." >&2
    echo "--- last 40 lines ---" >&2
    tail -40 /tmp/xcodebuild-test.log >&2
    exit 124
else
    echo "✗ xcodebuild exited \$XC_EXIT" >&2
    echo "--- last 40 lines ---" >&2
    tail -40 /tmp/xcodebuild-test.log >&2
    exit "\$XC_EXIT"
fi
GUEST_TEST

echo "────────────────────────────────────────────────────────────────────────"

# cleanup() runs via EXIT trap — shuts down VM and propagates exit code
