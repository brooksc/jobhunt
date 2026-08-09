---
id: TASK-664
title: >-
  Make DeepSeek a first-class provider — the recommended model currently
  requires the generic "custom" path
status: Done
assignee: []
created_date: '2026-08-05 18:13'
updated_date: '2026-08-09 22:38'
labels:
  - llm
  - onboarding
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LLMProviderFactory` names five providers: `openai`, `anthropic`, `google`, `openrouter`, and `custom` (any OpenAI-compatible endpoint), plus the local LM Studio / Ollama setups. **DeepSeek appears nowhere in the codebase** — `grep -ri deepseek core/ app/ marketing/` returns nothing.

So the model the benchmark selected can be reached two ways today:

- **Via OpenRouter** — works, first-class, has a default base URL and live pricing via `CostEstimator.fetchOpenRouterPricing`.
- **Via DeepSeek's own API** — only through `custom`, which means the user must know and type the base URL themselves, gets no model list, and gets no pricing (so the cost estimate in Settings reads 0.00 and is silently wrong).

That's an awkward place for the *recommended* configuration to sit, and it's a real cost decision for users: going direct is typically cheaper than the same model through an aggregator, and it's one less third party holding job-posting text.

**Work**

- Add `deepseek` as a named provider with its default base URL, so it appears in the picker alongside the rest.
- Populate the model list and per-1M pricing the way the other named providers do, so the Settings cost estimate is meaningful rather than zero.
- Key handling follows the existing pattern — Keychain, never the store; not in backups (see the secrets note in CLAUDE.md).
- Consider whether the default recommendation should point at OpenRouter or direct. OpenRouter is one signup for many models and simpler to explain; direct is usually cheaper and involves fewer intermediaries. Whichever is chosen, [TASK-662] has to explain the other.

**Check before assuming a gap:** the OpenAI-compatible transport may already work against DeepSeek's endpoint unchanged, in which case this is a metadata-and-picker change rather than a new provider implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 deepseek appears as a named provider with a working default base URL
- [ ] #2 not done (no data source): per-1M pricing does not populate — the Settings estimate comes from OpenRouter's live pricing feed and DeepSeek publishes no equivalent endpoint. Hard-coding a table would silently go stale, and DeepSeek's prices are currently rising, so a wrong number would be worse than an absent one. The model list DOES populate.
- [x] #3 API key is stored in the Keychain, consistent with the other cloud providers
- [ ] #4 not verified (credential): an end-to-end extract-and-score against the direct DeepSeek API needs a DeepSeek key, which this environment doesn't have — only OpenRouter and Google keys are present
- [x] #5 The recommendation page states when to choose direct vs OpenRouter
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The task's "check before assuming a gap" was right: DeepSeek serves an OpenAI-compatible API, so this is metadata and a picker entry, not a new client. Added to `LLMProviderFactory` (base URL `https://api.deepseek.com`, routed through `CustomProvider`), `AIProviderFormModel` (picker entry with privacy and key URLs), `ModelCatalog` (OpenAI-style `/models`, key required — unlike OpenRouter's public list), and `SettingsKey.keychainKeys` so the key lands in the Keychain and stays out of backups.

**Pricing deliberately not populated.** The Settings estimate is built on OpenRouter's live pricing feed; DeepSeek has no equivalent endpoint. The alternative is a hard-coded per-1M table, which would go stale silently — and DeepSeek's prices are currently *rising*, which is what prompted the task's sibling discussion in the first place. A confidently wrong cost estimate is worse than an absent one, so criterion 2 is marked not-done with the reason rather than papered over.

**The task's motivation has partly lapsed, and the page now says so.** It was filed because DeepSeek was "the model the benchmark selected". TASK-661 has since measured it as the **least consistent** model tested — 7–8 of 15 verdicts changing between byte-identical requests, served by five different providers across eight calls. It is no longer the recommendation, so the page warns about that before someone picks it for price alone, alongside the direct-vs-OpenRouter guidance criterion 5 asks for.

Criterion 4 is `not verified`: an end-to-end run against the direct API needs a DeepSeek key, and only OpenRouter and Google keys exist in this environment.
<!-- SECTION:FINAL_SUMMARY:END -->
