---
id: TASK-035
title: SettingsStore + Keychain + BackgroundStore ModelActor
status: To Do
assignee: []
created_date: '2026-06-07 22:44'
labels:
  - swift-rewrite
  - core
  - data
milestone: m-1
dependencies:
  - TASK-034
documentation:
  - swift-plan.md
  - server/db.js
priority: high
ordinal: 1200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Provide the typed settings layer and the background SwiftData actor that all write-heavy/background work funnels through (the concurrency backbone from §6.2).

## Read first
- swift-plan.md §6.2 (concurrency model — ModelActor), §6.3 (settings + Keychain), §0 (API keys in Keychain).
- Legacy server/db.js: SETTINGS_DEFAULTS and the settings get/set helpers (~30 keys: llm_provider, llm_model, llm_base_url, llm_api_key_*, preferred_locations, allow_remote/hybrid/onsite, location_filter_enabled, queue paused flag, availability settings, pricing, llm_consent_* flags, followup/snooze days, debug level, openrouter rotation). Reproduce keys + defaults exactly.

## Implement (core/Services/ or core/Settings/)
- `SettingsStore` (@Observable) backed by the Setting model: typed accessors for every setting with defaults centralized (mirror SETTINGS_DEFAULTS). Read on main actor for UI; writes go through the actor.
- **API keys NOT in SwiftData** — store llm_api_key_* in Keychain (a small KeychainStore wrapper). Settings stores only the provider/model/base_url and consent flags.
- `BackgroundStore` as `@ModelActor`: owns a background ModelContext for all background mutations (bulk ops, queue, availability, demo seeding). Provide helpers for batched insert/update/save. UI updates propagate via SwiftData change tracking (no manual broadcast — replaces the old SSE).
- Consent flags helper: get/set llm_consent_<provider>; localhost providers (LM Studio, Foundation Models) always considered consented (§13.3).

## Dependencies
Depends on task-034 (models: Setting). Consumed by the LLM engine, all bulk operations, and Settings/Onboarding UI.

## Tests (CoreTests)
- Default values returned when unset; set/get round-trip; Keychain wrapper stores/reads/deletes a key; consent flag logic (cloud requires explicit consent, localhost auto-consented); ModelActor performs a batched write off the main actor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SettingsStore exposes every legacy setting key with matching defaults
- [ ] #2 API keys stored in Keychain via KeychainStore, never in SwiftData
- [ ] #3 BackgroundStore @ModelActor performs batched background writes; UI @Query views update without manual refresh
- [ ] #4 Consent helper: cloud providers require explicit consent, localhost providers auto-consented
- [ ] #5 CoreTests cover defaults, round-trip, Keychain, consent logic, and an off-main-actor batched write
<!-- AC:END -->
