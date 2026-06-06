---
id: TASK-023.14
title: 'M4: Surface extraction provenance application URL and confidence correctly'
status: Done
assignee: []
created_date: '2026-05-27 18:11'
updated_date: '2026-06-01 04:08'
labels:
  - m4
  - web
  - ui-audit
  - extraction
dependencies: []
modified_files:
  - src/jobhunt/extract.py
  - src/jobhunt/db.py
  - src/jobhunt/api.py
  - src/jobhunt/export.py
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/detail.jsx
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Most extraction provenance is implemented in the Node app: successful extraction model, application URL, and confidence are persisted, surfaced through /api/ui-data, shown in job detail, and application/model data is included in CSV export. Remaining work is to add focused tests for provenance serialization and ensure failed-attempt provenance is always available outside debug logs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Successful and failed extraction attempts record the model/provider or enough provenance to explain what ran.
- [x] #2 Detail panel `Model` field displays real extraction provenance or is removed until available.
- [x] #3 Extracted `application_url` is exposed to the UI and displayed when it differs from the captured source URL.
- [x] #4 Extraction confidence values are exposed and shown in a diagnostic/metadata area, or intentionally hidden with a code comment/task rationale.
- [x] #5 CSV export includes provenance/application URL if considered part of tracked job data, or explicitly excludes it by product decision.
- [ ] #6 Tests cover persistence and API serialization of extraction provenance and application URL/confidence metadata.
- [ ] #7 6
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added Node/JS provenance coverage for persistence, /api/ui-data serialization, and failed-attempt provenance via /api/llm-queue/:requestId/attempts. Verified model, application_url, extraction_confidence, extracted_json confidence, base URL, requested/returned model, response_format, prompt/response sizes, and failure error are exposed.
<!-- SECTION:NOTES:END -->
