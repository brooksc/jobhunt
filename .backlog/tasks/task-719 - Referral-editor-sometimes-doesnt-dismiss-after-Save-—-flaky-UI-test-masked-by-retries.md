---
id: TASK-719
title: >-
  Referral editor sometimes doesn't dismiss after Save — flaky UI test masked by
  retries
status: To Do
assignee: []
created_date: '2026-09-05 17:23'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the 2026-09-05 VM run of AppUITests against merged `main` (commit f8d4f719).

`ReferralUITests.testReferralEditor_repeatedOpenTypeDateSave_staysResponsiveAndDoesNotCrash` **failed 2 of its 3 attempts**, then passed on the third, so `xcodebuild` exited 0 and the suite reported success. The class has exactly one test method; "Executed 3 tests, with 2 failures" is three attempts under `-retry-tests-on-failure -test-iterations 3`.

Both failures were the same assertion (`ReferralUITests.swift:72`), on different internal iterations of the test's own loop:

```
iter 1: editor didn't dismiss after Save
iter 5: editor didn't dismiss after Save
```

```swift
save.click()
XCTAssertTrue(
    waitForDisappearance(recipient, timeout: 5),
    "iter \(iteration): editor didn't dismiss after Save"
)
```

## Why this is worth chasing rather than dismissing as VM slowness

The test exists precisely to prove the referral editor **stays responsive under repeated open → type → date → save**. An intermittent failure to dismiss within 5 seconds is the symptom that test was written to detect. Calling it flaky and moving on assumes the answer.

Two candidate causes, and they need distinguishing:

1. **A real race in the app** — the save path and the dismissal are not ordered, so the sheet occasionally stays up after a successful save. That would be user-visible: click Save, nothing happens, click again.
2. **Test timing under VM load** — 5 seconds is not generous on a virtualised host running a cold build.

Distinguish by raising only the timeout and re-running: if it goes green at 15s it is timing; if it still fails intermittently the ordering is wrong. Do **not** just raise the timeout and close this — that converts a possible product bug into a permanently green test.

## Related

The run also showed that a retry-masked failure was indistinguishable from a clean run, because the script printed a bare "✓ All tests passed". `run-ui-tests-in-vm.sh` now names the tests that needed a retry. Without that, this would not have been noticed at all.

Same family as [[TASK-716]], [[TASK-717]] and [[TASK-718]]: a green result that is not evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 It is established whether the dismissal failure is an app race or test timing, with the evidence stated
- [ ] #2 If it is an app race, the save-then-dismiss ordering is fixed and the test passes on the first attempt
- [ ] #3 If it is timing, the timeout is raised with a comment saying why, and the test still fails if dismissal genuinely breaks
- [ ] #4 The test passes 3 consecutive VM runs without needing a retry
<!-- AC:END -->
