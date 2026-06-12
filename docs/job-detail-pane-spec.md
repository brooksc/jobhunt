# Job Detail Pane — Implementation Spec

This document inventories the current Swift job detail pane, documents every gap versus the
original Node.js app, and specifies exactly what to build. Implement in priority order.

---

## Data Models Available

All fields come from the `Job` SwiftData model and its relationships.

### `Job` fields
| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID |
| `jobNumber` | Int? | Sequential display number |
| `company` | String? | |
| `title` | String? | |
| `location` | String? | |
| `remoteType` | RemoteType? | `.remote / .hybrid / .onsite / .unknown` |
| `salaryMin` | Int? | |
| `salaryMax` | Int? | |
| `salaryCurrency` | String? | e.g. "USD" |
| `salaryNote` | String? | e.g. "equity included" |
| `employmentType` | String? | e.g. "Full-time" |
| `seniority` | String? | e.g. "Senior" |
| `status` | JobStatus | new/pursuing/applied/interview/offer/rejected/passed/archived/closed/duplicate/expired |
| `rating` | Int? | 1–5 |
| `applicationURL` | String? | URL for apply page (may differ from source) |
| `manualOverridesJSON` | String | JSON array of skill strings `["Swift","SwiftUI"]` |
| `extractedJSON` | String? | Full LLM extraction output (see below) |
| `extractionStatus` | ExtractionStatus | pending/running/succeeded/failed/skipped |
| `extractionError` | String? | Error message when extraction fails |
| `extractionModel` | String? | LLM model name used |
| `extractionConfidence` | Double? | 0.0–1.0 |
| `extractedAt` | Date? | |
| `fitScore` | Int? | 0–100, overall best score |
| `fitStatus` | FitStatus | none/pending/running/succeeded/failed |
| `fitScoreJSON` | String? | Full fit scoring output (see below) |
| `duplicateOfJobID` | String? | ID of original if this is a duplicate |
| `duplicateConfidence` | Double? | |
| `unread` | Bool | |
| `createdAt` | Date | |
| `updatedAt` | Date | |

### `Job.capture: Capture?`
| Field | Type |
|---|---|
| `url` | String |
| `canonicalURL` | String? |
| `pageTitle` | String |
| `selectedText` | String? |
| `visibleText` | String? |
| `cleanedDescription` | String? |
| `rawHash` | String |
| `cleanedHash` | String? |
| `capturedAt` | Date |

### `Job.events: [JobEvent]`
| Field | Type |
|---|---|
| `eventType` | String — "capture", "note", "status", "applied", "interview", "offer", "rejected" |
| `note` | String? |
| `occurredAt` | Date |

### `Job.actions: [JobAction]`
| Field | Type |
|---|---|
| `note` | String |
| `dueDate` | Date |
| `completedAt` | Date? |
| `snoozedUntil` | Date? |
| `createdAt` | Date |

### `Job.contacts: [Contact]`
| Field | Type |
|---|---|
| `name` | String |
| `role` | String? |
| `email` | String? |
| `linkedinURL` | String? |
| `phone` | String? |
| `notes` | String? |

### `Job.fitScores: [JobFitScore]`
| Field | Type |
|---|---|
| `fitScore` | Int? |
| `fitStatus` | FitStatus |
| `fitScoreJSON` | String? |
| `model` | String? |
| `scoredAt` | Date? |
| `resume` | Resume? |

### `Job.coverLetters: [CoverLetter]`
| Field | Type |
|---|---|
| `content` | String |
| `instructions` | String? |
| `model` | String? |
| `createdAt` | Date |

### `extractedJSON` parsed shape
```json
{
  "summary": "string",
  "requirements": ["string"],
  "nice_to_have": ["string"],
  "benefits": ["string"],
  "application_instructions": "string",
  "skills": ["string"],
  "dimensions": [
    { "name": "required_qualifications", "score": 80, "rationale": "..." }
  ]
}
```

### `fitScoreJSON` parsed shape
```json
{
  "dimensions": [
    { "name": "required_qualifications", "score": 80, "rationale": "..." },
    { "name": "preferred_qualifications", "score": 60, "rationale": "..." },
    { "name": "skills", "score": 75, "rationale": "..." },
    { "name": "experience_level", "score": 70, "rationale": "..." },
    { "name": "domain_fit", "score": 85, "rationale": "..." }
  ],
  "requirements_met": ["string"],
  "requirements_not_met": ["string"]
}
```

### `JobService` methods relevant to detail pane
```swift
setStatus(_ status: JobStatus, for jobID: String)
setRating(_ rating: Int?, for jobID: String)
addNote(_ text: String, to jobID: String)
archive(jobID: String)
delete(jobID: String)
updateJobFields(jobID:company:title:location:remoteType:applicationURL:duplicateOfJobID:)
updateSkills(_ skills: [String], for jobID: String)  // encodes to manualOverridesJSON
resetExtraction(jobID: String)
createAction(jobID: String, text: String, dueAt: Date?)
completeAction(actionID: String)
snoozeAction(actionID: String, until: Date)
createContact(jobID: String, name: String, email: String?, role: String?)
updateContact(contactID: String, name: String, email: String?, role: String?)
deleteContact(contactID: String)
deleteCoverLetter(id: String)
enqueueLLM(jobIDs: [String], mode: LLMRequestType)
```

---

## Current Swift Implementation Inventory

### Header — `JobDetailHeader`

Currently renders:
- `#jobNumber` (caption, only if non-nil)
- `job.title` (headline, "Untitled" fallback)
- `job.company` (subheadline, only if non-nil)
- `StatusChip(job.status)` — badge
- `StarRating(job.rating)` — read-only, only if rating > 0
- External link icon → `job.applicationURL` (only if non-nil)

Missing: location, remote type, salary, source URL badge, employment type, prev/next buttons, re-extract shortcut, archive shortcut.

---

### Tab Bar

Current tabs (in order):  
`Details · Extracted · Fit · Summary · Requirements · Timeline · Raw · (Compare)`

Compare tab conditionally added when `job.duplicateOfJobID != nil`.

Keyboard: `←` prev job, `→` next job, `Esc` deselect.

---

### Details Tab — `DetailsTabView`

**Editable inline fields (tap-to-edit text):**
- Company → `updateJobFields(company:)`
- Title → `updateJobFields(title:)`
- Location → `updateJobFields(location:)`
- Remote → menu Picker → `updateJobFields(remoteType:)`
- Apply URL → `updateJobFields(applicationURL:)`

**Read-only display only (no edit):**
- Employment type (`job.employmentType`)
- Seniority (`job.seniority`)
- Salary (formatted from `salaryMin/Max/Currency/Note`)

**Status section:** menu Picker → `setStatus()`

**Rating section:** 5-star interactive → `setRating()`

**Add Note section:** TextEditor + "Save Note" → `addNote()`

**Actions row:** "Archive" → `archive()` · "Delete" / "Confirm Delete" → `delete()`

**Missing:** Skills section, source URL as distinct link field, application instructions, field provenance/confidence indicators.

---

### Extracted Tab — `ExtractedTabView`

- `ExtractionChip` badge (`job.extractionStatus`)
- Confidence % label (`job.extractionConfidence * 100`)
- "Re-extract" button → `resetExtraction()`
- Key-value table of all `extractedJSON` fields, sorted alphabetically

---

### Fit Tab — `FitTabView`

- Overall fit score large display (`job.fitScore`) — color: green ≥75, orange ≥50, red <50
- "Run Fit Score" button → `queueActor.enqueue(mode: .fit)`
- Dimensions breakdown from `fitScoreJSON["dimensions"]`:
  - Name (humanized), score, progress bar, rationale text
- Per-resume scores list (`job.fitScores` sorted by score desc):
  - Model name + scoredAt — **no resume name shown** (bug: `resume` relationship not used)
  - Score value or fitStatus string

**Missing:** Requirements met/not met split list, resume name (use `fitScore.resume?.name`), "BEST" badge on top scorer, per-resume "Re-score" button, queued/pending indicator per resume.

---

### Summary Tab — `SummaryTabView`

- Renders `extractedJSON["summary"]` as plain text
- **Bug:** summary is truncated to 500 characters with `String.prefix(500)`
- Empty state: "No summary available."

---

### Requirements Tab — `RequirementsTabView`

- Bulleted list from `extractedJSON["requirements"]` as `[String]`
- Empty state: "No requirements extracted."

**Missing:** "Nice to have" list from `extractedJSON["nice_to_have"]`, benefits from `extractedJSON["benefits"]`.

---

### Timeline Tab — `TimelineTabView`

**Top — note entry:**
- TextEditor (70pt) + "Add Note" button → `addNote()`

**Event list** (chronological, oldest→newest):
- Icon (`eventType` → SF Symbol), event type label, timestamp, note body
- Icon mapping: capture→`tray.and.arrow.down`, note→`note.text`, status→`tag`, applied→`paperplane`, interview→`calendar`, offer→`star`, rejected→`xmark.circle`, default→`clock`

**Missing:** Next action section at top (pending `JobAction` with due date + note + "Complete" button), "Set next action" button.

---

### Raw Tab — `RawTabView`

**Capture metadata:**
- URL, Page Title, Canonical URL, Captured At, Raw Hash (first 16 chars)

**Content:** parses `cleanedDescription ?? visibleText` into `JDBlock` array:
- `.heading(text)` → bold caption
- `.paragraph(text)` → caption with line spacing
- `.list([items])` → bulleted list
- `.horizontalRule` → Divider

Falls back to raw text if no blocks parsed.

---

### Compare Tab — `CompareTabView`

Shown only when `job.duplicateOfJobID != nil`. Queries `allJobs: [Job]` via `@Query`.

Comparison table columns: Field | This job | Original  
Rows: Company, Title, Location, Remote, Status, Rating  
Differing fields → `yellow.opacity(0.15)` background highlight.

Actions: "Unmark as Duplicate" → clears `duplicateOfJobID` + sets status `.new` · "View Original" → `router.selectedJobID = original.id`

---

## Gap Analysis — What to Build

### Priority 1 — Header redesign

**Replace** `JobDetailHeader` with a richer layout:

```
[#14]  Principal Technical Program Manager
       Amazon  ·  Seattle, WA  ·  Hybrid  ·  $180k–$250k
       [Saved ▾]  ★★★☆☆  [↗ Source]  [⟳ Re-extract]
```

Spec:
- Row 1: `#jobNumber` (if set) · `title` (headline)
- Row 2: `company` · `location` (if set) · `remoteType.displayName` (if set) · salary formatted (if set)
- Row 3: `StatusChip` (tappable → status picker popover) · `InteractiveStarRating` · "Open Source" button → `job.capture?.url` as URL · "Re-extract" icon button → `jobService.resetExtraction()`
- Source badge: extract domain name from `capture.url` (e.g. "linkedin.com") and show as small chip
- Row/column layout collapses gracefully when fields are nil

Data: `job.title, .company, .location, .remoteType, .salaryMin, .salaryMax, .salaryCurrency, .status, .rating, .applicationURL, .capture?.url, .capture?.pageTitle`

---

### Priority 2 — Description tab (new)

**Add** a "Description" tab between Requirements and Timeline (or after Requirements).  
**Move** the content rendering from Raw tab into this dedicated tab.  
Raw tab keeps only the capture metadata section.

Spec:
- Source: `job.capture?.cleanedDescription ?? job.capture?.visibleText`
- Render using existing `JDBlock` parsing already in `RawTabView`
- Show block types: heading (bold), paragraph, bullet list, horizontal rule
- Full `ScrollView`, text is selectable (`textSelection(.enabled)`)
- Empty state: "No job description captured." with hint to recapture

---

### Priority 3 — Timeline tab: next action

**Add** a next action section at the very top of the Timeline tab, above the note editor.

Spec:
- Query `job.actions` filtered to `completedAt == nil && (snoozedUntil == nil || snoozedUntil <= now)`
- If a pending action exists, show a card:
  ```
  [clock icon]  Follow up with recruiter           [Complete]
  Due: Tomorrow  (or "2d overdue" in red)
  ```
  - "Complete" button → `jobService.completeAction(actionID:)`
  - Due date color: red if overdue, orange if today, secondary if future
- If no pending action, show "+ Set next action" button
- "Set next action" opens a sheet with:
  - Text field: "What to do" (required)
  - Date picker: "Due date" (default: 7 days from now)
  - "Save" / "Cancel" buttons → `jobService.createAction(jobID:text:dueAt:)`

---

### Priority 4 — Details tab: skills & source

**Add skills section** to Details tab, below the core fields group and above Status:

Spec:
- Label: "Skills"
- Source: `job.manualOverridesJSON` decoded as `[String]`, merged/display with `extractedJSON["skills"]` as `[String]`
- Editable: show each skill as a pill with `×` button to remove
- `+` button to add a new skill (text field inline or sheet)
- On any change → `jobService.updateSkills(skills, for: job.id)`
- If no skills extracted and none manual: show "No skills extracted" in tertiary color

**Add source URL field** to the core fields group:
- Label: "Source URL"
- Source: `job.capture?.url`
- Render as a clickable link (truncated to domain + path, full URL on hover)
- Read-only (capture URL can't be edited)
- Position: after "Apply URL" row

**Fix employment type and seniority** — make them editable:
- Employment: free-text field or small menu (Full-time / Part-time / Contract / Internship) → needs `updateJobFields` extension or direct model edit
- Seniority: free-text field → same

---

### Priority 5 — Apply tab (new)

**Add** an "Apply" tab between Details and Extracted.  
Tab only shown when: always (show empty state if no data).

Spec — three sections in a ScrollView:

**Section A — Application Instructions**  
- Source: `extractedJSON["application_instructions"]` as String
- Show as a yellow-tinted info box if non-empty
- Label: "Instructions from posting"
- Empty: hide section entirely

**Section B — Contacts**  
- Source: `job.contacts: [Contact]`
- Each contact shows as a card:
  ```
  [person icon]  Jane Smith  ·  Recruiter
                 jane@company.com  [mailto link]
                 linkedin.com/in/jane  [external link]
                 Phone: 555-1234
                 Notes: Met at job fair
                 [Delete]
  ```
- "+ Add Contact" button expands an inline form:
  - Name (required TextField)
  - Role (TextField, placeholder "Recruiter")
  - Email (TextField, `.emailAddress` keyboard)
  - LinkedIn URL (TextField)
  - Phone (TextField, `.phonePad`)
  - Notes (TextEditor, small)
  - "Add" / "Cancel" buttons → `jobService.createContact()`

**Section C — Cover Letters**  
- Source: `job.coverLetters: [CoverLetter]` sorted by `createdAt` desc
- Each shows: creation date, model name, content in a monospace box, "Copy" button, "Delete" button → `jobService.deleteCoverLetter()`
- Generation: a collapsed/expandable "Generate cover letter" panel
  - Resume selector (if multiple active resumes)
  - Custom instructions TextEditor
  - "Generate" button → `jobService.enqueueLLM(mode: .fit)` (or dedicated cover letter mode if available)
- Empty state: "No cover letters yet."

---

### Priority 6 — Fit tab improvements

**Fix resume name:** `fitScore.resume?.name ?? "Resume"` — currently shows model name only.

**Add requirements met/not met** section below the dimensions breakdown:
- Source: `fitScoreJSON["requirements_met"]` and `["requirements_not_met"]` as `[String]`
- Two-column layout (or stacked):
  - Left/top: green checkmarks for each met requirement
  - Right/bottom: red X marks for each unmet requirement
- Only shown if either list is non-empty

**Add "BEST" badge** on the highest-scoring `JobFitScore` entry.

**Add per-resume "Re-score" button** → `queueActor.enqueue(jobIDs: [job.id], mode: .fit)`.

**Add queued/pending indicator** when `fitStatus == .pending` or `.running`.

---

### Priority 7 — Minor fixes

| Item | Fix |
|---|---|
| Summary tab truncation | Remove `String.prefix(500)` — show full summary |
| Requirements tab | Add "Nice to Have" section from `extractedJSON["nice_to_have"]` |
| Requirements tab | Add "Benefits" pills from `extractedJSON["benefits"]` |
| Raw tab | Remove block content rendering — move to Description tab; Raw shows metadata only |
| Header | Show `ExtractionChip` (extraction status) next to title or in header |
| Timeline events | Add "recapture" event type → `arrow.clockwise` icon |

---

## Tab Order (final)

`Details · Apply · Fit · Description · Requirements · Timeline · Extracted · Raw · (Compare)`

Rationale: most-used tabs first. Details and Apply are everyday workflow. Fit and Description inform evaluation. Requirements/Timeline are reference. Extracted/Raw are diagnostic.

---

## Implementation Notes

- All mutations go through `JobService` — no direct model writes from the view layer.
- `@Environment(\.jobService) private var jobService` is already wired in `JobDetailView`.
- `queueActor` for LLM operations: `@Environment(\.queueActor) private var queueActor`.
- Skills use `jobService.updateSkills(_:for:)` which encodes to `manualOverridesJSON`.
- New `JobAction` operations use `createAction/completeAction/snoozeAction`.
- New `Contact` operations use `createContact/updateContact/deleteContact`.
- The `extractedJSON` and `fitScoreJSON` parsing is already established in the existing tab views — reuse the same pattern.
- `JDBlock` parsing helper is already in the codebase (used by `RawTabView`) — reuse for Description tab.
- `ExtractionChip` and `StatusChip` components already exist.
