---
id: TASK-035
title: SettingsStore + Keychain + BackgroundStore ModelActor
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:44'
updated_date: '2026-06-08 01:47'
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
- [x] #1 SettingsStore exposes every legacy setting key with matching defaults
- [x] #2 API keys stored in Keychain via KeychainStore, never in SwiftData
- [x] #3 BackgroundStore @ModelActor performs batched background writes; UI @Query views update without manual refresh
- [x] #4 Consent helper: cloud providers require explicit consent, localhost providers auto-consented
- [x] #5 CoreTests cover defaults, round-trip, Keychain, consent logic, and an off-main-actor batched write
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. core/Settings/KeychainStore.swift — Security framework wrapper: store/read/delete String by service+key
2. core/Settings/SettingsStore.swift — @Observable, reads Setting from SwiftData context, typed accessors with SETTINGS_DEFAULTS, API key accessors delegate to KeychainStore
3. core/Settings/ConsentHelper.swift — isConsented(provider:) logic: localhost providers auto-consented, cloud requires flag
4. core/Services/BackgroundStore.swift — @ModelActor owning a background ModelContext; batchInsert, batchSave helpers
5. Tests/CoreTests/SettingsStoreTests.swift — defaults, set/get, Keychain, consent, off-main-actor write
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented SettingsStore, KeychainStore, ConsentHelper, and BackgroundStore. KeychainStore.swift wraps Security framework (set/get/delete by service+account). SettingsStore (@Observable) backed by Setting SwiftData model; cache-on-load for reads; typed accessors for all 31 legacy settings with exact SETTINGS_DEFAULTS values; API keys (SettingsKey.keychainKeys) routed to Keychain, never SwiftData. ConsentHelper.isConsented: localhost providers (lmstudio, foundation_models, custom) always true; cloud providers read llm_consent_<provider> flag. BackgroundStore @ModelActor provides insert, insertBatch, update, delete, fetch, save helpers — UI @Query updates automatically via SwiftData change tracking. 20 new CoreTests (+ 18 existing = 38 total), all passing: defaults, set/get, Keychain round-trip, API key not in SwiftData, consent grant/revoke, BackgroundStore async insert and batch insert."
<!-- SECTION:FINAL_SUMMARY:END -->
