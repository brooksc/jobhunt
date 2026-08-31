#!/usr/bin/env bash
# Catch documentation drift mechanically, before it misleads someone.
#
# WHY THIS EXISTS
# ---------------
# A 2026-08-31 audit found CLAUDE.md carrying four factual errors and three lists presented as
# exhaustive that were not: six shipped migrator flags missing, four AppUITests classes missing, a
# whole settings tab missing, `LaunchPlan` cited in the wrong file. None of it was noticed for
# months. CLAUDE.md is loaded into every agent session, so each error propagated into the
# assumptions of every session that read it.
#
# A wrong LINE gets caught eventually — someone tries it and it fails. A list that LOOKS complete
# never does: a reader takes it as the whole set and never re-derives it. That asymmetry is why the
# lists are checked here and the prose is left to human review.
#
# This checks only what can be checked mechanically. It is not a substitute for reading the docs;
# see docs/release-process.md for the periodic human audit it complements.
#
# Usage:  ./scripts/check-docs.sh          # report drift, exit 1 if any
#         ./scripts/check-docs.sh --quiet  # only print failures
set -uo pipefail
cd "$(dirname "$0")/.."

quiet=0
[[ "${1:-}" == "--quiet" ]] && quiet=1
fails=0

say()  { ((quiet)) || echo "$@"; }
ok()   { say "  ok   $*"; }
fail() { echo "  FAIL $*"; fails=$((fails + 1)); }

# ---------------------------------------------------------------------------
say "== migrator flags: CLAUDE.md and tools/migrator/README.md vs Args.swift =="
# Args.swift is the source of truth. Operation flags only — --store/--input/--output/--from/--into
# are parameters, not modes, and are documented in prose rather than the mode list.
mapfile -t real_flags < <(
  grep -oE '"--[a-z-]+"' tools/migrator/Args.swift |
    tr -d '"' | sort -u |
    grep -vE '^--(store|input|output|from|into)$'
)
for doc in CLAUDE.md tools/migrator/README.md; do
  missing=()
  for flag in "${real_flags[@]}"; do
    grep -qF -- "$flag" "$doc" || missing+=("$flag")
  done
  if ((${#missing[@]})); then
    fail "$doc is missing ${#missing[@]} migrator flag(s): ${missing[*]}"
  else
    ok "$doc lists all ${#real_flags[@]} migrator modes"
  fi
done

# ---------------------------------------------------------------------------
say "== UI-test launch arguments: CLAUDE.md vs AppUITests.swift =="
if [[ -f tests/AppUITests/AppUITests.swift ]]; then
  mapfile -t real_args < <(
    grep -oE '"--[a-z-]+"' tests/AppUITests/AppUITests.swift | tr -d '"' | sort -u
  )
  missing=()
  for arg in "${real_args[@]}"; do
    grep -qF -- "$arg" CLAUDE.md || missing+=("$arg")
  done
  if ((${#missing[@]})); then
    fail "CLAUDE.md is missing launch argument(s): ${missing[*]}"
  else
    ok "CLAUDE.md documents all ${#real_args[@]} launch arguments"
  fi
else
  fail "tests/AppUITests/AppUITests.swift not found — did the path move?"
fi

# ---------------------------------------------------------------------------
say "== CI runner names: docs vs workflow files =="
for wf in .github/workflows/*.yml; do
  runner=$(grep -m1 -oE 'runs-on: *[a-z0-9.-]+' "$wf" | awk '{print $2}')
  [[ -z "$runner" ]] && continue
  name=$(basename "$wf")
  # Only lines that name the workflow AND state a runner are claims about the runner. A doc that
  # merely mentions the workflow is not asserting anything, and failing on that made this check
  # noisy enough to ignore — which is how the stale 'macos-latest' survived in the first place.
  claims=$(grep -h "$name" CLAUDE.md docs/*.md 2>/dev/null |
             grep -oE '\b(macos|ubuntu|windows)-[a-z0-9.]+\b' | sort -u || true)
  [[ -z "$claims" ]] && continue
  if grep -qxF "$runner" <<<"$claims"; then
    ok "$name runner ($runner) matches the docs"
  else
    fail "$name pins '$runner' but the docs say: $(tr '\n' ' ' <<<"$claims")"
  fi
done

# ---------------------------------------------------------------------------
say "== source paths cited in CLAUDE.md actually exist =="
missing=()
while read -r path; do
  [[ -e "$path" ]] || missing+=("$path")
done < <(
  # Must contain a '/' — a bare `main.swift` or `release-dmg.yml` is prose naming a file, not a
  # path claim, and there are several of each in CLAUDE.md that are perfectly correct.
  grep -oE '`[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)+\.(swift|sh|yml|json|py|md|toml)`' CLAUDE.md |
    tr -d '`' | sort -u
)
if ((${#missing[@]})); then
  fail "CLAUDE.md cites ${#missing[@]} path(s) that do not exist: ${missing[*]}"
else
  ok "every source path cited in CLAUDE.md exists"
fi

# ---------------------------------------------------------------------------
say "== retired-stack references =="
# The Electron/Node/React stack was removed in TASK-064. .backlog/ is a historical record and is
# correctly full of Electron references; tools/migrator and Schema.swift legitimately name the
# legacy SQLite database they still import from.
# Only tracked files: .claude/worktrees holds other agents' checkouts, build/ and dist/ hold
# generated output and vendored dependencies. Scanning those reported the same file five times.
hits=$(git ls-files -z '*.swift' '*.js' '*.md' 2>/dev/null |
       xargs -0 grep -ilE 'electron' 2>/dev/null |
       grep -vE '^(tools/migrator/|core/Models/Schema\.swift|\.backlog/|doc-audit\.md)' || true)
if [[ -n "$hits" ]]; then
  fail "retired-stack references outside the allowed set:"
  echo "$hits" | sed 's/^/         /'
else
  ok "no stray Electron references"
fi

# ---------------------------------------------------------------------------
echo
if ((fails)); then
  echo "check-docs: $fails check(s) failed."
  echo "Fix the docs, or if a check itself is wrong, fix the check — don't silence it."
  exit 1
fi
echo "check-docs: all checks passed."
