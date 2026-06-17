# VM-Based UI Testing

This document describes how Jobhunt runs its XCUITest suite (`AppUITests`) inside a headless macOS virtual machine, why that approach was chosen, how it works step by step, and how to debug failures.

## Why a VM

XCUITest drives the app through the macOS Accessibility API. That requires a live graphical session — the same thing a logged-in user sees. Running the tests directly on a developer's Mac steals keyboard and mouse focus for the duration of the run (5–10 minutes). That makes the machine unusable and is easily broken by incidental mouse movement.

A Tart VM solves this cleanly:

- Headless — no window appears on the host; focus is never stolen.
- Isolated — tests use a throw-away in-memory store; the host's production data is untouched.
- Disposable — the VM starts fresh from a known-good image every run.
- Proximate — virtiofs mounts the project directory read-only into the guest at ~NVMe speed, so there's no file-transfer step before the build.

## Architecture

```
Host Mac (Apple Silicon)
├── xcodebuild build-for-testing → build/Jobhunt-testing/   ← HOST BUILD (native speed)
├── tart run jobhunt-uitest-env --no-graphics --dir=project:<repo>:ro
│     └─ VM (macOS Sequoia + Xcode)
│           ├── /Volumes/My Shared Files/project  ← virtiofs, read-only
│           │     └── build/Jobhunt-testing/      ← pre-built artifacts visible here
│           ├── /tmp/jobhunt-testing/             ← local copy for test execution
│           └── xcodebuild test-without-building  ← only runs tests, no compile
└── SSH (sshpass, no host-key check)
      ├── GUEST_SETUP: mount share, disable sleep
      ├── GUEST_COPY:  cp artifacts from virtiofs → /tmp/jobhunt-testing/
      └── GUEST_TEST:  test-without-building from local copy
```

The project files live on the host and are presented to the VM read-only via virtiofs. The host performs the Swift compilation using its native Apple Silicon performance. The VM receives a local copy of the pre-built test artifacts and only handles test execution (launching the app, driving Accessibility API). This avoids the overhead of compiling inside a virtualized environment.

## Prerequisites (one-time setup)

```bash
# Install Tart (Apple Silicon hypervisor)
brew install cirruslabs/cli/tart

# Install sshpass (non-interactive SSH password auth)
brew install hudochenkov/sshpass/sshpass

# Clone the VM image — includes macOS Sequoia + Xcode (~20 GB, one-time download)
tart clone ghcr.io/cirruslabs/macos-sequoia-xcode:latest jobhunt-uitest-env
```

The image is from [Cirrus Labs](https://github.com/cirruslabs/macos-image-templates) and ships with Xcode pre-installed. Default credentials: `admin / admin`.

## Running the Tests

```bash
# Standard run — starts VM, runs all AppUITests, stops VM
./scripts/run-ui-tests-in-vm.sh

# Leave the VM running after the run (useful for debugging — see below)
./scripts/run-ui-tests-in-vm.sh --no-shutdown

# Run only one test suite
./scripts/run-ui-tests-in-vm.sh --only-testing AppUITests/BehaviorUITests

# Override the scheme (rarely needed)
./scripts/run-ui-tests-in-vm.sh --scheme Jobhunt-DMG
```

## What Happens During a Run

The script runs six phases, each printed as `▶ Phase name`:

### 1. Preflight
Checks that `tart` and `sshpass` are on `PATH`. Prints the resolved scheme and project path.

### 2. VM Provisioning
Checks if the `jobhunt-uitest-env` VM exists locally. If not, clones it from `ghcr.io/cirruslabs/macos-sequoia-xcode:latest`. If it's already running (stale from a prior crash), stops it first.

### 3. Starting VM
Launches the VM headlessly:
```bash
tart run jobhunt-uitest-env --no-graphics --dir=project:<repo>:ro
```
`--no-graphics` suppresses the VM window entirely. `--dir` mounts the repo as a virtiofs share named `project`.

### 4. Waiting for VM Network
Polls `tart ip jobhunt-uitest-env --wait 120` until the VM gets a DHCP address, then waits for SSH to respond (up to 120 × 2 s retries, requiring 3 consecutive successful password auths — fresh clones restart `sshd` several times during first boot).

### 5. Configuring Guest Environment
Sends a setup script over SSH that:
- Disables sleep and screen-saver (so UI elements stay hittable during long runs).
- Verifies the virtiofs share is auto-mounted at `/Volumes/My Shared Files/project`.
- Locates `Jobhunt.xcodeproj` up to 3 directory levels deep (handles Tart's occasional extra nesting).
- Writes the resolved project root to `/tmp/jobhunt_proj_root` for the next phase.

### 6. Running XCUITest Suite
By default the host pre-built the test bundle (`build-for-testing`), so the guest only **runs** the tests — no compile — from the copied artifacts:
```bash
xcodebuild test-without-building \
  -xctestrun /tmp/jobhunt-testing/<scheme>.xctestrun \
  -destination 'platform=macOS' \
  -only-testing AppUITests \
  -resultBundlePath /tmp/jobhunt-uitest.xcresult \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 \
  -maximum-test-execution-time-allowance 600 \
  2>&1 | tee /tmp/xcodebuild-test.log
```
(With `--build-in-vm` the guest instead runs a full `xcodebuild test`.) The per-test time allowance is the hang guard: if the app crashes at launch and a test wedges, it's killed after 10 minutes instead of blocking forever.

Full output streams back to the host in real time via SSH. After xcodebuild finishes, the script replays a summary filtered to `Test Case`, `error:`, `FAILED`, `PASS`, and `Executed N tests` lines.

### Teardown
On exit (success, failure, or Ctrl-C), the script first **copies the artifacts back to the host** (best-effort) — the result bundle to `build/UITestResults.xcresult` (overwritten each run) and the screenshots to `local-screenshots/<timestamp>/` — then the `EXIT` trap stops the VM unless `--no-shutdown` was passed. Because retrieval runs in the `EXIT` trap, the artifacts come back even when the tests failed.

## App Launch Arguments

The `launchApp()` helper in `AppUITests.swift` always sets:

| Argument | Effect |
|---|---|
| `-UIAnimationDragCoefficient 0` | Disables all SwiftUI animations — tests run 2–3× faster and element queries don't race animations |
| `--ui-test-store` | App creates an isolated SwiftData store in a temp directory; production data is never touched |
| `--seed-demo-data` | Calls `DemoSeeder` on launch to populate ~20 jobs, sites, and captures |

The app handles these in `app/JobhuntApp.swift`.

## Before Running: Regenerate the Xcode Project

If you've added new Swift source files (e.g., to `core/` or `app/`) since the last run, regenerate the project first:

```bash
tuist generate --no-open
```

Tuist generates an xcodeproj with explicit file references. New files added after the last `tuist generate` are invisible to xcodebuild and will cause "cannot find X in scope" build errors in the VM. The VM reads the xcodeproj from the host via virtiofs, so regenerating on the host is sufficient.

## Debugging Failures

### Step 1: Re-run with --no-shutdown

```bash
./scripts/run-ui-tests-in-vm.sh --no-shutdown
```

The VM stays up after the test run. You can SSH in to inspect logs:

```bash
VM_IP=$(tart ip jobhunt-uitest-env)
sshpass -p admin ssh -o StrictHostKeyChecking=no admin@$VM_IP

# Full xcodebuild log (very verbose)
less /tmp/xcodebuild-test.log

# Replay test summary
grep -E "(Test Case|error:|Executed)" /tmp/xcodebuild-test.log
```

### Step 2: Check the element tree

If a test fails with "No matches found" or "Not hittable", the accessibility tree is the first thing to inspect. Add a temporary debug line to the failing test:

```swift
print(app.debugDescription)
```

The output appears in `/tmp/xcodebuild-test.log` in the VM.

### Step 3: Review screenshots

`ScreenshotTests` writes `.png` files to `/tmp/jobhunt-screenshots/<timestamp>/` inside the VM and also attaches them to the `.xcresult` bundle. To retrieve them while the VM is running:

```bash
VM_IP=$(tart ip jobhunt-uitest-env)
sshpass -p admin scp -o StrictHostKeyChecking=no -r \
  "admin@$VM_IP:/tmp/jobhunt-screenshots/" ./local-screenshots/
```

> **Limitation**: Screenshots and the `.xcresult` bundle are lost when the VM shuts down. They are not automatically copied back to the host. See the backlog for a planned fix.

### Step 4: Run a single test class

Isolate the failing suite to reduce iteration time. `--class`/`--test` are shortcuts that expand to
`-only-testing AppUITests/…` (TASK-404):

```bash
# Whole suite filter (full path):
./scripts/run-ui-tests-in-vm.sh --only-testing AppUITests/BehaviorUITests
# One class (shortcut):
./scripts/run-ui-tests-in-vm.sh --class BehaviorUITests
# One method (shortcut):
./scripts/run-ui-tests-in-vm.sh --test BehaviorUITests/testSidebarNavigationChangesSections
```

The in-VM `xcodebuild` is capped at `XCODEBUILD_TIMEOUT` (15 min, TASK-405): a hung run exits 124
with a clear `TIMEOUT` message and the VM is stopped cleanly by the host trap.

### Step 5: Run directly in the VM (no script)

If the script's SSH wrapping is obscuring an issue, SSH directly and run xcodebuild interactively:

```bash
VM_IP=$(tart ip jobhunt-uitest-env)
sshpass -p admin ssh -o StrictHostKeyChecking=no admin@$VM_IP

cd "$(cat /tmp/jobhunt_proj_root)"
xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -destination 'platform=macOS' \
  -only-testing AppUITests/BehaviorUITests \
  CODE_SIGNING_ALLOWED=NO
```

## Incremental Builds

The host's `build/Jobhunt-testing/` directory serves as the incremental build cache. Xcode on the host recompiles only changed files on subsequent runs.

- **Cold build (first run)**: ~3–5 minutes on an M-series host
- **Incremental build (changed files only)**: ~20–60 seconds on host
- **VM test execution (no build)**: ~4–6 minutes

The VM does not maintain its own DerivedData for this project. For a clean rebuild:

```bash
rm -rf build/Jobhunt-testing
./scripts/run-ui-tests-in-vm.sh
```

## Comparison with CI

| | Tart VM (local) | GitHub Actions (`macos-15`) |
|---|---|---|
| Trigger | Manual (`./scripts/run-ui-tests-in-vm.sh`) | Weekly (Mon 8am UTC) or manual dispatch |
| Environment | `ghcr.io/cirruslabs/macos-sequoia-xcode` (digest-pinned) | `macos-15` runner (default Xcode) |
| Build cache | Persists across runs on reused VM | Cold cache every run |
| Artifacts | Retrieved to host on exit (see Results Retrieval) | `.xcresult` + `toolchain.txt` uploaded for 7 days |
| Focus-steal | None (headless VM) | None (CI runner) |
| Speed (cold) | ~12 min (clone + build + test) | ~12 min (install Tuist + build + test) |
| Speed (warm) | ~6 min (incremental build + test) | ~12 min (always cold) |

CI is defined in `.github/workflows/ui-tests.yml`. A UI-test failure fails the job (no `continue-on-error`); the `.xcresult` still uploads via `if: always()`.

### Toolchain parity (TASK-406)

The two environments pin their toolchains **independently**: the VM via the immutable `VM_IMAGE`
digest (below), CI via the `macos-15` runner's default Xcode. Both can move without a code change, so
each prints its exact `sw_vers` + `xcodebuild -version` at run time, making any divergence explicit
and diffable:

- **VM:** the guest run logs a `── VM toolchain (TASK-406 parity check) ──` block (streamed to the host).
- **CI:** the *Record toolchain versions* step writes `build/toolchain.txt`, uploaded with the results
  artifact.

**Last observed versions** (update when you re-pin `VM_IMAGE` or notice CI drift):

| Environment | macOS | Xcode | Observed |
|---|---|---|---|
| Tart VM (digest `sha256:31413f…`) | 15.7.3 (24G419) | 26.4.1 | 2026-06-17 |
| `macos-15` CI runner | (see `build/toolchain.txt` in the latest run's artifact) | | |

**Drift check:** compare the two `Xcode <version>` lines. They should report the same **major** Xcode.
If they don't, reconcile — bump `VM_IMAGE` to a digest whose bundled Xcode matches the `macos-15`
runner (or pin the runner's Xcode with `xcode-select` to match the VM) — then note the new versions
here. We deliberately don't hard-fail on a mismatch: GitHub rolls the runner's default Xcode forward
on its own schedule, and a forced `xcode-select -s /Applications/Xcode_X.Y.app` to a path that isn't
installed would break the scheduled job outright. Recording-and-comparing is the lighter, non-brittle
signal for an app at this scale.

## Results Retrieval

On every exit the script copies the result bundle and screenshots back to the host **before** stopping the VM:

```
build/UITestResults.xcresult     ← open in Xcode: open build/UITestResults.xcresult
local-screenshots/<timestamp>/   ← PNGs from ScreenshotTests
```

This happens whether the run passed or failed, so a failure is debuggable without re-running with `--no-shutdown`.

## Pinning the VM image

`run-ui-tests-in-vm.sh` pins `VM_IMAGE` to an **immutable digest** (TASK-403) so `:latest` can't
silently drift to a new Xcode/macOS patch and break tests with no code change:

- Image: `ghcr.io/cirruslabs/macos-sequoia-xcode` — macOS Sequoia 15.x, bundled latest Xcode
- Digest: `sha256:31413f28df83c37b94e76f8feea8046fb1950b3ed42195523408477189a3f76d` (resolved from
  `:latest` on 2026-06-17)

**To upgrade** the pin: re-resolve the digest and update both the script and this doc, then confirm
the bundled Xcode/macOS:

```bash
# Resolve the current :latest digest (no Tart needed):
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:cirruslabs/macos-sequoia-xcode:pull" | jq -r .token)
curl -sI -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  https://ghcr.io/v2/cirruslabs/macos-sequoia-xcode/manifests/latest | grep -i docker-content-digest
# then set the new VM_IMAGE digest in scripts/run-ui-tests-in-vm.sh (and here), or per-run:
VM_IMAGE=ghcr.io/cirruslabs/macos-sequoia-xcode@sha256:<digest> ./scripts/run-ui-tests-in-vm.sh
```

## Known Limitations

- **CI and local VM use different base images.** `macos-15` on GitHub Actions may have a different Xcode patch version than the Tart image, so a test that passes locally could behave differently in CI. Pin both for parity.
- **Retry masks flakiness.** Both lanes pass `-retry-tests-on-failure -test-iterations 3`, so a test that fails then passes is reported green. Genuinely flaky tests still need fixing — check the result bundle for retried tests.
