# Requirement matching and fit scoring — joint problem statement

**Audience:** two collaborating agents with different access and different blind spots.

| Agent | Works in | Owns | Cannot see |
|---|---|---|---|
| **jobhunt agent** | `~/code/jobhunt` | The scoring pipeline: extraction prompt, requirement decomposition, dimension scores, penalty model, deterministic feedback layer, eval harness, and measurement over the 400+ scored jobs in the live store | Whether a given verdict is *true* — it has no independent knowledge of what the user has actually done |
| **résumé agent** | the résumé workspace | The master résumé and skills inventory, the user's real career history, and the tailored résumés/cover letters generated from it | The code, the corpus-wide statistics, and what any change costs to implement or run |

**Why two agents.** jobhunt can measure everything and verify nothing. The résumé agent can verify everything and measure nothing. Ground truth for "does this candidate meet this requirement?" exists only on the résumé side; the ability to act on it at scale exists only on the jobhunt side. Neither can solve this alone, and each will confidently produce a wrong answer if it tries.

Adopt the role of whichever directory you're working in. Say which one you are in every exchange.

---

## 1. What the score is for

The user tracks a few hundred applications. The fit score exists to answer **one** question:

> Of the jobs I've captured, which deserve the hours it takes to tailor a résumé and apply?

Everything follows from that. Notably:

- **Ranking matters more than absolute values** — but not exclusively. The user has a *Requirements* setting with a **minimum fit score** (currently 50) that buckets jobs into Meets / Not stated / Doesn't meet. That's an absolute threshold, so calibration can't be waved away in favour of pure ordering.
- **The two errors are not symmetric.** A false positive costs one wasted read and an archive click. A false negative hides a job the user would have wanted, permanently and invisibly. This asymmetry is already settled policy elsewhere in the app (remote-location inference was deliberately made permissive on exactly this reasoning) and should govern here too.
- **An unusable score is worse than no score.** A list where everything scores 95 conveys nothing; so does a list where a third of the entries are 0.

## 2. How it works today

Per job, per résumé, one LLM call produces JSON containing:

**Five dimension scores (0–100), weighted:**

| Dimension | Weight |
|---|---|
| `required_qualifications` | 0.40 |
| `preferred_qualifications` | 0.20 |
| `skills` | 0.15 |
| `domain_fit` | 0.15 |
| `experience_level` | 0.10 |

**Plus a list of `requirement_assessments`**, each with `requirement` text, `kind` ∈ {required, preferred}, `status` ∈ {met, partial, missing}, and `evidence`.

Final score = weighted base − penalty, floored at 0. Penalty is a raw sum over the assessments:

| | missing | partial |
|---|---|---|
| **required** | 12 | 6 |
| **preferred** | 10 | 5 |

capped at 60. Prompt is at `assessment_prompt_version = 3`; scoring model is currently `deepseek/deepseek-v4-flash` via OpenRouter, and local models (LM Studio / Ollama) are supported and used.

Two deterministic layers sit on top of the model output:

- **Non-discriminating filter** — drops requirements no candidate could fail ("capacity to learn Jira", "alignment with our values").
- **User corrections** (`ScoringFeedback`) — per-phrase overrides: *I do have this* / *I don't have this* / *not a real requirement* / *wrong for this job only*.

The full analysis is stored as JSON on every score, so **the entire corpus can be re-scored with different arithmetic at zero LLM cost.** This is the single most useful property for this project: any change to weights, penalties or normalisation can be evaluated against 400+ real jobs immediately.

## 3. The core problem

**Exact matching cannot work, and neither can naive semantic matching.** A requirement and a résumé line relate along at least three levels, and only the third is the one that matters:

1. **Lexical** — "Kubernetes" vs "Kubernetes". Rare, and when it happens it's often a trap (the résumé says the word in a context that wouldn't survive an interview).
2. **Semantic** — "container orchestration" vs "Kubernetes"; "stakeholder alignment" vs "drove consensus across five orgs". An embedding or an LLM handles this well.
3. **Judgement** — *given what this person has actually done, and what this job actually needs, would a competent hiring manager consider this satisfied?* This is the real question, and it is not a text-similarity problem at all.

Level 3 is where the system keeps failing, in both directions:

**Over-crediting** (the failure mode fixed in prompt v3, still partially present): the model rewards *adjacent* experience. Job #231 asked for "background in hardware or controls engineering" at a hardware manufacturer; a strong cloud-infrastructure PM résumé scored 98. Job #718 counted "capacity to learn" and company values as met requirements. Left unchecked, everything lands in the high 80s–90s and the score stops discriminating.

**Under-crediting** (the failure mode the user is hitting now): the model marks a requirement missing because the résumé doesn't *say* it, when the user has in fact done it. Five of the six user corrections currently in the store are exactly this, all restating one underlying fact: the résumé under-evidences AI / gen-AI / agent work.

**And the taxonomy itself is underspecified.** `met` / `partial` / `missing` is applied inconsistently because nothing defines the boundaries. Is 6 years against "8+ years required" partial or met? Is "PRDs for ML features" partial credit against "shipped LLM products"? Is a compound bullet asking for two things, one of which you have, a `partial` — or two requirements, one `met` and one `missing`? (Prompt v3 says decompose; the model does so unevenly.) These calls swing scores by 20+ points and there's no written standard for a labeller — human or model — to apply consistently.

## 4. What's measured, not asserted

All figures are from the live store (415 scored jobs, 1,003 fit-score rows, 12,597 requirement assessments), computed 2026-08-02.

**Penalty saturation** (TASK-656):
- **11%** of scored rows hit the 60-point penalty cap. Past the cap the score is flat — it has stopped carrying information.
- **10%** score exactly 0.
- **13%** miss *no* required qualification yet score under 40.
- Worked example, job #734 (Zscaler, Principal AI PM): base 58; 6 required met, 4 required partial, **zero required missing**, 5 preferred missing, 2 preferred partial. Raw penalty 84 → capped 60 → **score 0**. A missing *preferred* costs 10 against a missing *required*'s 12, and nothing normalises for how many requirements a posting lists, so a verbose JD is arithmetically guaranteed to hit the cap.

**User corrections don't generalize** (TASK-659). Matching is a lowercased substring test, and the UI captures the whole requirement sentence:
- Five of the six live rules match **exactly one** requirement in 12,597 — the one they were created from.
- The sixth is `IDE`, which matches *provide*, *identify*, *guidance*, *consider*: **359 requirements across 124 of 415 jobs**, all force-credited to `met`.

**Prompt dilution is real and was measured.** A v4 experiment added one broad "omit non-discriminating requirements" instruction; job #231 regressed from a correct 60 back to 96 on `gemini-3.1-flash-lite`, because the new rule diluted the rules that were working. This is why user feedback is applied deterministically in code and **never appended to the prompt** — and it's a hard constraint on any proposal that amounts to "just tell the model about the user's background."

## 5. Constraints that bound the solution space

Proposals that violate these will be rejected, so design inside them:

1. **The scoring model is weak and cheap by design.** `deepseek-v4-flash`-class, sometimes a local model. A solution that only works on a frontier model isn't a solution to this problem, though "use a better model for scoring" is a legitimate *option* to price out (the eval harness can measure exactly what it buys).
2. **Prompt budget is scarce and non-monotonic.** Adding instructions has measurably made things worse. Every prompt change must be justified against the eval set, not by argument.
3. **One call per job/résumé pair.** Multi-pass or per-requirement calls multiply cost and latency by the number of requirements (10–20 typical). Not forbidden, but must be justified.
4. **Re-scoring from stored JSON is free.** Any purely arithmetic change (weights, penalties, normalisation) can be evaluated over the whole corpus instantly. Prefer these.
5. **Deterministic layers must be explainable and reversible.** The user has to be able to see why a score moved and undo it.
6. **Ground truth is scarce.** ~20 hand-labelled roles exist; the model-judgement eval has 5 fixtures. Everything else is unlabelled. **Expanding this is the résumé agent's highest-value contribution.**
7. **Privacy.** The repo is public. The master résumé lives at `~/.config/jobhunt/eval-resume.md` and must never be committed. Eval fixtures must be paraphrased or synthetic.
8. **Scale is small.** A few hundred jobs. Don't propose caching layers or indexes; O(N) over the corpus is free.

## 6. The résumé side of the contract

The insight that reframes this project: **most "scoring errors" the user reports are evidence gaps, not scoring gaps.** When the model marks a requirement missing and the user says "I do have this", the model was usually right *about the résumé*. A recruiter or ATS reading the same document would also miss it.

That makes the résumé agent a first-class participant rather than a consumer, with three jobs:

1. **Label ground truth.** For a given JD and the master résumé, produce the per-requirement verdicts (met/partial/missing, with reasoning) and an overall band. This is the benchmark jobhunt cannot produce.
2. **Distinguish the two failure classes.** For every disagreement with the scorer: is this *the résumé failing to evidence a real capability* (fix the résumé) or *the scorer misreading evidence that is present* (fix the scorer)? The routing decision is the whole game, and only the résumé agent can make it.
3. **Maintain a skills inventory** — capabilities the user has that the narrative résumé doesn't surface. Candidate input to scoring as a supplementary evidence block.

**A tension to name early:** a résumé edited to satisfy the scorer may be a worse résumé for humans. If the answer to every under-credit is "add the keyword", the master résumé degrades into a keyword pile that reads badly and interviews worse. The résumé agent should push back when jobhunt's proposed fix is "the user should write X" and X doesn't belong there.

## 7. Questions to resolve jointly

Answer these with evidence, not preference. Numbered so both sides can reference them.

1. **What is the operational definition of met / partial / missing?** Write it as a rubric a labeller can apply to unseen requirements and reach the same verdict twice. Include the hard cases: years-of-experience shortfalls, adjacent-domain experience, compound bullets, credentials/degrees, "or equivalent" clauses.
2. **Should `partial` exist at all?** It's the least reliable label and carries half the penalty weight. Would binary met/missing plus a confidence be more consistent?
3. **How should preferred qualifications count?** Currently near-parity with required (10 vs 12), which produces the saturation in §4. What's the defensible ratio, and should missing preferreds subtract at all rather than simply not adding?
4. **Should penalty be normalised by requirement count?** (α ≈ 5, prior 0.184 was proposed in an earlier review.) Validate against the labelled set rather than adopting on argument.
5. **Do the five dimensions earn their keep?** They're scored independently of the requirement assessments and can contradict them — #734 scored `required_qualifications` 75 while zero required qualifications were missing. Should the dimensions be *derived* from the assessments instead of separately generated?
6. **What's the right home for a skills inventory** — appended to the résumé text sent to the model, a separate prompt block, or a deterministic pre-pass? What does the eval say?
7. **Can user feedback be generalized without prompt injection?** Given constraint §5.2, is there a middle path — e.g. corrections that update the *résumé/skills* evidence rather than overriding *verdicts*, so generalization happens through the model's own judgement?
8. **Is the current scoring model good enough?** Price the alternatives. The eval harness (`tests/LLMEval/`) already runs N-model comparisons; deepseek scored 7/7 vs gemini-flash-lite's 5/7 on the judgement eval.

## 8. Success criteria

The proposal is better than today if, over the labelled set and the 415-job corpus:

- **No job missing zero required qualifications scores below the user's threshold** on preferred gaps alone.
- **Cap occupancy is negligible** (today 11%) — the score should carry information across its whole range.
- **MAE against hand labels under 5 points**, and no job with a missing *required* qualification scoring above 80.
- **Ranking quality holds:** the top 20 by score, judged by the résumé agent, are jobs worth applying to.
- **Existing eval fixtures don't regress.** A change that fixes #734 and breaks #231 is a loss.
- **Re-scored distribution is inspectable** before/after, from stored JSON, at zero LLM cost.

## 9. Non-goals

- Predicting whether the user gets an interview. The score ranks effort, not outcomes.
- Optimising for ATS keyword systems.
- Scoring at a scale this app won't reach.
- Any change that requires the user to author rules in the abstract — the previously rejected "never credit these" textbox. Corrections must be a by-product of reviewing real output.

## 10. Working agreement

- **Disagree in writing, with evidence.** jobhunt brings corpus statistics and eval results; the résumé agent brings ground-truth verdicts and career facts. An assertion neither can back is not a finding.
- **Route every disagreement** through §6.2: résumé gap or scorer gap?
- **Three substantive rounds per side** on any design point, then escalate to the user rather than continuing.
- **jobhunt owns the final call on feasibility and cost**; the résumé agent owns the final call on whether a verdict is *true*.
- Land changes as: rubric → labelled set → arithmetic/prompt change → re-score corpus → compare. Not the reverse.
