---
id: TASK-663
title: >-
  Surface the model recommendation where the choice is made — onboarding step 3
  and Settings → AI
status: Done
assignee: []
created_date: '2026-08-05 18:12'
updated_date: '2026-08-09 22:46'
labels:
  - onboarding
  - ui
  - docs
dependencies:
  - TASK-662
modified_files:
  - core/LLM/ModelRecommendation.swift
  - core/LLM/AIProviderFormModel.swift
  - app/Views/Onboarding/OnboardingView.swift
  - app/Views/Settings/SettingsView.swift
  - tests/CoreTests/ModelRecommendationTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A page nobody finds is worth nothing. The two places a user is actually deciding which model to use are:

- **Onboarding step 3** — `AIProviderStep` in `app/Views/Onboarding/OnboardingView.swift:231`. This is the first time anyone is asked, and it's the moment of maximum ignorance: the user has no data, no scores, and no way to judge whether their choice is working.
- **Settings → AI** — `app/Views/Settings/LLMTab.swift`, where the provider, model, base URL and cost pricing already live.

Both should link to the "Which AI model should I use?" page ([TASK-662]).

**Design notes**

- In onboarding, prefer a **one-tap path** over a link that sends the user to a browser mid-setup: "Use the recommended setup" that selects the provider and model for them, with the link as the secondary route for anyone who wants the reasoning. A user who leaves onboarding to read a web page may not come back.
- The link text should promise the answer — *"Not sure? See which model we recommend and what it costs"* — not just "Learn more".
- In Settings the link belongs next to the **Provider/Model** rows, not buried under cost pricing.
- The app already computes a live cost estimate for the current corpus in the AI pane. Where that's shown, it's worth stating the unit a user thinks in (per 100 postings) rather than only raw token counts.
- **Don't hardcode the recommended model in two places.** If onboarding can preselect it, that value and the page's recommendation must come from one source, or they will drift the first time the recommendation changes.

MAS builds ship the same onboarding, so whatever is linked must be a public URL rather than anything DMG-only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Onboarding's AI provider step links to the recommendation page
- [x] #2 Settings → AI links to it next to the provider/model rows
- [x] #3 Onboarding offers a one-tap recommended setup that does not require leaving the app
- [x] #4 The recommended provider/model is defined in one place, not duplicated between onboarding and the page
- [x] #5 Link text states what the reader will get, not 'learn more'
- [x] #6 Works identically in MAS builds (public URL, no DMG-only dependency)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
New `ModelRecommendation` in JobhuntCore is the single definition of the suggested provider/model, help URL and link text (#4). Onboarding's AI step and Settings → AI both read it (#1, #2) and both offer a one-tap "use our recommendation" via `AIProviderFormModel.applyRecommendation()`, which sets provider then model in that order — `applyProviderChange` resets `modelText`, so the reverse silently loses the model (#3). Link text names what the page answers rather than "learn more" (#5), and a test asserts that plus the https/public-host property that makes it work identically in the sandboxed MAS build (#6).

The one-line summary quotes the cost measured in `which-model.html` ($0.12/100 jobs) instead of a second estimate, and points at Haiku for anyone who wants steadier answers — the constant carries a comment tying it to the TASK-661 measurement so a future re-run updates both.

4 tests in CoreTests/ModelRecommendationTests. Gate: fast gate TEST SUCCEEDED, swiftlint 0 violations, swiftformat 0.61.1 0/317 files require formatting.

not verified: (visual) — that the new link and button read well in the onboarding step and the Settings AI tab at real window sizes. No screen access was taken for this task; the compiler and the model-level tests cover behaviour, not layout.
<!-- SECTION:FINAL_SUMMARY:END -->
