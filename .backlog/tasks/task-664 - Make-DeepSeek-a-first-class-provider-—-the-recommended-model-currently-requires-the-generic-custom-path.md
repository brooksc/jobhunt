---
id: TASK-664
title: >-
  Make DeepSeek a first-class provider — the recommended model currently
  requires the generic "custom" path
status: To Do
assignee: []
created_date: '2026-08-05 18:13'
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
- [ ] #1 deepseek appears as a named provider with a working default base URL
- [ ] #2 Model list and per-1M pricing populate, so the Settings cost estimate is non-zero and correct
- [ ] #3 API key is stored in the Keychain, consistent with the other cloud providers
- [ ] #4 A job can be extracted and scored end-to-end against the direct DeepSeek API
- [ ] #5 The recommendation page states when to choose direct vs OpenRouter
<!-- AC:END -->
