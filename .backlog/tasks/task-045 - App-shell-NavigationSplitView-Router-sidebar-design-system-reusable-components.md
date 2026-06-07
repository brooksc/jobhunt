---
id: TASK-045
title: >-
  App shell: NavigationSplitView, Router, sidebar, design system + reusable
  components
status: To Do
assignee: []
created_date: '2026-06-07 22:47'
labels:
  - swift-rewrite
  - ui
  - foundation
milestone: m-1
dependencies:
  - TASK-034
  - TASK-035
documentation:
  - swift-plan.md
  - static/shell.jsx
  - static/app.jsx
  - static/components.jsx
  - static/styles.css
priority: high
ordinal: 2200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Build the SwiftUI application shell and the shared design system every screen depends on — the 3-column layout, navigation/routing, sidebar, theme tokens, and reusable components. This is the UI foundation; build it before/around individual screens.

## Read first
- swift-plan.md §10.1 (shell & navigation), §10.4 (design system replacing styles.css), §10.2 (screen inventory the sidebar links to), §2 (in-process @Query data flow, no SSE).
- Legacy static/shell.jsx (sidebar sections, status quick-filters, saved views, footer status dots, theme toggle, demo banner, topbar/breadcrumb), static/app.jsx (hash routing, deep-link params, localStorage persistence), static/components.jsx (icons + primitives: Chip, StatusChip, ExtractionChip, CoLogo/CompanyCell, Btn, Kbd, toasts), static/styles.css (tokens: indigo #5E6AD2 accent, status palette, spacing 4px scale, radii, shadows, dark/light).

## Implement (app/Shell/ + app/Views/Components/)
- `NavigationSplitView` 3-column scaffold: sidebar | content | detail inspector.
- `Router` (@Observable) holding selected section, selected job/site, active saved view; persisted via `SceneStorage` (replaces hash routing + localStorage). Support deep-link params (jobhunt://jobs/{n}) routing into it (the URL handler itself is in the platform-integration task; expose the routing entry points here).
- Sidebar: sections (Dashboard, Jobs, Data Quality, Needs Action, LLM Queue, Sites, Duplicates) with live counts via @Query; status quick-filters; saved-views section (pinned + custom + save/delete); footer status dots (local service / extension last-seen / LLM configured) + theme toggle; demo banner when in demo mode.
- `Theme` (@Observable) design tokens; Light/Dark/Auto via preferredColorScheme. Status→(SF Symbol,color) mapping.
- Reusable components: StatusChip, ExtractionChip, Chip, CompanyCell/CoLogo (monogram/favicon), StarRating, Btn variants, Kbd, a toast/inline-status system, popover filter control. Replace the 30 inline SVG icons with SF Symbols.
- Content area routes to a placeholder per section (real screens are separate tasks); detail inspector is a slot the Jobs/Sites tasks fill.

## Dependencies
Depends on task-034 (models for @Query counts) and task-035 (SettingsStore/theme). Foundation for ALL screen tasks (Jobs, Detail, Dashboard, Quality, Needs, Sites, Duplicates, LLM Queue, Settings, Help, Onboarding).

## Tests (AppUITests + snapshot)
- XCUITest: app launches, sidebar shows all sections, navigation switches content. Snapshot tests (swift-snapshot-testing) for the component library in light + dark.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3-column NavigationSplitView shell with Router persisted via SceneStorage
- [ ] #2 Sidebar reproduces sections, live counts, status quick-filters, saved-views (pinned+custom), footer status dots, theme toggle, demo banner
- [ ] #3 Theme tokens reproduce styles.css palette (indigo accent, status colors) with Light/Dark/Auto
- [ ] #4 Reusable components implemented (StatusChip/ExtractionChip/CompanyCell/StarRating/Btn/Kbd/toasts/filter popover) using SF Symbols
- [ ] #5 Deep-link routing entry points exposed for jobhunt://jobs/{n}
- [ ] #6 XCUITest launch+nav passes; snapshot tests for components in light+dark
<!-- AC:END -->
