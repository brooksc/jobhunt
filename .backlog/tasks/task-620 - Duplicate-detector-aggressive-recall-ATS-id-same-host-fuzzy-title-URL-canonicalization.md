---
id: TASK-620
title: >-
  Duplicate detector: aggressive recall (ATS id, same-host, fuzzy title, URL
  canonicalization)
status: To Do
assignee: []
created_date: '2026-07-22 20:07'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The duplicate detector missed real duplicates in the user's Interested/New/Applied jobs (same posting captured from different URL forms/sources). Improve recall (user confirms duplicates manually, so false positives are low-risk):

A. Match on the ATS/posting id extracted from the URL (Greenhouse gh_jid / job-boards jobs/N, Workday `_P…` req, Ashby/Lever UUID, LinkedIn view/currentJobId) — same id = same posting regardless of title/host/text.
B. Allow same-host duplicates (drop the two-distinct-hostname requirement).
C. Fuzzy title matching (token subset / Jaccard ≥ threshold) within a company cluster for slight cross-source title variations.
D. Canonicalize ATS URL variants (subsumed by A for dedup).

Real missed pairs: Pinterest #191/#331 & #122/#329 (same gh_jid), Zillow #196/#348 (Workday req), SecurityScorecard #148/#361 (same board), Pulumi #129/#130 (LinkedIn post vs view), Toast #165/#304 (aggregator vs company, title suffix).
<!-- SECTION:DESCRIPTION:END -->
