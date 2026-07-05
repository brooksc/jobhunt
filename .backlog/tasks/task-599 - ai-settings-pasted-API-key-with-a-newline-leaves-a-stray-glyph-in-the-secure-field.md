---
id: TASK-599
title: >-
  ai settings: pasted API key with a newline leaves a stray glyph in the secure
  field
status: Done
assignee: []
created_date: '2026-07-05 19:48'
labels:
  - ai
  - settings
  - ui
dependencies: []
modified_files:
  - core/LLM/AIProviderFormModel.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Onboarding/OnboardingView.swift
  - tests/CoreTests/AIProviderFormModelTests.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Pasting an API key with a trailing newline into the AI Provider secure field left the newline visible (a stray dot/glyph). The stored key is already correct — `AIProviderFormModel.onAPIKeyChanged` strips all whitespace (`filter { !$0.isWhitespace }`, tested since TASK-541) — so this was purely a SwiftUI/AppKit display bug: when a Binding's setter sanitizes pasted text, `SecureField`'s field editor keeps showing the pre-sanitized text and doesn't re-read the shorter bound value.

Fix: `onAPIKeyChanged` now increments `apiKeySanitizeCount` only when stripping actually changed the string, and both secure fields (Settings AI tab + Onboarding) key their `.id()` on that count. When a paste is sanitized, the id changes, SwiftUI rebuilds the field, and it re-initializes from the clean bound value — dropping the stray glyph. Ordinary clean typing never bumps the count, so the field isn't rebuilt (and focus isn't dropped) during normal input.

Tradeoff: when whitespace IS stripped (paste with newline, or the rare case of typing a space), the field rebuilds and loses focus — acceptable since that only happens on a sanitizing edit, and a paste is a terminal action.</description>
<parameter name="acceptanceCriteria">["Pasting an API key with a trailing newline shows the clean key (no stray glyph) in the Settings AI tab and Onboarding secure fields", "apiKeySanitizeCount bumps only when characters are actually stripped; clean input never bumps it (so the field isn't rebuilt / focus retained)", "The stored key remains whitespace-free (existing behavior)", "CoreTests green; app builds; lint/format clean"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added apiKeySanitizeCount (bumped only on an actual strip) to AIProviderFormModel and keyed the API-key SecureField .id() on it in SettingsView + OnboardingView, so a sanitized paste rebuilds the field and re-reads the clean value instead of leaving the pasted newline glyph. Stored key was already clean. Added a CoreTests case for the bump semantics; app builds; lint/format clean.
<!-- SECTION:FINAL_SUMMARY:END -->
