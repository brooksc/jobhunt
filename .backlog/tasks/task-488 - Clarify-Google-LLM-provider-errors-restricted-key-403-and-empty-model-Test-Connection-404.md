---
id: TASK-488
title: >-
  Clarify Google/LLM provider errors: restricted-key 403 and empty-model Test
  Connection 404
status: Done
assignee: []
created_date: '2026-06-18 18:26'
updated_date: '2026-06-18 18:26'
labels:
  - bug
  - ux
  - llm
  - settings
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A user added a valid Gemini key but got "Could not load models (HTTP 403)" on Fetch Models and "LLM HTTP 404" on Test Connection.

Diagnosis (not an app request bug — the endpoints are correct): an *invalid* Gemini key returns HTTP 400 ("API key not valid"), but a 403 means the key is real yet *forbidden* — almost always a restricted key (HTTP-referrer / IP / app restrictions) or the Generative Language API not enabled on its project. The 404 on Test Connection was because no model was selected, so the request hit Google's `models/:generateContent` (empty model).

The app reported both unhelpfully. Fixes:
- ModelCatalog surfaces the provider's own error message (Google/OpenAI/Anthropic `{error:{message}}`) and adds a 401/403 hint ("key rejected — use an unrestricted key with the API enabled").
- Test Connection fails fast with "Select or enter a model first" when no model is set, and surfaces the server reason + 401/403 hint for real HTTP errors instead of the bare "LLM HTTP <code>".
- Connection-failure label wraps (was lineLimit 2).

Files: core/LLM/ModelCatalog.swift, app/Views/Settings/SettingsView.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fetch Models 401/403 shows an actionable message (restricted key / API not enabled) plus the provider's own error text
- [x] #2 Test Connection with no model selected shows 'Select or enter a model first' instead of a 404
- [x] #3 Test Connection HTTP errors surface the provider's error message + a 401/403 hint
- [x] #4 The connection-status failure text can wrap to show the full message
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Root cause was not an app request bug — verified the Google endpoint is correct: an invalid key returns HTTP 400 ("API key not valid"), so the user's 403 means a real-but-forbidden key (restricted by HTTP-referrer/IP/app, or the Generative Language API not enabled on its project). The 404 on Test Connection was because no model was selected (request hit `models/:generateContent`). The app just reported both opaquely.

Fixes:
- `ModelCatalog.get` now parses the provider error body (`{error:{message}}`, shared by Google/OpenAI/Anthropic) and threads it into `ModelCatalogError.httpError(statusCode:serverMessage:)`; `errorDescription` adds a 401/403 hint ("the API key was rejected — use an unrestricted key with the provider's API enabled") and appends the provider's own message. So the Gemini 403 now reads e.g. "…(HTTP 403): the API key was rejected… \nGenerative Language API has not been used in project … or it is disabled."
- `SettingsView.testConnection` fails fast with "Select or enter a model first" when the model is empty (kills the misleading 404), and for `LLMProviderError.httpError` surfaces a 401/403 hint + the parsed server message instead of "LLM HTTP <code>".
- The `.failure` connection-status Label now wraps (lineLimit 5 + fixedSize) so the richer message is readable.

Tests: `ModelCatalogErrorTests` (403 hint, embedded provider message, no auth-hint on a 500). Updated the one existing pattern-match for the new associated value. Build + full fast gate green.

Note for the user: the 403 is on their key — they'll need a Gemini API key without application restrictions, with the Generative Language API enabled for its project. They can also type a model name manually (the Model field is editable) instead of relying on Fetch Models.
<!-- SECTION:FINAL_SUMMARY:END -->
