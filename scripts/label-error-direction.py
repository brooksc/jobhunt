#!/usr/bin/env python3
"""Which way does the scorer err — too generous, or too harsh?

Reads the hand-labelled jobs and cross-tabulates the model's verdict against the labeller's, so the
direction of error is measured rather than assumed. Requires no LLM calls: it compares verdicts
already stored in the label files.

    ./scripts/label-error-direction.py [labelled-dir]

Written because TASK-669 was filed to "attack partial→met over-crediting" on the strength of a count
of 21 `partial → met`. In the notation the labels actually use — model → truth — that is the model
saying *partial* where the truth is *met*, i.e. UNDER-crediting, and the labeller's own notes on those
rows read "UNDER-credit". Tightening what qualifies as `met`, which is what the task proposed, would
have made the most common error worse. Hence a script rather than a one-off count: the direction is
easy to invert in your head and expensive to get wrong.

Labels live outside the repo (they quote résumé facts and this repo is public), so the path is an
argument with a default.
"""
import collections
import glob
import json
import os
import sys

DEFAULT_DIR = os.path.expanduser("~/Desktop/resume/fitscore-collab/labelled")

# Ordered weakest to strongest, so "the model said less than the truth" is a simple comparison.
RANK = {"missing": 0, "partial": 1, "met": 2}


def main() -> int:
    directory = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    files = sorted(glob.glob(os.path.join(directory, "job-*.json")))
    if not files:
        print(f"No labelled jobs in {directory}", file=sys.stderr)
        return 1

    pairs = []
    for path in files:
        with open(path) as handle:
            data = json.load(handle)
        verdicts = {v["index"]: v for v in data["ground_truth"]["requirement_verdicts"]}
        for index, assessment in enumerate(data["requirement_assessments"]):
            truth = verdicts.get(index)
            if not truth:
                continue
            got, want = assessment.get("status"), truth.get("ground_truth_status")
            # DROP means "not a real requirement" — a judgement about the posting, not the scorer.
            if got not in RANK or want not in RANK:
                continue
            pairs.append((got, want))

    counts = collections.Counter(pairs)
    agree = sum(n for (g, w), n in counts.items() if g == w)
    over = sum(n for (g, w), n in counts.items() if RANK[g] > RANK[w])
    under = sum(n for (g, w), n in counts.items() if RANK[g] < RANK[w])

    print(f"{len(pairs)} assessments with a usable ground truth, across {len(files)} jobs\n")
    print(f"{'model':>8} -> {'truth':<8} {'count':>6}")
    for (got, want), n in counts.most_common():
        direction = "agree" if got == want else ("OVER-credit" if RANK[got] > RANK[want] else "under-credit")
        print(f"{got:>8} -> {want:<8} {n:6}   {direction}")

    total = max(len(pairs), 1)
    print(f"\nagree        {agree:4}  ({100 * agree / total:.0f}%)")
    print(f"over-credit  {over:4}  ({100 * over / total:.0f}%)   model more generous than the truth")
    print(f"under-credit {under:4}  ({100 * under / total:.0f}%)   model harsher than the truth")
    if under > over:
        print("\nThe scorer errs HARSH on this set. Tightening the `met` threshold would worsen the")
        print("dominant error, not fix it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
