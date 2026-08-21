# Scoring-model benchmark — August 2026

Run 2026-08-20 against `FitScoringEval` (prompt version 3), real résumé
(`~/.config/jobhunt/eval-resume.md`, 34,307 chars), 5 fixtures × 5 repeats, all models through
OpenRouter in a single run so the comparison is on identical input.

The question was whether a frontier model — `openai/gpt-5.6-sol` — is worth its price on fit
judgement. **It is not.** It ties with a model 5× cheaper at list prices.

## Result

| Model | Checks | Verdict flips | $ / fit-score call |
|---|---|---|---|
| `openai/gpt-5.6-sol` | 25/25 (100%) | 0 of 4 | $0.0317 (billed) / $0.0549 list |
| `google/gemini-3.7-flash` | 25/25 (100%) | 0 of 4 | $0.0053 (promo) / $0.0107 list |
| `openai/gpt-5.6-luna` | 23/25 (92%) | 1 of 4 | $0.0026 |
| `google/gemini-3.1-flash-lite` | 18/25 (72%) | 1 of 4 | ~$0.0020 |
| `deepseek/deepseek-v4-flash-0731` | 30/33 (90%) | 0 of 4 | ~$0.0013 |
| `anthropic/claude-haiku-4.5` | **not measured** | — | $0.0210 |

Caveats, so the numbers aren't over-read:

- The first four rows are the **printed** checks (the four requirement needles + `domain_fit`), 5 of
  the 10 checks per repeat, tallied from the run log. They are the discriminating subset — the
  unprinted ones are `expectedOmitted`, which every model passed.
- `deepseek` is the harness's own full `=== Comparison ===` tally over all 33 checks, from a second
  run. Judge it against the others loosely, not to the point.
- `claude-haiku-4.5` produced **no valid result**: the OpenRouter account hit its $20 ceiling and
  every call returned HTTP 402. Its 15% in that run log is an artifact — ignore it. Haiku remains
  unmeasured on this fixture set.
- Total benchmark spend: **$6.40**.

## What the numbers say

**Sol is not worth it.** 100% checks and perfect verdict stability, but `gemini-3.7-flash` matched it
exactly on both, at **5× lower cost** at list rates. There is no fit-judgement headroom left for a frontier model
to recover on this fixture set — both are already at ceiling.

**`gemini-3.1-flash-lite` has regressed and must not be used.** It marked the Akamai CUDA
requirement `met` on **5 of 5** runs — the exact over-credit failure the fixture exists to catch —
and its scores swing wildly on identical input (67–88, 17–56, 99–100). An older recording of this
model at 9/10 no longer holds; whether the cause is model drift or prompt version 3 was not
isolated.

**Stability tracks capability here, and cheap models are the unstable ones.** Verdict flips across 5
identical calls, plus per-fixture score spread:

| Model | Score spread on identical input |
|---|---|
| `gpt-5.6-sol` | 39–45, 31–33, 70–74, 66–70, 81–88 (tight) |
| `gemini-3.7-flash` | 36–41, 25–30, 80–86, 64–78, 87–88 (tight) |
| `gpt-5.6-luna` | 18–38, 20–56, 38–59, 47–64, 72–80 (wide) |
| `gemini-3.1-flash-lite` | 67–88, 17–56, 99–100, 81–88, 89 (wide) |

`ConsistencyEval` x5 on Sol independently: score spread **1 point**, **0 of 7** requirements changed
answer. Compare the August measurement on `deepseek-v4-flash`: 7 of 15 verdicts changed and the
score moved 10–16 points.

**`deepseek-v4-flash-0731` has a reliability problem separate from its judgement.** Its judgement is
fine (30/33). But across three runs it was consistently the slowest model by a wide margin (~43 s per
call against 7–21 s for everything else), stalled long enough on two runs to look hung, and one of
its three misses was a **malformed JSON response** (`invalidJSON`, a duplicated `"summary` key), not
a judgement error. A scorer that occasionally returns unparseable output is a different class of
problem from one that scores a requirement generously.

## Recommendation

**`google/gemini-3.7-flash` for fit scoring.** Ceiling accuracy, stable verdicts, tight score
spreads, fast, and $0.0107 per call at list — about **$4.30 to score a 300-job corpus end to end**. It is the
only model measured that is both at the accuracy ceiling and cheap.

Reach for `gpt-5.6-sol` only if a future fixture set shows judgement failures that `gemini-3.7-flash`
cannot clear. On this one there is nothing left for it to fix.

## Verified OpenRouter pricing (2026-08-20)

Live from `GET https://openrouter.ai/api/v1/models`, $/1M tokens. Third-party pricing trackers were
wrong on several of these by 2×, in both directions — query OpenRouter directly.

> **These are the rates OpenRouter's default routing billed on the day, not list prices, and two of
> them are temporary.** `GET /models/{id}/endpoints` shows every upstream tier, and the default is the
> cheapest — which can be a promotion or a non-standard SKU:
>
> | Model | Billed here | Standard list | Why they differ |
> |---|---|---|---|
> | `google/gemini-3.7-flash` | 0.375 / 1.875 | **0.750 / 3.750** | OpenRouter 50%-off promo **ending 2026-08-27**; Google's own rate is itself introductory and doubles to 1.50 / 7.50 on 2027-01-01 |
> | `openai/gpt-5.6-sol` | 2.500 / 15.000 | **5.000 / 30.000** | OpenAI list is confirmed by the Azure (5.00/30.00) and Bedrock (5.50/33.00) endpoints |
> | `deepseek/deepseek-v4-flash-0731` | ~0.140 / 0.280 | varies | ~30 hosts spanning **0.065–0.440 in**, a 7× spread; DeepSeek's own API is the most expensive at 0.440 / 1.320 |
> | `google/gemini-3.1-flash-lite` | 0.250 / 1.500 | 0.250 / 1.500 | genuine parity, no promo |
>
> **Cost figures published to users must use the standard column**, or the page is wrong the day a
> promo lapses. The user-facing table in `marketing/help/which-model.html` does.
>
> **OpenRouter does not mark up per token** — its fee is 5.5% on credit top-ups — so "aggregator vs
> direct" is roughly a wash at list. Any gap you observe is a promotion or a routing choice, not a
> structural discount, and will not survive.

| Model | Input | Output |
|---|---|---|
| `deepseek/deepseek-v4-flash` | 0.078 | 0.157 |
| `deepseek/deepseek-v4-flash-0731` | 0.140 | 0.280 |
| `openai/gpt-5.6-luna` | 0.200 | 1.200 |
| `google/gemini-3.1-flash-lite` | 0.250 | 1.500 |
| `google/gemini-3.5-flash-lite` | 0.300 | 2.500 |
| `google/gemini-3.7-flash` | 0.375 | 1.875 |
| `anthropic/claude-haiku-4.5` | 1.000 | 5.000 |
| `deepseek/deepseek-v4-pro-0813` | 1.188 | 3.564 |
| `anthropic/claude-sonnet-5` | 2.000 | 10.000 |
| `openai/gpt-5.6-terra` | 2.000 | 12.000 |
| `openai/gpt-5.6-sol` | 2.500 | 15.000 |

A fit-score call costs ~6.9K input / ~0.7–1.3K output tokens against the real résumé. Reasoning
tokens are not a cost blowup here: Sol emitted 118, `gemini-3.7-flash` 808.

## Open items

- **Haiku 4.5 is still unmeasured** — needs an OpenRouter top-up and a re-run.
- **Extraction was not benchmarked**, only fit scoring. Extraction is the easier, well-specified half
  (strict JSON schema, answer present in the text); the cheapest reliable model is likely right there,
  but that is an assumption, not a measurement.
- **`gemini-3.1-flash-lite`'s regression was not root-caused** — model drift vs. prompt version 3.
