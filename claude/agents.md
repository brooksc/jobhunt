# Agent Guidelines

## macOS notification criteria

Use notifications for workflow-level events that matter when Jobhunt is running in the background. Keep them sparse and actionable.

Trigger a notification when:

- A new, non-duplicate job capture creates a job record.
- AI queue processing completes after at least one queued item was processed.
- The AI queue auto-pauses after repeated failures.

Do not trigger a notification when:

- A capture is a duplicate or a recapture of an existing job.
- A job is merely queued for AI processing.
- Individual AI items start, finish, retry, or update row state.
- The user edits fields, ratings, statuses, notes, or duplicate decisions.
- Polling or availability checks run without a user-visible state change that needs attention.

Notification behavior:

- Prefer one summary notification per completed workflow over per-row notifications.
- Suppress non-critical notifications while the app window is focused.
- Include counts for batch work, especially succeeded and failed AI item counts.
- Treat queue auto-pause as critical because it requires user action.
