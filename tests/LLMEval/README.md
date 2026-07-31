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

## Configuration

`xcodebuild` does **not** forward the shell environment to the test process, so an exported variable
never arrives. Write the values to dotfiles in your **home directory** instead — which also means an
API key can't be committed by accident.

```sh
echo openrouter                       > ~/.jobhunt-eval-provider
echo deepseek/deepseek-v4-flash-0731  > ~/.jobhunt-eval-model
echo sk-or-...                        > ~/.jobhunt-eval-api-key
chmod 600 ~/.jobhunt-eval-api-key
```

Providers: `lmstudio` (needs `~/.jobhunt-eval-base-url`, no key), `openrouter`, `google`,
`anthropic`, `openai`. OpenRouter rotation is disabled in evals, so the model you name is the model
you measure.

The legacy `~/.jobhunt-lmstudio-url` / `~/.jobhunt-lmstudio-model` pair still selects LM Studio, and
`scripts/run-eval.sh <model> [threshold]` still works for that path.

## Running

```sh
xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-Eval \
  -configuration Debug-DMG -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Both suites **report** by default and fail nothing, so a run always shows the full picture. To gate:

- extraction — `~/.jobhunt-lmstudio-min-accuracy` (integer percentage)
- fit scoring — `JOBHUNT_EVAL_STRICT=1`

An unconfigured or misconfigured run **skips with the reason** rather than passing silently.

## Comparing two models

```sh
for m in gemini-3.1-flash-lite deepseek/deepseek-v4-flash-0731; do
  echo "$m" > ~/.jobhunt-eval-model
  echo "=== $m ==="
  xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-Eval \
    -configuration Debug-DMG -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E "checks passed|Overall:|→ score|Misses"
done
```

Judge on the **checks-passed percentage of `FitScoringEval`**, not on the scores themselves. A model
that rates everything 95 passes no checks; a model that scores conservatively for the right reasons
passes them all.

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
