#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Measure fit-scoring quality defects across the stored corpus. No LLM calls.

Every check here is a comparison against a source document or a structural property of the
requirement text, so it can be re-run after a model change or a résumé re-sync to see whether the
change helped. That is the point: without it, a re-score produces different numbers with no way to
tell whether they are better.

    scripts/analyze-fit-quality.py                   # measure the current corpus
    scripts/analyze-fit-quality.py --json            # machine-readable, for before/after diffs
    scripts/analyze-fit-quality.py --baseline b.json # compare against a saved run

Reads the live store READ-ONLY, so it is safe with the app running.

WHAT IT MEASURES

  fabricated evidence   Quoted spans in `evidence` that appear in no résumé the user has ever had.
                        Measured at 32% on deepseek-v4-flash, of which 74% were lifted verbatim from
                        the job posting — the model quoting the JD back as though it were the résumé.
                        Split into `jd_lifted` (a grounding failure) and `invented` (a factual claim
                        about the user), because they differ in severity.

  fragment requirements Bare noun phrases scored as if they were requirements ("IDE", "CLI",
                        "Governance"). Measured at 35% of `preferred` vs 1.8% of `required`, carrying
                        20% of all penalty points; 42% of jobs at the penalty cap would fall below it
                        without them.

  verdict distribution  met/partial/missing by kind. The headline over-crediting signal: 83% of
                        required requirements were marked `met` on deepseek-v4-flash. A model that
                        abstains instead of fabricating should push this DOWN, and scores with it.

  cap occupancy         Share of jobs pinned at the 60-point penalty cap, where the score has stopped
                        responding to further gaps.
"""

import argparse
import collections
import json
import pathlib
import re
import sqlite3
import sys
import unicodedata

STORE = pathlib.Path.home() / "Library/Application Support/Jobhunt/jobhunt.store"
RESUME_DIR = pathlib.Path.home() / "Desktop/resume"

WEIGHTS = {
    "required_qualifications": 0.40,
    "preferred_qualifications": 0.20,
    "skills": 0.15,
    "domain_fit": 0.15,
    "experience_level": 0.10,
}
COST = {
    ("required", "missing"): 12,
    ("required", "partial"): 6,
    ("preferred", "missing"): 10,
    ("preferred", "partial"): 5,
}
PENALTY_CAP = 60

# A quoted span, not opened or closed mid-word so `don't` and `it's` don't read as quotes.
QUOTE = re.compile(
    r"(?<![A-Za-z0-9])['‘]([^'‘’\n]{4,120})['’](?![A-Za-z])"
    r"|(?<![A-Za-z0-9])[\"“]([^\"“”\n]{4,120})[\"”]"
)
ELLIPSIS = re.compile(r"\.\.\.|…")


def norm(s: str) -> str:
    """Fold quotes, dashes and whitespace so a match isn't missed on typography alone."""
    s = unicodedata.normalize("NFKD", s or "")
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("—", "-"), ("–", "-")]:
        s = s.replace(a, b)
    return re.sub(r"\s+", " ", s).lower()


def is_fragment(text: str) -> bool:
    """A bare noun phrase with nothing assessable in it — "IDE", "Governance", "Partners"."""
    t = (text or "").strip()
    words = t.split()
    if not words:
        return True
    if len(words) <= 3 and not re.search(r"\b(years?|degree|bachelor|master|mba|phd)\b", t, re.I):
        return not re.search(
            r"\b(experience|ability|proven|strong|excellent|deep|knowledge|familiar)\b", t, re.I
        )
    return False


def connect() -> sqlite3.Connection:
    if not STORE.exists():
        sys.exit(f"No store at {STORE}")
    return sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)


def load(conn: sqlite3.Connection) -> tuple[dict, list[str], dict]:
    """Newest analysis per job, every résumé text ever stored, and each job's posting."""
    rows = conn.execute(
        """SELECT j.ZJOBNUMBER, f.ZFITSCORE, f.ZFITSCOREJSON, f.ZMODEL
           FROM ZJOBFITSCORE f JOIN ZJOB j ON j.Z_PK = f.ZJOB
           WHERE f.ZFITSTATUS = 'succeeded' AND f.ZFITSCOREJSON LIKE '%requirement_assessments%'
           ORDER BY f.ZSCOREDAT DESC"""
    ).fetchall()
    jobs = {}
    for num, score, js, model in rows:
        if num in jobs:  # newest wins
            continue
        try:
            jobs[num] = {"score": score, "model": model, "analysis": json.loads(js)}
        except json.JSONDecodeError:
            continue

    # Every résumé the user has ever had active, so a quote from an older version isn't
    # miscounted as fabricated. Plus anything in the résumé directory, deliberately generous.
    sources = [norm(t) for (t,) in conn.execute("SELECT ZTEXT FROM ZRESUME") if t]
    if RESUME_DIR.exists():
        for p in RESUME_DIR.rglob("*.md"):
            if "fitscore-collab" in str(p):
                continue
            try:
                sources.append(norm(p.read_text()))
            except OSError:
                pass

    descs = {}
    for num, desc in conn.execute(
        "SELECT j.ZJOBNUMBER, c.ZCLEANEDDESCRIPTION FROM ZJOB j LEFT JOIN ZCAPTURE c ON c.ZJOB = j.Z_PK"
    ):
        if desc and num not in descs:
            descs[num] = norm(desc)
    return jobs, sources, descs


def measure(jobs: dict, sources: list[str], descs: dict) -> dict:
    assessments = [(n, r) for n, j in jobs.items() for r in j["analysis"].get("requirement_assessments", [])]

    quoted = fabricated = jd_lifted = fab_met = 0
    fab_jobs: set[int] = set()
    for num, r in assessments:
        for m in QUOTE.finditer(r.get("evidence", "") or ""):
            span = (m.group(1) or m.group(2)).strip()
            if ELLIPSIS.search(span) or len(span) < 5:
                continue
            quoted += 1
            q = norm(span)
            if any(q in s for s in sources):
                continue
            fabricated += 1
            fab_jobs.add(num)
            if r.get("status") == "met":
                fab_met += 1
            if descs.get(num) and q in descs[num]:
                jd_lifted += 1

    by_kind: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    frag_by_kind: dict[str, int] = collections.Counter()
    kind_totals: dict[str, int] = collections.Counter()
    for _, r in assessments:
        kind = r.get("kind") if r.get("kind") in ("required", "preferred") else "unset"
        kind_totals[kind] += 1
        by_kind[kind][r.get("status")] += 1
        if is_fragment(r.get("requirement")):
            frag_by_kind[kind] += 1

    # Penalty attributable to fragments, and how much of the cap they account for.
    pen_all: dict[int, int] = collections.Counter()
    pen_frag: dict[int, int] = collections.Counter()
    for num, r in assessments:
        # An unset kind is treated as `required` — matching FitScorer.requirementGaps.
        kind = r.get("kind") if r.get("kind") in ("required", "preferred") else "required"
        cost = COST.get((kind, r.get("status")), 0)
        pen_all[num] += cost
        if is_fragment(r.get("requirement")):
            pen_frag[num] += cost
    capped = [n for n in jobs if pen_all[n] >= PENALTY_CAP]
    capped_only_by_fragments = [n for n in capped if pen_all[n] - pen_frag[n] < PENALTY_CAP]

    scores = sorted(j["score"] for j in jobs.values() if j["score"] is not None)
    models = collections.Counter(j["model"] for j in jobs.values())

    def pct(a: int, b: int) -> float:
        return round(100 * a / b, 1) if b else 0.0

    return {
        "jobs": len(jobs),
        "assessments": len(assessments),
        "models": dict(models),
        "score_distribution": {
            "median": scores[len(scores) // 2] if scores else None,
            "mean": round(sum(scores) / len(scores), 1) if scores else None,
            "pct_zero": pct(sum(1 for s in scores if s == 0), len(scores)),
            "pct_under_10": pct(sum(1 for s in scores if s < 10), len(scores)),
            "pct_90_plus": pct(sum(1 for s in scores if s >= 90), len(scores)),
        },
        "fabricated_evidence": {
            "quoted_spans": quoted,
            "fabricated": fabricated,
            "pct_fabricated": pct(fabricated, quoted),
            "jd_lifted": jd_lifted,
            "pct_of_fabrications_lifted_from_posting": pct(jd_lifted, fabricated),
            "invented": fabricated - jd_lifted,
            "supporting_met": fab_met,
            "jobs_affected": len(fab_jobs),
        },
        "verdicts": {
            kind: {
                "n": kind_totals[kind],
                "met": pct(by_kind[kind]["met"], kind_totals[kind]),
                "partial": pct(by_kind[kind]["partial"], kind_totals[kind]),
                "missing": pct(by_kind[kind]["missing"], kind_totals[kind]),
                "fragments_pct": pct(frag_by_kind[kind], kind_totals[kind]),
            }
            for kind in sorted(kind_totals)
        },
        "penalty": {
            "points_total": sum(pen_all.values()),
            "points_from_fragments": sum(pen_frag.values()),
            "pct_from_fragments": pct(sum(pen_frag.values()), sum(pen_all.values())),
            "jobs_at_cap": len(capped),
            "pct_at_cap": pct(len(capped), len(jobs)),
            "capped_only_because_of_fragments": len(capped_only_by_fragments),
        },
    }


def render(m: dict, baseline: dict | None) -> None:
    def delta(path: list[str]) -> str:
        if not baseline:
            return ""
        cur, old = m, baseline
        for k in path:
            if not isinstance(cur, dict) or not isinstance(old, dict) or k not in cur or k not in old:
                return ""
            cur, old = cur[k], old[k]
        if not isinstance(cur, (int, float)) or not isinstance(old, (int, float)):
            return ""
        d = round(cur - old, 1)
        return f"  ({d:+})" if d else "  (=)"

    print(f"corpus: {m['jobs']} jobs, {m['assessments']} requirement assessments")
    print(f"models: {', '.join(f'{k or 'unknown'}={v}' for k, v in m['models'].items())}")

    s = m["score_distribution"]
    print("\nscores")
    print(f"  median {s['median']}{delta(['score_distribution', 'median'])}"
          f"   mean {s['mean']}{delta(['score_distribution', 'mean'])}")
    print(f"  zero {s['pct_zero']}%{delta(['score_distribution', 'pct_zero'])}"
          f"   >=90 {s['pct_90_plus']}%{delta(['score_distribution', 'pct_90_plus'])}")

    f = m["fabricated_evidence"]
    print("\nfabricated evidence quotes  (quoted spans in `evidence` found in no résumé)")
    print(f"  {f['fabricated']}/{f['quoted_spans']} = {f['pct_fabricated']}%"
          f"{delta(['fabricated_evidence', 'pct_fabricated'])}"
          f"   across {f['jobs_affected']} jobs")
    print(f"  lifted verbatim from the job posting: {f['jd_lifted']}"
          f" ({f['pct_of_fabrications_lifted_from_posting']}%)   invented: {f['invented']}")
    print(f"  supporting a `met` verdict: {f['supporting_met']}")

    print("\nverdicts by kind")
    for kind, v in m["verdicts"].items():
        print(f"  {kind:9} n={v['n']:5}  met {v['met']:5}%{delta(['verdicts', kind, 'met'])}"
              f"  partial {v['partial']:5}%  missing {v['missing']:5}%"
              f"  fragments {v['fragments_pct']:5}%{delta(['verdicts', kind, 'fragments_pct'])}")

    p = m["penalty"]
    print("\npenalty")
    print(f"  from fragment requirements: {p['pct_from_fragments']}%"
          f"{delta(['penalty', 'pct_from_fragments'])} of {p['points_total']} points")
    print(f"  jobs at the {PENALTY_CAP}-point cap: {p['jobs_at_cap']} ({p['pct_at_cap']}%)"
          f"{delta(['penalty', 'pct_at_cap'])}"
          f"   of which fragments alone put {p['capped_only_because_of_fragments']} there")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", action="store_true", help="emit JSON (save it to use as a baseline)")
    ap.add_argument("--baseline", type=pathlib.Path, help="a saved --json run to compare against")
    ap.add_argument(
        "--by-model",
        action="store_true",
        help="break every metric down by scoring model — the model bake-off, on real postings",
    )
    args = ap.parse_args()

    with connect() as conn:
        jobs, sources, descs = load(conn)

    if args.by_model:
        groups = collections.defaultdict(dict)
        for num, job in jobs.items():
            groups[job["model"] or "unknown"][num] = job
        per_model = {
            model: measure(sub, sources, descs)
            for model, sub in sorted(groups.items(), key=lambda kv: -len(kv[1]))
        }
        if args.json:
            print(json.dumps(per_model, indent=2))
            return
        for model, metrics in per_model.items():
            print(f"\n{'=' * 78}\n{model}\n{'=' * 78}")
            render(metrics, None)
            f = metrics["fabricated_evidence"]
            # Rate-per-quote hides how *often* a model quotes at all: one that rarely cites can post
            # a low percentage while still being the safer choice, or the reverse. Normalise by job.
            print(f"  fabricated quotes per job: "
                  f"{round(f['fabricated'] / metrics['jobs'], 2) if metrics['jobs'] else 0}"
                  f"   (quotes attempted per job: "
                  f"{round(f['quoted_spans'] / metrics['jobs'], 2) if metrics['jobs'] else 0})")
        return

    metrics = measure(jobs, sources, descs)
    if args.json:
        print(json.dumps(metrics, indent=2))
        return
    baseline = json.loads(args.baseline.read_text()) if args.baseline else None
    render(metrics, baseline)


if __name__ == "__main__":
    main()
