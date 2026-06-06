---
id: TASK-023.16
title: 'M4: Improve keyboard accessibility and ARIA for interactive table UI'
status: Done
assignee: []
created_date: '2026-05-27 18:11'
updated_date: '2026-05-31 23:38'
labels:
  - m4
  - web
  - ui-audit
  - accessibility
dependencies: []
modified_files:
  - src/jobhunt/static/components.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/screens/duplicates.jsx
  - src/jobhunt/static/screens/needs.jsx
  - src/jobhunt/static/screens/sites.jsx
  - src/jobhunt/static/styles.css
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Accessibility is partially implemented in the Node app: many icon buttons have labels, detail tabs support keyboard navigation, modals trap focus and close on Escape, and select-all uses the real indeterminate property in key tables. Remaining work is a full keyboard-only verification pass, focus-return polish for popovers, and duplicate/filter accessibility fixes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clickable rows or card rows are keyboard reachable and activatable, or contain explicit buttons/links for their actions.
- [x] #2 Icon-only buttons have accessible labels beyond visual icons/title where needed.
- [x] #3 Filter/status/dropdown popovers support Escape to close and return focus to the trigger.
- [x] #4 Detail tablist supports arrow-key navigation or is simplified to standard buttons without misleading ARIA roles.
- [x] #5 Modal dialogs trap focus while open and restore focus after close.
- [x] #6 Select-all checkbox uses the real indeterminate property for partial selection.
- [x] #7 Manual keyboard-only verification covers Jobs table, detail panel, filters, modal, and duplicate actions.
<!-- AC:END -->

## Verification Notes

<!-- SECTION:NOTES:BEGIN -->
- `tests/ui/jobs-smoke.test.js` covers keyboard activation for Jobs table rows, Escape focus return for the Jobs filter popover, app dialog error feedback, and keyboard activation for duplicate Compare/Back actions.
- Existing native buttons, links, radio inputs, selects, and app modal focus trapping cover the remaining detail panel/modal interactions.
<!-- SECTION:NOTES:END -->
