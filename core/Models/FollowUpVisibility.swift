import Foundation

/// Single definition of an "actionable" follow-up — not completed, not snoozed into the future, and
/// linked to a job — shared by the Needs Action screen + sidebar badge, the Dashboard follow-ups
/// section, the job-detail pending indicator, and export, so those counts can't drift (TASK-576).
public enum FollowUpVisibility {
    /// Pure form (Sendable scalars) for unit tests and off-actor use.
    public static func isActionable(completedAt: Date?, snoozedUntil: Date?, hasJob: Bool, now: Date) -> Bool {
        guard completedAt == nil else { return false } // done → not actionable
        if let snoozedUntil, snoozedUntil > now { return false } // snoozed into the future → hidden
        return hasJob // orphaned actions (no linked job) are excluded everywhere
    }

    /// Convenience for a live `JobAction`. Call on the actor that owns the model (it reads `job`).
    public static func isActionable(_ action: JobAction, now: Date = Date()) -> Bool {
        isActionable(
            completedAt: action.completedAt,
            snoozedUntil: action.snoozedUntil,
            hasJob: action.job != nil,
            now: now
        )
    }
}
