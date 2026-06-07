---
id: TASK-057
title: Help screen + About
status: To Do
assignee: []
created_date: '2026-06-07 22:50'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
documentation:
  - swift-plan.md
  - static/screens/help.jsx
priority: low
ordinal: 3400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Help/documentation screen.

## Read first
- swift-plan.md §10.2 #10 (Help sections), §3 (AttributedString markdown / swift-markdown).
- Legacy static/screens/help.jsx (509 lines) — getting started, how-to, extraction & scoring, sites & availability, duplicates, troubleshooting, settings reference, keyboard shortcuts, About (version/local-data/privacy).

## Implement (app/Views/Help/)
- Sectioned scrollable reference rendered from Markdown (AttributedString(markdown:) or swift-markdown), keyboard-shortcuts table, About panel showing app version (from bundle) + local-data note + privacy statement. Static content; no service deps.

## Dependencies
Depends on task-045 (shell/components).

## Tests (AppUITests)
- Help renders all sections; About shows the correct version; keyboard-shortcuts table present.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All Help sections rendered from Markdown
- [ ] #2 Keyboard-shortcuts table present
- [ ] #3 About shows bundle version + local-data + privacy note
- [ ] #4 XCUITest verifies sections + version render
<!-- AC:END -->
