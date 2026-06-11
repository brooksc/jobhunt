#!/usr/bin/env bash
# run-ui-tests-in-vm.sh
#
# Runs the AppUITests XCUITest suite inside an isolated Tart macOS VM so the
# test runner never hijacks focus or the mouse on the host machine.
#
# ASSUMPTIONS:
#   - Host: Apple Silicon (M1/M2/M3/M4)
#   - Tart CLI:      brew install cirruslabs/cli/tart
#   - sshpass:       brew install hudochenkov/sshpass/sshpass
#   - VM image:      ghcr.io/cirruslabs/macos-sequoia-xcode:latest
#                    (a Cirrus Labs image that includes Xcode — the base image
#                     does NOT include Xcode and cannot run xcodebuild)
#   - VM credentials: admin / admin  (default for all cirruslabs images)
#   - Code signing is disabled for the test build (no provisioning needed)
#   - The VM needs ~20 GB free for DerivedData; the base image provides ~50 GB
#
# USAGE:
#   ./scripts/run-ui-tests-in-vm.sh [--scheme <scheme>] [--no-shutdown]
#
# FLAGS:
#   --scheme <name>   XCUITest scheme to run (default: AppUITests)
#   --no-shutdown     Leave the VM running after tests (useful for debugging)
#
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

VM_NAME="jobhunt-uitest-env"
VM_IMAGE="ghcr.io/cirruslabs/macos-sequoia-xcode:latest"

SCHEME="AppUITests"
CONFIG="Debug-DMG"
PROJECT="Jobhunt.xcodeproj"

SSH_USER="admin"
SSH_PASS="admin"
# sshpass options: no host-key checking (new VM every clone), short connect timeout
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

MOUNT_NAME="project"
GUEST_SRC="/Users/admin/src"
GUEST_DERIVED="/Users/admin/Library/Developer/Xcode/DerivedData/Jobhunt-vm"

SHUTDOWN=true
MAX_IP_WAIT=120   # seconds to wait for VM to get an IP

# ── Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme)   SCHEME="$2"; shift 2 ;;
        --no-shutdown) SHUTDOWN=false; shift ;;
        *) echo "Usage: $0 [--scheme <scheme>] [--no-shutdown]" >&2; exit 1 ;;
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

# ── Preflight checks ─────────────────────────────────────────────────────────

step "Preflight"

command -v tart    >/dev/null 2>&1 || fail "tart not found. Install: brew install cirruslabs/cli/tart"
command -v sshpass >/dev/null 2>&1 || fail "sshpass not found. Install: brew install hudochenkov/sshpass/sshpass"

log "tart:    $(tart --version 2>/dev/null | head -1)"
log "project: $REPO_ROOT/$PROJECT"
log "scheme:  $SCHEME"

# ── VM provisioning ──────────────────────────────────────────────────────────

step "VM provisioning"

if tart list 2>/dev/null | grep -q "^${VM_NAME}\b"; then
    log "VM '$VM_NAME' already exists — reusing"
else
    log "Cloning $VM_IMAGE → $VM_NAME (this can take several minutes the first time)..."
    tart clone "$VM_IMAGE" "$VM_NAME"
    log "Clone complete"
fi

# ── Start VM ─────────────────────────────────────────────────────────────────

step "Starting VM"

# Kill any stale instance of this VM before starting fresh
if tart list 2>/dev/null | grep -q "^${VM_NAME}.*running"; then
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

log "Waiting for SSH to become available..."
for i in $(seq 1 60); do
    if sshpass -p "$SSH_PASS" ssh $SSH_OPTS -o ConnectTimeout=3 \
            "${SSH_USER}@${VM_IP}" 'true' 2>/dev/null; then
        log "SSH ready (attempt $i)"
        break
    fi
    if [ "$i" -eq 60 ]; then
        fail "SSH did not become available within 60 attempts"
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

# ── Run tests ─────────────────────────────────────────────────────────────────

step "Running XCUITest suite: $SCHEME"

log "Streaming test output from guest..."
echo "────────────────────────────────────────────────────────────────────────"

# Run xcodebuild test inside the VM; exit code propagates back via SSH.
# We build to a guest-local DerivedData path to avoid writing back to the
# (read-only) host share and to get full NVMe throughput inside the VM.
vm_ssh bash -s <<GUEST_TEST
set -uo pipefail

# Read the project root written by GUEST_SETUP
PROJ_DIR="\$(cat /tmp/jobhunt_proj_root)"
echo "  cd \$PROJ_DIR"
cd "\$PROJ_DIR"

# Run xcodebuild, capturing full output to log file.
# We intentionally do NOT pipe through grep here so that PIPESTATUS[0]
# is unambiguously xcodebuild's exit code — no trailing || true to reset it.
xcodebuild test \\
    -project "${PROJECT}" \\
    -scheme "${SCHEME}" \\
    -configuration "${CONFIG}" \\
    -destination 'platform=macOS' \\
    -derivedDataPath "${GUEST_DERIVED}" \\
    CODE_SIGNING_ALLOWED=NO \\
    CODE_SIGNING_IDENTITY="" \\
    CODE_SIGN_ENTITLEMENTS="" \\
    2>&1 | tee /tmp/xcodebuild-test.log
XC_EXIT=\${PIPESTATUS[0]}

# Replay summary lines from the captured log
echo
grep -E "(Test Suite|Test Case 'test|error:|FAILED|PASS|Executed [0-9])" \
    /tmp/xcodebuild-test.log || true

echo
if [ "\$XC_EXIT" -eq 0 ]; then
    echo "✓ All tests passed"
else
    echo "✗ xcodebuild exited \$XC_EXIT" >&2
    echo "--- last 40 lines ---" >&2
    tail -40 /tmp/xcodebuild-test.log >&2
    exit "\$XC_EXIT"
fi
GUEST_TEST

echo "────────────────────────────────────────────────────────────────────────"

# cleanup() runs via EXIT trap — shuts down VM and propagates exit code
