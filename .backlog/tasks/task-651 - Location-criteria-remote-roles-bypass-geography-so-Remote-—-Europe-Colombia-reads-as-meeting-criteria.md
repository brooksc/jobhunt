---
id: TASK-651
title: >-
  Location criteria: remote roles bypass geography, so "Remote —
  Europe/Colombia" reads as meeting criteria
status: To Do
assignee: []
created_date: '2026-07-27 20:19'
updated_date: '2026-07-27 20:19'
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
- [ ] #1 A remote role whose stated geography excludes the user does not read as meeting criteria
- [ ] #2 A bare "Remote" with no stated geography continues to meet criteria (no new false negatives)
- [ ] #3 The user can express a remote-eligibility region without conflating it with onsite preferred locations
- [ ] #4 Existing hybrid/onsite behaviour is unchanged
- [ ] #5 Pure logic is unit-tested: Remote - US, Remote (Europe), Remote with no geography, and remote with an unrelated HQ city in the location field
<!-- AC:END -->
