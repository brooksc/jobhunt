---
id: TASK-485
title: Fix empty consent popup when selecting a cloud LLM provider
status: Done
assignee: []
created_date: '2026-06-18 16:54'
labels:
  - bug
  - ux
  - settings
  - swiftui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Selecting a cloud provider (e.g. Google) in Settings → LLM showed a tiny empty white popup instead of the "Send data to <provider>?" consent sheet, so consent couldn't be granted and the provider couldn't be switched.

Root cause: a SwiftUI empty-sheet race. The consent sheet used `.sheet(isPresented: $showingConsentSheet)` whose content read a SEPARATE optional `pendingProviderID` via `if let`. `handleProviderChange` set both `@State`s in one update; SwiftUI rendered the sheet before the optional propagated, so `if let` was nil and the content closure produced an empty view.

Fix: drive the sheet with `.sheet(item: $pendingConsent)` (a small Identifiable `ConsentRequest` wrapping the provider id). `.sheet(item:)` only presents when the value is non-nil and hands it to the content, eliminating the race, and auto-clears on dismiss.

Files: app/Views/Settings/SettingsView.swift, app/Views/Settings/LLMConsentSheet.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Selecting a cloud provider (Google/OpenAI/Anthropic/OpenRouter) shows the full consent sheet with title, body, privacy link, and Cancel/I Agree buttons
- [ ] #2 Agreeing grants consent and switches the provider; cancelling leaves the prior provider selected
- [ ] #3 The custom-provider base-URL consent path also presents the populated sheet
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The empty consent popup was a SwiftUI empty-sheet race: `.sheet(isPresented: $showingConsentSheet)` with content reading a separate optional `pendingProviderID` via `if let`. `handleProviderChange` set the Bool and the optional in one state update; SwiftUI presented the sheet before the optional propagated, so the `if let` was nil and rendered an empty view (the tiny white box).

Fix (app/Views/Settings/SettingsView.swift): replaced the `Bool + optional` pair with a single `@State pendingConsent: ConsentRequest?` (a small Identifiable wrapper around the provider id) and switched to `.sheet(item: $pendingConsent)`. `.sheet(item:)` only presents when the value is non-nil and passes it straight to the content, so the consent sheet always has its provider — no race. It also auto-clears the item on dismiss, so the onAgree/onCancel closures no longer need to nil it (onAgree applies the provider change; onCancel is a no-op because the Picker stays on the prior provider until consent is granted). Updated both trigger sites (the provider Picker and the custom base-URL consent path).

Build-verified (Jobhunt-DMG). This is SwiftUI presentation glue with no unit-test seam; the `.sheet(item:)` pattern is the canonical fix for this class of empty-sheet bug. Recommend a quick manual confirm: Settings → LLM → select Google → the populated "Send data to Google?" sheet should appear.
<!-- SECTION:FINAL_SUMMARY:END -->
