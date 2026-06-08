---
id: TASK-033
title: >-
  Swift project scaffold: Tuist project, targets, dual-flavor build,
  entitlements, CI skeleton
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:43'
updated_date: '2026-06-08 01:40'
labels:
  - swift-rewrite
  - foundation
  - build
milestone: m-1
dependencies: []
documentation:
  - swift-plan.md
  - build/entitlements.mas.plist
  - build/entitlements.dmg.plist
  - package.json
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Stand up the empty native Swift project that every other rewrite task builds on. After this task the repo produces two buildable app flavors (DMG + MAS) from one codebase, plus the Core/Server/MCP library/executable targets.

THIS IS THE ROOT TASK — most other Native Swift Rewrite tasks depend on it.

## Read first (load into context before starting)
- swift-plan.md §3 (tech stack), §5 (project structure & build tooling), §2 (layering/targets), §13.1–13.2 (dual flavors + entitlements), §0 (decisions: macOS 15 min, SwiftData, Swift 6 strict concurrency).
- Existing build/entitlements.dmg.plist, build/entitlements.mas.plist (port the entitlement intent; drop the Electron-only JIT/library-validation entries for DMG per §13.2).
- package.json `build` block (appId com.jobhunt-app.jobhunt, productName Jobhunt, category public.app-category.productivity) — reuse identifiers.

## Implement
- Add Tuist (Tuist/ config + Project.swift) generating Jobhunt.xcodeproj. Do NOT commit the generated .xcodeproj (gitignore it); commit the manifest.
- Targets per §2/§5.1: `JobhuntCore` (framework/library, no SwiftUI/AppKit), `JobhuntServer` (library, depends Core), `JobhuntMCP` (executable, depends Core), `Jobhunt` (app, depends all). Plus matching test targets: CoreTests, ServerTests, MCPTests, AppUITests.
- Deployment target macOS 15.0. Swift 6, `-strict-concurrency=complete`.
- Two app schemes / configurations: `Jobhunt-DMG` and `Jobhunt-MAS`, distinguished by a `MAS_BUILD` Swift active-compilation-condition on the MAS config. JobhuntMCP excluded from the MAS app embed.
- Bundle id com.jobhunt-app.jobhunt; set MARKETING_VERSION/CURRENT_PROJECT_VERSION build settings.
- Entitlements files build/Jobhunt-DMG.entitlements (hardened runtime, no sandbox) and build/Jobhunt-MAS.entitlements (app-sandbox, network.server, network.client, files.user-selected.read-only) per §13.2. Wire each to its config.
- Register the `jobhunt://` URL scheme in the app Info.plist (CFBundleURLTypes).
- Add swiftlint + swiftformat configs (mirror current ESLint gate intent).
- CI skeleton: a GitHub Actions workflow (build-only) that runs `tuist generate` + `xcodebuild build` for both schemes on macos-latest. (Full release/signing workflow is a later task — AE/AF.)
- App entry point: minimal SwiftUI `JobhuntApp` showing an empty NavigationSplitView placeholder so both flavors launch.

## Notes for downstream tasks
Other tasks will add sources into core/, server/swift/, mcp/swift/, app/ as laid out in §5.1. Keep the target source globs broad enough that new files are picked up without manifest edits where possible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `tuist generate` succeeds and produces Jobhunt.xcodeproj (gitignored)
- [x] #2 `xcodebuild -scheme Jobhunt-DMG build` succeeds; app launches showing an empty NavigationSplitView
- [x] #3 `xcodebuild -scheme Jobhunt-MAS build` succeeds with App Sandbox entitlements applied (verify with codesign -d --entitlements)
- [x] #4 JobhuntCore, JobhuntServer, JobhuntMCP targets exist and build; MAS_BUILD condition compiles MCP out of the MAS app
- [x] #5 Both entitlement plists pass `plutil -lint`; jobhunt:// scheme present in Info.plist
- [x] #6 CI workflow builds both schemes on macos-latest
- [x] #7 swiftlint/swiftformat run clean in CI
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Install swiftlint + swiftformat via brew
2. Scaffold directories: Tuist/, app/, core/, server/swift/, mcp/swift/, Tests/{CoreTests,ServerTests,MCPTests,AppUITests}/
3. Write Project.swift (Tuist manifest): 4 targets (JobhuntCore framework, JobhuntServer framework, JobhuntMCP executable, Jobhunt app) + 4 test targets + 2 schemes (Jobhunt-DMG / Jobhunt-MAS with MAS_BUILD flag)
4. Write Tuist/Config.swift and Tuist/Package.swift (SPM deps placeholder)
5. Write entitlement files: build/Jobhunt-DMG.entitlements (hardened runtime, no JIT/library-validation), build/Jobhunt-MAS.entitlements (sandbox + network.server + network.client)
6. Write minimal app entry: app/JobhuntApp.swift + app/ContentView.swift (empty NavigationSplitView)
7. Write stub source files for JobhuntCore, JobhuntServer, JobhuntMCP so targets compile
8. Write .swiftlint.yml and .swiftformat configs
9. Write .github/workflows/swift-build.yml CI skeleton
10. Update .gitignore to exclude *.xcodeproj, DerivedData, Tuist/.build
11. Run: tuist generate && xcodebuild -scheme Jobhunt-DMG build && xcodebuild -scheme Jobhunt-MAS build
12. Verify: plutil -lint on entitlements, codesign -d --entitlements on MAS product
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Scaffolded the full Tuist-based Swift project for Jobhunt. Tuist 4.196.1 installed. Project.swift defines 4 targets (JobhuntCore framework, JobhuntServer framework, JobhuntMCP commandLineTool, Jobhunt app) + 4 test targets + 2 schemes (Jobhunt-DMG / Jobhunt-MAS). Four project-level configurations (Debug/Release × DMG/MAS) with MAS_BUILD active compilation condition on the MAS configs. Both schemes build successfully (BUILD SUCCEEDED). Entitlements wired: DMG gets hardened runtime + network.server/client; MAS gets app-sandbox + network.server/client + files.user-selected.read-only. jobhunt:// URL scheme registered in Info.plist. swiftlint 0.63.3 + swiftformat 0.61.1 both pass clean. CI workflow at .github/workflows/swift-build.yml runs tuist generate + both scheme builds + CoreTests + lint on push. Xcodeproj gitignored. Minor: moved Tuist/Config.swift → Tuist.swift per Tuist 4.x convention (eliminates deprecation warning). Disabled sorted_imports in swiftlint (swiftformat owns import ordering via testable-bottom grouping)."
<!-- SECTION:FINAL_SUMMARY:END -->
