---
id: TASK-596
title: 'jobs: "Open in app" for a job outside the active sidebar filter now reveals it'
status: Done
assignee: []
created_date: '2026-07-05 18:42'
labels:
  - jobs
  - navigation
dependencies: []
modified_files:
  - app/Shell/Router.swift
  - app/Platform/PlatformIntegration.swift
  - app/Views/Queue/LLMQueueView.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Saving a job from the Chrome extension and clicking "Open in app" added it as `new` but left the Jobs view on the user's active sidebar smart-folder filter (e.g. `Interested`). Because `computeFilteredJobs()` drops any job whose status != the sidebar filter, the newly-captured `new` job was filtered out — invisible and unscrollable, so the app appeared to do nothing.

Root cause: `Router.selectJob(id:)` switched to the Jobs section and set the selection + pending scroll id, but never reconciled the active sidebar filter with the target job's status. Both external-navigation entry points (`PlatformIntegration.navigateToJob` for the `jobhunt://jobs/N` deep-link and the `/api/app/focus` HTTP endpoint, plus the LLM Queue "Open Job" menu) hit this.

Fix: `selectJob(id:jobStatus:)` now takes the target job's status; when an active sidebar filter would hide the job (non-nil and != the job's status), it switches the filter to the job's status so the view focuses on the folder actually containing the job (e.g. `New`). An `All` view (nil filter) or a filter already matching the job is left untouched, so a normal in-context open never narrows the view.

Known limitation: the toolbar advanced filter (`JobsFilterState` status chips / remote / fit) and free-text search are JobsView-local @State and are not reconciled here — if those are set to exclude the job it can still be hidden. Only the reported sidebar smart-folder case is addressed (setting the sidebar filter does clear search tokens via the existing onChange).</description>
<parameter name="acceptanceCriteria">["Opening a job via extension \"Open in app\" / jobhunt:// deep-link / focus endpoint while the Jobs sidebar is filtered to a different status switches the sidebar to the job's status and selects+scrolls to it", "An 'All' (nil) sidebar filter, or a sidebar filter already matching the job's status, is left unchanged (no unexpected narrowing)", "LLM Queue 'Open Job' behaves the same way", "App builds; SwiftLint/SwiftFormat clean"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
selectJob now accepts the target job's status and, when the active sidebar smart-folder filter would hide the job, switches the filter to the job's status so external navigation actually reveals the job. Wired through PlatformIntegration.navigateToJob (deep-link + focus endpoint) and the LLM Queue 'Open Job' menu (helper refactored to return the Job). App builds; lint/format clean. Toolbar advanced-filter/search hiding left as a documented limitation.
<!-- SECTION:FINAL_SUMMARY:END -->
