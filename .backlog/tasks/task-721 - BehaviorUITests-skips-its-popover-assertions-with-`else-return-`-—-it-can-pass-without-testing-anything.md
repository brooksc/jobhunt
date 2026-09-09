---
id: TASK-721
title: >-
  BehaviorUITests skips its popover assertions with `else { return }` — it can
  pass without testing anything
status: To Do
assignee: []
created_date: '2026-09-09 02:28'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while investigating [[TASK-720]]. `BehaviorUITests.testJobsFilterRemoteChip` (around `BehaviorUITests.swift:157-195`) opens the Advanced-filters popover and then guards **every** assertion behind an early return:

```swift
guard remoteChip.waitForExistence(timeout: 6) else {
    // NSPopover content not accessible on this headless VM — skip remaining assertions.
    return
}
…
guard remoteChip.exists else { return } // Popover closed — skip remaining assertions
```

There are four such guards. If the popover never opens, or opens and closes, the test **returns and reports success** — having asserted nothing about the thing it is named for.

This matters right now: `SavedSearchUITests.testSelectingSavedSearchAfterSessionFilterStaysActive` fails on CI with `popovers=0`, i.e. the popover does not open on that runner at all. `BehaviorUITests` opens the *same* popover on the *same* runner and passes. Those two facts are only compatible if BehaviorUITests is taking one of its early returns — so its green is very likely hollow, and has been for as long as the guards have existed.

The workaround was reasonable when written (headless NSPopover accessibility is genuinely flaky, and the comments say so honestly). The problem is that it is indistinguishable, in the results, from a test that ran.

## What to do

Make the skip **visible**, not silent. `XCTSkip` is the right tool: it reports as skipped rather than passed, so the suite stops claiming coverage it does not have.

```swift
try XCTSkipUnless(remoteChip.waitForExistence(timeout: 6),
                  "NSPopover content not accessible in this environment")
```

Then decide, with the TASK-720 evidence, whether the popover is testable on CI at all. If it is, the guards should become assertions. If it is not, the skip should be explicit and conditional on the environment rather than on the symptom.

Same family as [[TASK-716]], [[TASK-717]], [[TASK-718]] and [[TASK-719]]: a green result that is not evidence. This one is the most direct instance — the test literally returns early and passes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No assertion in the popover test is reachable only via a silent early return
- [ ] #2 An environment that cannot show the popover reports as skipped, not passed
- [ ] #3 It is recorded whether the Advanced-filters popover is testable on the CI runner at all, with evidence from TASK-720
- [ ] #4 The suite's pass count no longer includes tests that asserted nothing
<!-- AC:END -->
