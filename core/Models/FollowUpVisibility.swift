import Foundation

/// Single definition of an "actionable" follow-up — not completed, not snoozed into the future, and
/// linked to a job — shared by the Needs Action screen + sidebar badge, the Dashboard follow-ups
/// section, the job-detail pending indicator, and export, so those counts can't drift (TASK-576).
public enum FollowUpVisibility {
    /// Pure form (Sendable scalars) for unit tests and off-actor use. `jobIsTerminal` excludes
    /// follow-ups on jobs that are no longer an active pursuit (archived/closed/etc., TASK-577) — they
    /// reappear automatically if the job leaves the terminal status (no mutation, so undo is free).
    public static func isActionable(
        completedAt: Date?, snoozedUntil: Date?, hasJob: Bool, jobIsTerminal: Bool = false, now: Date
    ) -> Bool {
        guard completedAt == nil else { return false } // done → not actionable
        if let snoozedUntil, snoozedUntil > now { return false } // snoozed into the future → hidden
        return hasJob && !jobIsTerminal // orphaned or terminal-job actions are excluded everywhere
    }

    /// Convenience for a live `JobAction`. Call on the actor that owns the model (it reads `job`).
    public static func isActionable(_ action: JobAction, now: Date = Date()) -> Bool {
        isActionable(
            completedAt: action.completedAt,
            snoozedUntil: action.snoozedUntil,
            hasJob: action.job != nil,
            jobIsTerminal: action.job?.status.isTerminal ?? false,
            now: now
        )
    }
}
