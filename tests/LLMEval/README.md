# LLM evals

Opt-in benchmarks that call a real model. Kept out of the fast gate — run them deliberately, and
always before switching the model the app scores with.

Three suites, measuring different halves of the pipeline:

| Suite | Question it answers |
|---|---|
| `LLMEvalHarness` | **Extraction** — are title, company, location, remote type, salary and requirements pulled out correctly? |
| `FitScoringEval` | **Judgment** — are requirement assessments honest, or does the model over-credit adjacent experience? |
| `OverCreditEval` | The two originally-reported over-credit cases (CUDA, PCI), kept as a focused regression. |

`FitScoringEval` exists because nothing measured scoring judgment. Extraction accuracy says nothing
about whether "expertise in CUDA" was scored *met* from a GPU migration — and that judgment is what
every score, filter and triage decision rests on.

## Repeats — set this before believing any result

Hosted inference is **not deterministic**, even at `temperature: 0`. Measured August 2026 on
byte-identical requests: `deepseek-v4-flash` changed 7 of 15 requirement verdicts between calls and
moved the score 10–16 points; `claude-haiku-4.5` changed none across eight runs; `ministral-14b`
changed two. Provider pinning did not fix it.

So a single pass measures a sample, not a model — which is how a public recommendation came to rest
on one lucky run. Set repeats before drawing a conclusion:

```bash
echo 5 > ~/.config/jobhunt/eval-repeats     # or JOBHUNT_EVAL_REPEATS=5
```

Both `FitScoringEval` and `OverCreditEval` then run the whole fixture set N times and accumulate,
turning the report into a pass rate.

## Configuration

`xcodebuild` does **not** forward the shell environment to the test process, so an exported variable
never arrives — config is read from files instead. Keeping them outside the repo also means an API
key can't be committed by accident.

Config lives in `~/.config/jobhunt/`:

| File | Purpose |
|---|---|
| `eval-models` | One `model` or `provider:model` per line — **the multi-model list**. `#` comments allowed. |
| `eval-model` | A single model, when you only want one. |
| `eval-provider` | Default provider for lines that don't name one. |
| `eval-api-key-<provider>` | Per-provider key, e.g. `eval-api-key-openrouter`. |
| `eval-api-key` | Shared key, when every model uses one provider. |
| `eval-base-url` | LM Studio endpoint. |
| `eval-resume.md` | **The résumé evals score against.** |

```sh
mkdir -p ~/.config/jobhunt
cat > ~/.config/jobhunt/eval-models <<'EOF'
openrouter:deepseek/deepseek-v4-flash-0731
google:gemini-3.1-flash-lite
EOF
echo sk-or-...  > ~/.config/jobhunt/eval-api-key-openrouter
echo AIza...    > ~/.config/jobhunt/eval-api-key-google
chmod 600 ~/.config/jobhunt/eval-api-key-*
```

Providers: `lmstudio` (needs `eval-base-url`, no key), `openrouter`, `google`, `anthropic`,
`openai`. OpenRouter rotation is disabled in evals, so the model you name is the model you measure.

The pre-XDG `~/.jobhunt-eval-*` and `~/.jobhunt-lmstudio-*` files are still read as a fallback, and
`scripts/run-eval.sh <model> [threshold]` still works.

### The résumé

Evals score against `~/.config/jobhunt/eval-resume.md` when present, otherwise a synthetic stand-in.

Export your real one:

```sh
sqlite3 ~/Library/Application\ Support/Jobhunt/jobhunt.store \
  "SELECT ZTEXT FROM ZRESUME WHERE ZNAME='Brooks_Cutter_Resume_Master';" \
  > ~/.config/jobhunt/eval-resume.md
chmod 600 ~/.config/jobhunt/eval-resume.md
```

**It is deliberately not committed.** This repo is public, and a résumé is a full work history —
employers, dates, scope. Keeping it in config gives honest evals without publishing it.

Note the fixtures' expectations depend on what the résumé *lacks* — no CUDA development, no hardware
or controls engineering, no named PM tooling. If yours gains any of those, revisit the affected case
rather than assuming the model regressed.

## Running

```sh
xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-Eval \
  -configuration Debug-DMG -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Both suites **report** by default and fail nothing, so a run always shows the full picture. To gate:

- extraction — `~/.config/jobhunt/eval-min-accuracy` (integer percentage)
- fit scoring — `JOBHUNT_EVAL_STRICT=1`

An unconfigured or misconfigured run **skips with the reason** rather than passing silently.

## Comparing models

List them in `eval-models` and run once. `FitScoringEval` evaluates every model against **identical
fixtures in a single run** and prints a comparison:

```
=== Comparison ===
model                                       checks   scores
google:gemini-3.1-flash-lite                9/10 (90%)   62 61 86 74 99
openrouter:deepseek/deepseek-v4-flash-0731  7/10 (70%)   88 91 92 80 95

score columns, in order:
  1. #607 Akamai — GPU migration is not CUDA expertise
  ...
```

Running them together is the point: this scorer's run-to-run variance has been measured at **23
points on identical input**, so a difference observed across separate runs of separate models means
very little.

Judge on the **checks column**, not the scores. A model that rates everything 95 passes no checks; a
model that scores conservatively for the right reasons passes them all.

## Fixtures

**Extraction** — synthetic postings covering two paths:

- *Extraction-only* (pre-cleaned description → extract): remote role with salary bands and
  application URL; hybrid/contract role with hourly pay; multi-band US salary with metro override
  and a days-in-office work site.
- *End-to-end* (raw text → `cleanDescription` → extract), which also exercises boilerplate
  stripping, JSON-LD preference and selection dedupe.

**Fit scoring** — every case is a real posting where the scorer was demonstrably wrong, with the
rationale recorded alongside it:

| Case | Failure it pins |
|---|---|
| Akamai #607 | "CUDA ecosystem" scored *met* from an H100/H200 migration |
| Mainspring #231 | "hardware or controls engineering" scored *met* via the word "software" in a parenthetical, on a generator-manufacturing role; `domain_fit` 90 |
| Akamai #718 | "or capacity to learn JIRA" charged as a gap — satisfiable by anyone |
| Zip #182 | "Alignment with core values" graded at all |
| Pinterest #619 | A *one-or-more* preferred list marked missing — the inverse error |

When you find a new failure:

1. Add a case with the **JD context** that makes the judgment decidable — domain judgments need it.
2. State the expectation as a **set** of acceptable statuses. `partial` and `missing` are often both
   defensible; pinning one makes the eval brittle without making it stricter.
3. Record *why* in `rationale`, so a future regression explains itself instead of looking arbitrary.

Fixtures must be revisited when scoring rules change. `FitScorer.assessmentPromptVersion` is printed
on every run, so a result can always be traced to the rules that produced it.
