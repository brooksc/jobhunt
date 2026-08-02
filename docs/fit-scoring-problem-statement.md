# Requirement matching and fit scoring — joint problem statement

**Read this first. It assumes you have no prior context.** Two agents are working this problem from
different directories, with different access and complementary blind spots. Both are given this
same document.

## Start here: which agent are you?

**Look at your working directory.**

| If you are in… | You are the… | You own | You cannot see |
|---|---|---|---|
| `~/code/jobhunt` | **jobhunt agent** | The scoring pipeline: prompt, requirement decomposition, dimension scores, penalty arithmetic, the deterministic feedback layer, the eval harness, and measurement across ~412 scored jobs in the live store | Whether any individual verdict is *true*. You have no independent knowledge of what the user has actually done. |
| `~/Desktop/resume` | **résumé agent** | The master résumé, the skills inventory, the user's real career history, and the tailored résumés and cover letters generated from it | The code, the corpus-wide statistics, and what any proposal costs to build or run |

State which agent you are at the start of every message you write. Do not attempt the other agent's
job: jobhunt cannot verify a verdict, and the résumé agent cannot measure a distribution. Each will
produce a confident wrong answer if it tries.

**Why two agents.** Ground truth for "does this candidate meet this requirement?" exists only on the
résumé side. The ability to act on it across hundreds of jobs exists only on the jobhunt side.

---

## 0. The product, in one paragraph

JobHunt is a native macOS app the user runs to track their own job search — a few hundred
applications, one person. A browser extension captures a job posting; an LLM extracts structured
fields; a second LLM call scores the job against the user's résumé and produces a 0–100 **fit
score** plus a per-requirement breakdown. The user reads that breakdown to decide whether a job is
worth the hours it takes to tailor a résumé and apply.

## 1. What the score is for

> Of the jobs I've captured, which deserve the effort of applying?

Confirmed by the user, and this governs every tradeoff below:

- **The number drives a rough stack-rank, not a decision by itself.** The user reviews new jobs and
  moves them to Interested or Archive; for jobs already Interested, they work down the list from the
  top. **±2.5 accuracy would be nice; considerably worse is tolerable.** Do not sacrifice ranking
  quality to chase absolute calibration.
- **The two errors are not symmetric.** A false positive costs one wasted read and an archive click.
  A false negative hides a job the user would have wanted — permanently and invisibly. This
  asymmetry is settled policy elsewhere in the app (remote-location inference was deliberately made
  permissive on exactly this reasoning) and governs here too.
- **An unusable score is worse than no score.** A list where everything is 95 conveys nothing. So
  does a list where an eighth of the entries are 0.

## 2. How scoring works today

One LLM call per (job, résumé) pair returns JSON with:

**Five dimension scores, 0–100, weighted into a base:**

| Dimension | Weight |
|---|---|
| `required_qualifications` | 0.40 |
| `preferred_qualifications` | 0.20 |
| `skills` | 0.15 |
| `domain_fit` | 0.15 |
| `experience_level` | 0.10 |

**Plus `requirement_assessments`** — one entry per requirement, each with the requirement text,
`kind` ∈ {required, preferred}, `status` ∈ {met, partial, missing}, and `evidence`.

Final score = base − penalty, floored at 0, where penalty is a **raw sum**:

| | missing | partial |
|---|---|---|
| **required** | 12 | 6 |
| **preferred** | 10 | 5 |

capped at 60.

Prompt is `assessment_prompt_version = 3`. Two deterministic layers sit on top of the model output:

- **Non-discriminating filter** — drops requirements no candidate could fail ("capacity to learn
  Jira", "alignment with our values").
- **User corrections** (`ScoringFeedback`) — per-phrase overrides captured by clicking a flag next
  to a requirement: *I do have this* / *I don't have this* / *this isn't a real requirement* /
  *wrong for this job only*.

**The single most useful property of the system:** every analysis is stored as JSON, so the whole
corpus can be re-scored with different arithmetic **at zero LLM cost**. Any change to weights,
penalties or normalisation can be evaluated against 412 real jobs in seconds. Use this constantly.

## 3. The core problem

**Exact matching cannot work, and neither can naive semantic matching.** A requirement and a résumé
relate along three levels, and only the third matters:

1. **Lexical** — "Kubernetes" vs "Kubernetes". Rare, and often a trap: the word appears in a context
   that wouldn't survive an interview question.
2. **Semantic** — "container orchestration" vs "Kubernetes"; "stakeholder alignment" vs "drove
   consensus across five orgs". An LLM handles this well.
3. **Judgement** — *given what this person has actually done, and what this job actually needs,
   would a competent hiring manager consider this satisfied?* This is the real question, and it is
   not a text-similarity problem.

Level 3 fails in both directions:

**Over-crediting.** The model rewards *adjacent* experience. Job #231 asked for "background in
hardware or controls engineering" at a hardware manufacturer; a cloud-infrastructure PM résumé
scored 98. Job #718 counted "capacity to learn" and company values as met requirements. Unchecked,
everything lands in the high 80s–90s and the score stops discriminating. Prompt v3 addressed the
worst of this; residue remains (see §4).

**Under-crediting.** The model marks a requirement missing because the résumé doesn't *say* it, when
the user has in fact done it. Five of the six user corrections currently in the store are this, all
restating one underlying fact: the résumé under-evidences AI / gen-AI / agent work.

**The taxonomy itself is underspecified.** `met` / `partial` / `missing` is applied inconsistently
because nothing defines the boundaries. Is 6 years against "8+ years required" partial or met? Is
"PRDs for ML features" partial credit against "shipped LLM products"? Is a compound bullet asking
for two things, one of which you have, a `partial` — or two requirements, one `met` and one
`missing`? (Prompt v3 says decompose; the model does so unevenly.) These calls swing scores 20+
points, and **there is no written rubric a labeller — human or model — can apply consistently.**
Producing that rubric is the first joint deliverable.

## 4. What is measured, not asserted

All figures computed 2026-08-02 from the live store: **412 jobs** with a complete stored analysis,
**12,597 requirement assessments**.

**Score distribution is U-shaped** — both tails inflated, the middle hollowed out:

| Band | Share |
|---|---|
| 0–9 | **14%** |
| 10–49 | 23% |
| 50–79 | 26% |
| 80–89 | 12% |
| 90–100 | **25%** |

Median 66, mean 58.

**Penalty saturation is the cause of the bottom tail.**
- **11%** of rows hit the 60-point cap. Past the cap the score is flat — two very differently
  qualified candidates land on the same number and further gaps change nothing.
- **13%** miss *no* required qualification yet score under 40.
- Worked example, job #734 (Zscaler, Principal AI PM): base 58; 6 required met, 4 required partial,
  **zero required missing**, 5 preferred missing, 2 preferred partial. Raw penalty = 24 + 50 + 10 =
  84 → capped 60 → **score 0**. A missing *preferred* costs 10 against a missing *required*'s 12,
  and nothing normalises for requirement count, so a verbose posting is arithmetically guaranteed to
  saturate. Median posting has 7 required and 5 preferred requirements; the max seen is 25 required.

**The dimensions are internally consistent** — this was suspected as a defect and isn't. Comparing
the `required_qualifications` dimension against the share of required requirements marked met or
partial: mean absolute gap **5.2 points**, median 2.9, more than 25 points apart in only 3% of rows.
The model derives its dimensions from its own assessments. Don't spend effort reconciling them.

**The base is generous.** Weighted dimensions alone: median **84**, mean 80, below 50 in only 7% of
jobs. The penalty is currently doing the work of separating jobs, which is why breaking the penalty
breaks everything.

**User corrections don't generalize** — matching is a lowercased substring test and the UI captures
the whole requirement sentence:
- Five of six live rules match **exactly one** requirement out of 12,597 — the one they came from.
- The sixth is `IDE`, which matches *provide*, *identify*, *guidance*, *consider*: **359
  requirements across 124 of 412 jobs**, all force-credited to `met`.

**Prompt dilution is real and was measured.** A v4 experiment added one broad "omit
non-discriminating requirements" instruction; job #231 regressed from a correct 60 back to 96 on
`gemini-3.1-flash-lite`, because the new rule diluted the rules that were working. **This is why
user feedback is applied deterministically in code and never appended to the prompt**, and it is a
hard constraint on any proposal amounting to "just tell the model about the user's background."

## 5. Constraints — design inside these

1. **The scoring model is settled: `deepseek/deepseek-v4-flash` via OpenRouter.** It was benchmarked
   against `gemini-3.1-flash-lite` on the fit-judgement eval and passed 7/7 (gemini: 5/7), at lower
   cost. Local models (LM Studio / Ollama) remain supported. **If you believe the problem needs a
   frontier model, raise it with the user before designing around one** — don't assume it.
2. **Prompt budget is scarce and non-monotonic.** Adding instructions has measurably made scoring
   worse. Every prompt change must be justified against the eval set, not by argument.
3. **One call per (job, résumé).** Per-requirement calls multiply cost and latency by 10–20×. Not
   forbidden, but must be justified.
4. **Re-scoring from stored JSON is free.** Prefer changes that are pure arithmetic — they can be
   validated over the whole corpus immediately.
5. **Deterministic layers must be explainable and reversible.** The user must be able to see why a
   score moved and undo it.
6. **Ground truth is scarce.** ~20 hand-labelled roles, 5 judgement-eval fixtures. Everything else is
   unlabelled. Expanding this is the résumé agent's highest-value contribution; 20 is agreed as
   sufficient to start.
7. **Privacy.** The jobhunt repo is **public**. The master résumé (`~/.config/jobhunt/eval-resume.md`,
   same content as the résumé agent's master) and all exported job data must never be committed to
   it. Anything shared lives in the exchange directory below. Eval fixtures committed to the repo
   must be paraphrased or synthetic.
8. **Scale is small.** A few hundred jobs. Don't propose caching, indexes or pagination.

## 6. The résumé side of the contract

The insight that reframes this project: **most "scoring errors" the user reports are evidence gaps,
not scoring gaps.** When the model marks a requirement missing and the user says "I do have this",
the model was usually right *about the résumé*. A recruiter or ATS reading the same document would
also miss it.

The résumé agent therefore has three jobs:

1. **Label ground truth.** For a given posting and the master résumé, produce per-requirement
   verdicts with reasoning, and an overall band. This is the benchmark jobhunt cannot produce.
2. **Route every disagreement.** For each place the scorer differs from your judgement: is this *the
   résumé failing to evidence a real capability* (fix the résumé) or *the scorer misreading evidence
   that is present* (fix the scorer)? This routing decision is the whole collaboration.
3. **Maintain a skills inventory** — capabilities the user has that the narrative résumé doesn't
   surface, as candidate supplementary evidence for scoring.

**A tension to name early:** a résumé edited to satisfy the scorer may be a worse résumé for humans.
If the answer to every under-credit is "add the keyword", the master degrades into a keyword pile
that reads badly and interviews worse. **The résumé agent should push back** when jobhunt's proposed
fix is "the user should write X" and X doesn't belong there.

**On résumé format specifically** (the user asked, and wants this kept minimal): JobHunt must work
for other users' résumés, so **no format is mandated and none should be**. Any guidance must be
generic and optional. What demonstrably helps a scorer of any kind:

- **Name the specific technology, standard or certification** where it's true. Prompt v3 requires a
  literal name for full credit precisely because "worked on GPU-adjacent systems" is not evidence of
  CUDA — and a human screener would reach the same conclusion.
- **Include scope markers** (team size, budget, users, revenue) — these are what `experience_level`
  and seniority judgements key on.
- **State the domain**, since `domain_fit` means industry and product, not transferability.

That is the whole list. Resist growing it: every addition is a constraint on users who aren't this
one.

## 7. Questions to resolve jointly

Answer with evidence, not preference. Numbered for cross-reference.

1. **What is the operational definition of met / partial / missing?** Write it as a rubric a labeller
   can apply to unseen requirements and reach the same verdict twice. Must cover: years-of-experience
   shortfalls, adjacent-domain experience, compound bullets, degrees and credentials, "or equivalent"
   clauses, and requirements about the company rather than the candidate. **This is deliverable #1 —
   nothing else can be validated without it.**
2. **Should `partial` exist at all?** It's the least reliable label and carries half the penalty
   weight. Would binary met/missing plus a confidence be more consistent?
3. **How should preferred qualifications count?** Currently near-parity with required (10 vs 12),
   which produces the saturation in §4. What is the defensible ratio? Should missing preferreds
   subtract at all, rather than simply not adding?
4. **Should the penalty be normalised by requirement count?** A concrete proposal with measured
   results is already on the table — see `proposals/P1-normalized-penalty.md` in the exchange
   directory. Attack it; don't re-derive it from scratch.
5. **Is the base too generous?** Median base is 84 (§4). If the penalty stops being a blunt
   corrective, the base's calibration becomes load-bearing. This is a prompt/model question, and it
   needs labels to answer.
6. **Where should a skills inventory live** — appended to the résumé text sent to the model, a
   separate prompt block, or a deterministic pre-pass? What does the eval say?
7. **Can user feedback be generalized without prompt injection?** Given §5.2, is there a middle path
   — e.g. corrections that update the *résumé/skills evidence* rather than overriding *verdicts*, so
   generalisation happens through the model's own judgement? (Live defects: TASK-659.)

## 8. Success criteria

Better than today means, over the labelled set and the 412-job corpus:

- **Ranking is right.** The top 20 by score, judged by the résumé agent against the master résumé,
  are jobs worth applying to. This is the primary criterion.
- **No job missing zero required qualifications scores below the user's threshold** on preferred-
  qualification gaps alone.
- **Cap occupancy is negligible** (today 11%) and the zero pile is gone (today 14% under 10).
- **Jobs with a missing required qualification separate cleanly** from those without.
- **Absolute error within ~±2.5 of hand labels is desirable, not required.** Do not trade ranking
  quality for it.
- **Existing eval fixtures don't regress.** A change that fixes #734 and breaks #231 is a loss.
- **Every claim is backed by a re-score over the corpus**, which costs nothing.

## 9. Non-goals

- Predicting whether the user gets an interview. The score ranks effort, not outcomes.
- Optimising for ATS keyword systems.
- Scoring at a scale this app will never reach.
- Any change requiring the user to author rules in the abstract — a "never credit these" textbox was
  proposed and rejected. Corrections must be a by-product of reviewing real output.
- Mandating a résumé format (§6).

## 10. How the two agents exchange work

Shared directory, outside the public repo, readable and writable by both:

```
~/Desktop/resume/fitscore-collab/
├── corpus/       jobhunt writes: one JSON per job — posting text, model assessments,
│                 dimension scores, current score, and an empty `ground_truth` block
├── labelled/     résumé agent writes: the same files with `ground_truth` filled in
├── proposals/    jobhunt writes: scoring changes with measured before/after over the corpus
├── messages/     both: `NNN-<from>-<topic>.md`, numbered in sequence, newest last
└── DECISIONS.md  both: append-only log of what was agreed and why
```

**jobhunt agent — to export more jobs for labelling:**

```bash
cd ~/code/jobhunt
./scripts/export-fit-analysis.py --limit 20        # newest 20 scored jobs
./scripts/export-fit-analysis.py --jobs 231 734    # specific job numbers
```

Reads the store read-only, so it is safe while the app is running. 20 jobs are already exported.

**Working agreement**

- **Disagree in writing, with evidence.** jobhunt brings corpus statistics and eval results; the
  résumé agent brings ground-truth verdicts and career facts. An assertion neither can back is not a
  finding.
- **Route every disagreement through §6.2:** résumé gap or scorer gap?
- **Three substantive rounds per side** on a design point, then escalate to the user.
- **jobhunt owns the final call on feasibility and cost. The résumé agent owns the final call on
  whether a verdict is true.**
- **Order of work:** rubric (§7.1) → labelled set → arithmetic/prompt change → re-score corpus →
  compare. Not the reverse. Reversing this order is how the v4 regression happened.
- **Nothing ships without the user's review.** Produce recommendations; do not implement scoring
  changes unprompted.
