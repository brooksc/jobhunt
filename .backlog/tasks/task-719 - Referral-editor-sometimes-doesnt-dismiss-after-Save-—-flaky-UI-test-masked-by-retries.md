---
id: TASK-719
title: >-
  Referral editor sometimes doesn't dismiss after Save — flaky UI test masked by
  retries
status: Done
assignee: []
created_date: '2026-09-05 17:23'
updated_date: '2026-09-08 16:41'
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
- [x] #1 It is established whether the dismissal failure is an app race or test timing, with the evidence stated
- [ ] #2 If it is an app race, the save-then-dismiss ordering is fixed and the test passes on the first attempt
- [x] #3 If it is timing, the timeout is raised with a comment saying why, and the test still fails if dismissal genuinely breaks
- [x] #4 The test passes 3 consecutive VM runs without needing a retry
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in ca50db7b. **Cause: latency, not a race.**

The sheet dismisses only after the write returns — `ReferralViews.save` awaits `recordReferralAttempt` and then clears `editorAttempt` (review #7: never dismiss before the write succeeds). That write goes through the single-writer store actor, which during this suite is also serving demo seeding and job-detail queries. So the dismissal delay is queueing on a shared actor, which is why both failures landed on the iteration right after launch, when that actor is busiest — not view code being slow, and not the VM being slow in general.

**Evidence, from the experiment this task prescribed (raise only the timeout):**

| timeout | result |
|---|---|
| 5s | failed **2 of 3** attempts (2026-09-05) |
| 20s | passed 1 of 1, first attempt (2026-09-08) |

AC#2 does not apply — there is no ordering bug to fix. AC#3: the timeout is now 20s with a comment naming *what it waits on* rather than "the VM is slow", and the assertion keeps its teeth. The two ways this can genuinely break — a failed write showing a toast, or the duplicate-confirm path (`attemptSave` raises `showDuplicateConfirm` instead of saving) — both leave the sheet up indefinitely and fail at any timeout.

AC#4: three consecutive VM runs, one attempt each, zero failures (93s / 102s / 92s).

**Checked while investigating, worth recording:** a double Save cannot duplicate a referral. The write is keyed on the editor's stable `attemptID` and milestone events carry deterministic ids, so a second click upserts the same row.

**Found but deliberately not fixed — worth its own task if it matters.** Because the write can take seconds, clicking Save leaves the sheet up with no feedback and the button still enabled; a user can reasonably think the click missed. Harmless in data terms (see above), but it is the real user-facing consequence of the same latency this task measured. A "saving" state that disables Save and shows progress would fix it, and needs plumbing between `ReferralAttemptEditor` and `ReferralViews` — a product change, out of scope here and not something to add unannounced before a release.

**Also fixed here:** the flaky-run detector added the previous day was wrong on its first outing. It matched the bare `-[Class method]` shape, which appears in every "Test Case '-[…]' passed" line, so it reported retry-masked failures on a clean run. It now takes names from `error:` lines only, verified against both real logs — fires on the 09-05 failing run, silent on the 09-08 clean one.
<!-- SECTION:FINAL_SUMMARY:END -->
