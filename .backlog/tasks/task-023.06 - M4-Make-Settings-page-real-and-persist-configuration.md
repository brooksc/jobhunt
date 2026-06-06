---
id: TASK-023.06
title: 'M4: Make Settings page real and persist configuration'
status: Done
assignee: []
created_date: '2026-05-27 18:06'
updated_date: '2026-05-28 22:26'
labels:
  - m4
  - web
  - ui-audit
  - settings
dependencies: []
modified_files:
  - src/jobhunt/static/screens/settings.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - src/jobhunt/extract.py
  - src/jobhunt/models.py
  - tests/
parent_task_id: TASK-023
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: persist settings fetched from /api/settings, enable save workflow, apply saved LLM/site/follow-up defaults in execution paths, replace fake extension service indicators with real last-seen/heartbeat data, and either remove or implement disabled controls (Backup/Import/Test connection).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings page loads persisted settings from an API instead of hardcoded defaults.
- [x] #2 Save button is enabled when settings change and persists LM Studio base URL/model plus default intervals.
- [x] #3 Extraction runner uses persisted LLM settings when invoked from the web server.
- [x] #4 Test connection calls a backend endpoint and displays success/failure with model/server details.
- [x] #5 Chrome extension connection status is based on real data, or fake version/last-ping text is removed.
- [x] #6 Defaults entered in Settings are used by site review creation and follow-up creation flows.
- [x] #7 Disabled Backup DB and Import JSON controls are either implemented as real workflows or removed/deferred from the UI.
- [x] #8 Tests cover settings persistence, LLM test endpoint behavior with a fake client, and default interval usage.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings page now fully functional. All settings load from /api/ui-data (already populated via JH_SETTINGS global). Save button disabled until a field changes — "Unsaved changes" label appears on edit, "Settings saved" appears on success. After save, JH_SETTINGS global is updated in-memory so other components see the new values. Test connection POSTs the current (unsaved) base_url to /api/settings/test-llm rather than only using the DB value. Removed fake "Pairing token" row from Chrome extension section. Fixed AddSiteRequest.interval_days default from 14 to None so the site_review_interval_days DB setting is actually used when creating sites. Added TestLlmRequest model and updated the test-llm endpoint to accept an optional base_url body. Added 3 new tests: test-llm unreachable, test-llm uses provided base_url, and settings interval applied to new sites.
<!-- SECTION:FINAL_SUMMARY:END -->
