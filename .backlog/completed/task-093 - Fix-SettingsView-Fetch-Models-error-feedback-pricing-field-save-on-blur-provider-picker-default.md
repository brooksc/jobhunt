---
id: TASK-093
title: >-
  Fix SettingsView: Fetch Models error feedback, pricing field save on blur,
  provider picker default
status: Done
assignee: []
created_date: '2026-06-10 07:32'
updated_date: '2026-06-10 22:24'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: `Fetch Models` button empty `catch` block — errors are silently swallowed. Fix: show error in `connectionStatus` or a dedicated error label.

HIGH: Pricing TextFields only save `.onSubmit` — clicking away discards edits silently. Fix: also save on focus loss (`.focused` + `.onChange`, or `@FocusState`).

HIGH: `selectedProviderID` hard-initialized to `"lmstudio"` (line 100) before `onAppear` syncs from settings. If sheet appears before onAppear, picker shows wrong value. Fix: initialize from settings synchronously.

MEDIUM: `Clear` button next to model picker sets `fetchedModels = []` (hides picker) but doesn't reset `settings.llmModel`. Misleading — should either clear the model or be relabeled "Show TextField".

MEDIUM: Consent sheet external dismiss leaks `pendingProviderID`. Fix: use `.onDisappear` to clear it.

Files: `app/Views/Settings/SettingsView.swift`, `app/Views/Settings/LLMConsentSheet.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fetch Models shows an error message when the request fails
- [ ] #2 Editing pricing fields and clicking away saves the values
- [ ] #3 Provider picker shows the correct saved provider on first render (before onAppear)
- [ ] #4 Clear button either resets the saved model or is relabeled to avoid confusion
- [ ] #5 Dismissing consent sheet without confirming properly resets pendingProviderID
<!-- AC:END -->
