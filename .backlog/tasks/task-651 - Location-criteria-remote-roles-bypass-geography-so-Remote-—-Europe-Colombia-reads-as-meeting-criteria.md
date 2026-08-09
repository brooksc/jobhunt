---
id: TASK-651
title: >-
  Location criteria: remote roles bypass geography, so "Remote —
  Europe/Colombia" reads as meeting criteria
status: Done
assignee: []
created_date: '2026-07-27 20:19'
updated_date: '2026-08-09 19:36'
labels:
  - extraction
  - filters
  - data-quality
  - workflow
dependencies: []
references:
  - core/LLM/LocationCriteria.swift
  - core/LLM/PromptBuilder.swift
  - core/Services/JobFilterRules.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LocationCriteria.meets` deliberately ignores preferred locations for remote roles:

```swift
switch remoteType {
case .remote: return allowRemote          // geography never checked
case .hybrid: return allowHybrid && hasMatch
case .onsite: return allowOnsite && hasMatch
case .unknown, .none: return allowOnsite && hasMatch
}
```

The rationale is sound in isolation — a remote posting's `location` is often "Remote" or an unrelated HQ city, so matching it against preferred locations would produce false negatives. But the consequence is that **a remote role in any geography passes**, including ones the user isn't eligible for. "Remote - Colombia", "Remote (Europe)", "Remote — India" all read as *Meets criteria* for a US-based candidate.

There is currently **no way to express "remote, but must be US-eligible"** — setting `preferred_locations` does not help, because the remote branch never consults it.

Reported via jobs #342 (Nebius, Amsterdam) and #316 (Five9, remote Colombia). Both currently *do* fail criteria, but only by accident: their work mode failed to extract (`null`/`unknown`), so they fell into the `unknown ≈ onsite` branch. Had extraction correctly said `remote`, both would have displayed "Meets criteria". The user is presently protected by extraction failures, not by the filter — and this gets *worse* as extraction improves.

Design notes:
- The signal usually lives in the posting text ("Remote - US", "Remote (EMEA)", "must be authorised to work in the US"), not in a clean field. Extracting a *remote region / eligibility* is probably the real fix, rather than string-matching the existing `location`.
- A bare "Remote" with no geography must NOT start failing — that's the common case, and a false negative there would be worse than today's false positive.
- This feeds fit scoring too, not just the filter.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A remote role whose stated geography excludes the user does not read as meeting criteria
- [x] #2 A bare "Remote" with no stated geography continues to meet criteria (no new false negatives)
- [x] #3 The user can express a remote-eligibility region without conflating it with onsite preferred locations
- [x] #4 Existing hybrid/onsite behaviour is unchanged
- [x] #5 Pure logic is unit-tested: Remote - US, Remote (Europe), Remote with no geography, and remote with an unrelated HQ city in the location field
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Criteria 1, 2, 4 and 5 were already satisfied by `RemoteGeography` (11 existing tests), which had replaced the `case .remote: return allowRemote` short-circuit the report quotes. Criterion 3 — expressing remote eligibility without conflating it with onsite preferences — was the real gap, and underneath it a worse assumption.

**New setting `remote_eligibility_regions`,** separate from `preferredLocations`, surfaced in Settings → Location and threaded through `ExtractionSettings`, `LocationContext`, both `LocationCriteria.meets` callers, and `recomputeMeetsCriteria`. Empty reproduces the previous behaviour exactly.

**The assumption it exposed:** `RemoteGeography.classify` consulted a hardcoded `usTokens` list as an *eligibility* signal, so "Remote - US" passed for everyone. Fine while the app assumed a US-based user; wrong the moment the user says otherwise. With explicit regions set, any **recognised** region that isn't theirs now rules the posting out — including the US. Unrecognised text ("Global", "Multiple Locations", an unrelated HQ city) is still `indeterminate` and still passes, so the asymmetry that guards against false negatives is intact; it simply no longer treats one country as everyone's home.

I found this because the test failed first: with eligibility `Canada`, `Remote - United States` still passed, because `usTokens` short-circuits to `.eligible` before any foreign check.

**Tests** (`RemoteEligibilityRegionTests`, 7): foreign remote ruled out; bare "Remote"/nil/"Global" still pass; eligibility works independently of commuting preference in both directions; unrelated HQ city; empty setting falls back; the setting applies even with no preferred locations (a path that returned early); hybrid and onsite unchanged. All 26 location tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
