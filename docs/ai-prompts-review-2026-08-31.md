# Fit-scoring prompt review, 2026-08-31

A review of `ai-prompts.md` prompted by a specific ranking failure, written from outside
the codebase by an agent that spent a day using fit scores to choose which jobs to write
applications for. It proposes changes to the **fit-scoring prompt and the dimension
definitions**; it does not revisit extraction, retries, or transport, which that document
already covers well.

Everything here is either grounded in a stored score whose rationale contradicts the role
it scored, or in a measurable property of the corpus. Where I could not establish
something without running an eval, it says so. **No recommendation below is specific to a
company, a board, or a candidate** — each is a general property of the rubric.

---

## The failure that prompted this

Two postings at the same company, scored against the same résumé, same prompt version,
minutes apart:

| Job | Role | Level | Score | Actually the better application? |
|---|---|---|---|---|
| 1108 | Senior Program Manager, Enterprise Technology & AI | Senior | **94** | No |
| 777 | Principal Product Manager, AI Software Factory | Principal | **90** | Yes |

Job 1108 is a CIO-organization role: enterprise applications, business systems, corporate
IT services, internal data platforms. Its users are the company's own employees. The
candidate has no enterprise-IT, ERP, or enterprise-architecture background at all.

Job 777 is a product role on the company's AI agent platform, defining an end-to-end
software-creation experience. The candidate is a contributor to an open-source coding
agent, wrote its multi-agent orchestration component, uses coding agents daily as work
tooling, and previously owned an external developer platform.

The rubric ranked the role he cannot do above the role he is unusually well matched to,
by four points. That is not a close call being resolved slightly wrong. Three separate
mechanisms produced it, and each is fixable in the prompt.

---

## 1. `domain_fit` asks about the company, not about the role

**This is the largest single defect and the direct cause of the inversion above.**

The current definition:

> "domain_fit": relevance of the candidate's INDUSTRY and PRODUCT background to this role
> — the field the company operates in and the kind of thing it builds

The clause after the dash points the model at **the employer**, not at **the work**. For
job 1108 the model scored `domain_fit` 90 with this rationale:

> "The candidate brings extensive experience in developer platforms, AI infrastructure,
> and enterprise software systems, aligning closely with GitLab's product and operational
> domain."

Read that carefully: it is a true statement about the *company* and an irrelevant one
about the *job*. The posting is for internal corporate IT. What the employer sells has
almost no bearing on whether someone can run the business-systems portfolio behind it.

**The same model, on the same day, at the same company, applied the rule in the opposite
direction.** Job 777 — the actual product role on the actual product — scored `domain_fit`
**85**, five points lower, with this rationale:

> "He has extensive domain experience in developer platforms, API ecosystems, and AI
> tooling, though his recent primary corporate focus was AI infrastructure and governance
> rather than a dedicated DevSecOps product."

So the product role was *penalized* for not matching the employer's product closely enough,
while the internal-IT role was *rewarded* for matching the employer's product it has
nothing to do with. That is not a borderline judgement call going the wrong way twice by
chance; it is the definition sending the model to the wrong referent and the answer
depending on which way the adjacency happened to fall. A rubric that produces opposite
readings of the same phrase for two roles at one company is underspecified, and the
underspecified part is "domain of what."

This is a systematic blind spot, not a one-off. Every employer has roles whose domain is
unrelated to its product: IT and corporate engineering, finance and revenue operations,
trust and safety, workplace, internal tooling, GTM operations, security compliance.
A candidate with strong product-side experience at that employer's *category* will score
`domain_fit` high on all of them, because the rubric asked about the category.

The v3 note ("`domain_fit` means industry and product rather than transferable craft") was
the right correction to make and it did not go far enough: it separated *craft* from
*domain* but left *domain* pointing at the company.

**Recommended replacement:**

```
- "domain_fit": relevance of the candidate's background to THE WORK THIS POSTING
  DESCRIBES. Judge three things and take the weakest:
    (a) the subject matter of the role's day-to-day work
    (b) who the role serves — external customers and developers, or the company's own
        employees and internal operations
    (c) the industry, only where the industry genuinely constrains the work
        (regulated fields such as clinical, financial, or defence; not otherwise)
  What the employer sells is evidence about (c) at most, and often not even that. An
  internal IT, corporate engineering, finance-operations, workplace, or GTM-operations
  role does not inherit the domain of the company's product: score it against the
  internal function it actually sits in. Score domain_fit low when the candidate has not
  done this kind of work for this kind of user, however strong they are otherwise. The
  other dimensions already credit transferable skill; do not credit it twice here.
```

Cost: about 90 tokens of prompt. Expected effect: it should pull internal-facing roles
down toward their true fit and leave product-facing ones unchanged. **Untested — this
needs an eval run against the hand-labelled fixtures, which I could not do.** The
existing labelled set is the right instrument, and roles whose function differs from the
company's product should be over-sampled in it, because that is the population where the
current rubric is wrong.

---

## 2. `experience_level` is one-sided, which is why it looks useless

`ai-prompts.md` §10.3 observes that `experience_level` averages 90 across 872 v3 scores,
that 54% of them are exactly 95, and concludes the dimension should be removed and its
weight redistributed.

I think the diagnosis is right and the remedy is wrong. The dimension is constant because
the prompt made it one-directional:

> "experience_level": alignment between the candidate's seniority/years and the role's level

"Alignment" is symmetric in ordinary English, but every stored rationale treats exceeding
the bar as satisfying it. On a mid-level posting asking 2-3 years, scored against a
22-year principal-level résumé, the model returned **85** with the rationale "substantially
exceeds the mid-level seniority requested." Exceeding by two decades cost fifteen points.
On job 1108, a Senior posting scored against the same principal-level résumé, it returned
95.

A dimension that only measures a floor will read near-constant for any experienced
candidate, which is exactly the distribution §10.3 reports. That is a symptom of the
definition, not evidence the axis carries no signal.

Over-leveling is a real and common rejection cause. It is also one of the few things a
résumé and a posting jointly determine with high confidence, since the fit prompt is
already given `Seniority`. Making it symmetric turns a dead dimension into a
discriminating one at zero token cost:

```
- "experience_level": two-sided alignment between the candidate's seniority and the
  role's level. 100 means the candidate sits at the level the posting is pitched at.
  Score DOWN for being materially under the bar, and score DOWN for being materially
  over it: a principal- or director-level candidate against a role scoped for two to
  three years of experience is misaligned, not overqualified-and-therefore-excellent.
  Two levels of distance in either direction should not score above 60. Judge level,
  not raw years: a long career at one level is not seniority.
```

**Recommendation: fix the definition first and re-measure before deleting the dimension.**
If the distribution stays degenerate after the change, §10.3's removal argument stands and
is then supported by evidence about the right question. If it spreads, the corpus gains a
signal it currently lacks, and one that bears directly on the failure in this review — 777
is a level match and 1108 is a level-down, and the current rubric scored the level-down
higher on this axis.

---

## 3. The named-technology rule has no counterpart for function or audience

§3's NAMED-TECHNOLOGY RULE is the strongest thing in the fit prompt. It stops exactly the
adjacency inflation that produces false "met" verdicts:

> working with hardware that runs CUDA is not CUDA expertise, and compliance experience
> with one regime is not experience with a different named regime

There is no equivalent rule for the *function* a role sits in or the *users* it serves,
and those generalize just as wrongly:

- running an external developer platform is not running internal enterprise IT
- building a product for engineers is not operating the business systems that engineers'
  employer runs on
- program management in an infrastructure org is not program management in a
  finance-operations org
- security *compliance* is not security *engineering*

Requirement assessments on job 1108 show the pattern. "Familiarity with Enterprise Tech
domains such as business systems, data, AI, security, infrastructure, or enterprise
architecture" scored `met`, with evidence citing GPU clusters, data-query reliability, and
API platform architecture. The posting's list is an *alternatives menu*, and v3's
ALTERNATIVES RULE should have applied — judge against the option the posting emphasises,
which for a CIO-org role is business systems and enterprise architecture, both absent.
The rule exists and did not fire, most likely because the menu's other options are
genuinely present and the model took the easy path.

**Recommended addition, next to the named-technology rule:**

```
  - FUNCTION AND AUDIENCE RULE: when a qualification is about a kind of work or a kind
    of user rather than a named technology, the same restraint applies. Experience
    serving external customers or developers is not experience serving internal
    employees, and the reverse. Experience in one organizational function (product,
    corporate IT, finance operations, trust and safety, GTM) is not experience in
    another, even at the same seniority and even when the craft transfers. Adjacent
    function or adjacent audience is "partial" at best.
```

This also gives the ALTERNATIVES RULE something concrete to bite on, since "the option
this posting is actually about" is usually determined by function and audience.

---

## 4. Extraction does not capture who the role serves

Sections 1 through 3 all depend on the model inferring the role's function and audience
from a summary and a requirements list. That inference is cheap to make explicit, and the
fit prompt is currently given **no location, no salary, no employment type, no URL** —
so it is already working from a thin slice.

**Recommended new extraction key:**

```
- serves: one of "external_customers", "external_developers", "internal_employees",
  "mixed", or null — who the role's output is FOR. A role building the company's
  product serves external customers or developers; a role running the systems the
  company itself operates on serves internal employees. Read this from the
  responsibilities and the named partner teams, not from the company description.
```

Then render it in the fit prompt beside `Seniority`, and reference it in `domain_fit`.

This is a small, well-formed classification with a closed vocabulary and it is almost
always determinable from the posting. It is a better candidate for a new field than most,
because §10.2 correctly argues for *removing* keys nothing reads — this one would have
three readers on day one.

If added, it should replace rather than accompany `benefits`, whose deletion §10.2 already
justifies on measured grounds.

---

## 5. Postings with weak requirements score high, and nothing corrects for it

`FitScorer.computeScore` normalizes gap penalties by how many requirements the posting
listed. The consequence is structural: a posting that lists eight easy requirements the
candidate clears trivially generates no penalties and scores near the dimension ceiling,
while a demanding posting that stretches the candidate generates penalties and scores
lower. The corpus already contains the extreme case — a part-time hourly role scoring 99.

This is a known and documented property, and the honest framing is that `fit_score`
answers "does the candidate satisfy what this posting asked for," which is a different
question from "is this worth applying to." The trouble is that a single number displayed
next to a job is read as the second question no matter what the documentation says. That
is what happened here.

Two options, in order of preference:

**(a) Report a stretch indicator alongside the score.** Nothing new from the model is
needed — the ingredients are already stored. Something as simple as the ratio of
requirements marked `met` with direct evidence to total requirements, combined with the
posting's seniority against the candidate's, distinguishes "clears a low bar" from
"matches a high one." A job at 94 that clears every requirement trivially and a job at 90
that matches a demanding posting are different objects and should not sort together.

**(b) Rename the field in the UI.** `fit_score` invites the wrong reading;
`requirements_match` does not. This costs nothing and prevents the misreading at the
source, though it also gives up the convenience of one sortable number.

I would not recommend folding desirability into the existing score. It would make an
already-uncomparable metric worse, and it depends on candidate preferences the app does
not model.

---

## 6. Résumé text containing meta-commentary depresses scores

This one is new evidence rather than a reading of the document, and it is worth recording
because it is invisible from inside the app.

The stored résumé is prose the scorer reads as evidence about the candidate. If that text
contains editorial instructions **about** the résumé, the scorer reads them as facts about
the person. A master résumé maintained for an agent's use may contain lines such as
"do not claim X" or "this was coordination, not ownership" — calibration notes for the
writer that a scorer reads as the candidate lacking X.

Concretely: a master document that had accumulated framing caveats, do-not-claim lists,
and correction notices was 51,755 characters, of which about 6,800 were agent-facing
annotation. Stripping it to 44,920 characters of pure prose removed instructions sitting
directly beside the skills line telling the reader which skills not to credit.

**Recommendation:** note in the résumé-import path, or in user-facing documentation, that
the stored résumé should be the document a recruiter would read, with no editorial or
meta-commentary. This costs nothing and prevents a failure mode with no symptom — scores
come back plausible, just uniformly lower, and nothing indicates why.

This also strengthens §10.1's case for a shorter résumé, from a second direction: the
argument there is cost, and the argument here is accuracy. A purpose-built 6 KB variant is
unlikely to contain meta-commentary; a 45 KB master maintained by hand over months is
likely to.

---

## 7. Version incomparability should be enforced, not documented

§9 establishes that the store holds 994 v1 scores, 12 v2, 872 v3, and 3 unversioned, that
the versions are not comparable, and that recomputation cannot reconcile them because the
model's judgement moved rather than the arithmetic.

It is then documented and left there, while `min_score` remains available as a filter and
a single `fit_score` remains sortable across the whole corpus. More than half the stored
scores were produced by a rubric that no longer exists, and v3 is described as
systematically harsher — so any sort or threshold over the full corpus is systematically
biased toward the older, more generous population.

**Recommendation:** make the version visible where the score is, and either exclude
non-current versions from `min_score` and default sorts, or surface a count of stale
scores with a one-click rescore. `reflects_previous_resume_version` already exists as a
precedent for exactly this kind of staleness flag; version staleness deserves the same
treatment and is more consequential, because a résumé change moves one job's score while
a rubric change moves the whole ranking.

---

## What I did not evaluate

- **Whether any of these change scores materially.** Every recommendation above needs
  `tests/LLMEval` against the hand-labelled fixtures. I had neither budget nor a running
  app. Sections 1 and 2 are the two worth measuring first, and job 1108 against job 777
  is a ready-made regression case: the correct outcome is 777 above 1108.
- **Extraction, retries, transport, structured output.** Already well covered, and
  nothing I saw contradicted §2, §5, §7, or §8.
- **§10.1 through §10.5.** I agree with all five as written, with the single amendment to
  §10.3 in section 2 above: fix `experience_level`'s definition and re-measure before
  removing it.

## Summary

| # | Change | Where | Cost | Confidence |
|---|---|---|---|---|
| 1 | `domain_fit` judges the role's work, not the employer's product | fit prompt | ~90 tokens | High — a stored rationale contradicts its own posting |
| 2 | `experience_level` becomes two-sided | fit prompt | 0 | High on the diagnosis, untested on the remedy |
| 3 | Function-and-audience rule beside the named-technology rule | fit prompt | ~70 tokens | High — same failure class the tech rule already fixed |
| 4 | Extract who the role serves | extraction prompt, schema, fit prompt | ~50 tokens, offset by dropping `benefits` | Medium — enables 1 and 3 |
| 5 | Stretch indicator, or rename to `requirements_match` | scoring / UI | 0 model cost | Medium |
| 6 | Document that stored résumés carry no meta-commentary | docs / import | 0 | High — observed directly |
| 7 | Enforce version incomparability rather than noting it | scoring / UI | 0 model cost | High — already established in §9 |

Items 1, 2, 3 and 5 all bear on the same failure: the rubric currently rewards a candidate
for clearing an easy bar in the wrong domain at the wrong level, and reports it as a
better match than a demanding role they are genuinely suited to.
