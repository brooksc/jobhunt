#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Export stored fit analyses for the two-agent scoring collaboration.

Reads the live SwiftData store READ-ONLY (it is single-writer; this never opens it for writing, so
it is safe with the app running) and writes one JSON file per job into the shared exchange
directory, plus a corpus-wide summary.

    scripts/export-fit-analysis.py                 # newest 20 scored jobs
    scripts/export-fit-analysis.py --jobs 231 734  # specific job numbers
    scripts/export-fit-analysis.py --limit 50

Each file carries the job description, the model's requirement assessments and dimension scores,
and the current score — everything the résumé agent needs to label ground truth, and nothing it
would have to ask for.

Output is the user's own private job and résumé data: it goes to ~/Desktop/resume/fitscore-collab,
NEVER into this repo, which is public.
"""

import argparse
import json
import pathlib
import sqlite3
import sys

STORE = pathlib.Path.home() / "Library/Application Support/Jobhunt/jobhunt.store"
OUT = pathlib.Path.home() / "Desktop/resume/fitscore-collab/corpus"

WEIGHTS = {
    "required_qualifications": 0.40,
    "preferred_qualifications": 0.20,
    "skills": 0.15,
    "domain_fit": 0.15,
    "experience_level": 0.10,
}


def connect() -> sqlite3.Connection:
    if not STORE.exists():
        sys.exit(f"No store at {STORE}")
    return sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)


def fetch(conn: sqlite3.Connection, job_numbers: list[int] | None, limit: int) -> list[dict]:
    where = "f.ZFITSTATUS = 'succeeded' AND f.ZFITSCOREJSON LIKE '%requirement_assessments%'"
    params: list = []
    if job_numbers:
        where += f" AND j.ZJOBNUMBER IN ({','.join('?' * len(job_numbers))})"
        params += job_numbers
    rows = conn.execute(
        f"""SELECT j.ZJOBNUMBER, j.ZCOMPANY, j.ZTITLE, j.ZLOCATION, c.ZURL,
                   c.ZCLEANEDDESCRIPTION, f.ZFITSCORE, f.ZMODEL, f.ZFITSCOREJSON
            FROM ZJOBFITSCORE f
            JOIN ZJOB j ON j.Z_PK = f.ZJOB
            -- description lives on the capture, not the job
            LEFT JOIN ZCAPTURE c ON c.ZJOB = j.Z_PK
            WHERE {where}
            ORDER BY f.ZSCOREDAT DESC LIMIT ?""",
        params + [limit],
    ).fetchall()

    out, seen = [], set()
    for num, company, title, location, url, desc, score, model, js in rows:
        if num in seen:  # one row per job — the newest score wins
            continue
        seen.add(num)
        try:
            analysis = json.loads(js)
        except json.JSONDecodeError:
            continue
        out.append(
            {
                "job_number": num,
                "company": company,
                "title": title,
                "location": location,
                "url": url,
                "job_description": desc,
                "current_score": score,
                "scoring_model": model,
                "dimensions": analysis.get("dimensions", []),
                "requirement_assessments": analysis.get("requirement_assessments", []),
                "ground_truth": {
                    "_instructions": (
                        "résumé agent: fill this in. For each requirement above, give the verdict "
                        "you would defend to a hiring manager, and say whether a disagreement with "
                        "the model is a RESUME gap (the capability exists but isn't evidenced) or a "
                        "SCORER gap (the evidence is there and was misread)."
                    ),
                    "requirement_verdicts": [],
                    "overall_band": None,
                    "notes": None,
                },
            }
        )
    return out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--jobs", type=int, nargs="*", help="specific job numbers")
    p.add_argument("--limit", type=int, default=20)
    args = p.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    with connect() as conn:
        jobs = fetch(conn, args.jobs, args.limit if not args.jobs else 1000)

    for job in jobs:
        (OUT / f"job-{job['job_number']}.json").write_text(json.dumps(job, indent=2) + "\n")

    summary = {
        "exported": len(jobs),
        "job_numbers": sorted(j["job_number"] for j in jobs),
        "scoring_weights": WEIGHTS,
        "penalty_grid_current": {
            "required_missing": 12,
            "required_partial": 6,
            "preferred_missing": 10,
            "preferred_partial": 5,
            "cap": 60,
        },
    }
    (OUT / "_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Wrote {len(jobs)} job files to {OUT}")


if __name__ == "__main__":
    main()
