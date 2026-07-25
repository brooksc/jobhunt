import Foundation
import JobhuntCore
import SwiftData

// MARK: - Repair: create missing JobFitScore records

func repairFitScores(context: ModelContext) -> Int {
    let jobs: [Job]
    do {
        jobs = try context.fetch(FetchDescriptor<Job>())
    } catch {
        fputs("Error fetching jobs: \(error)\n", stderr)
        return 0
    }

    var inserted = 0
    for job in jobs {
        guard job.fitStatus == .succeeded,
              let json = job.fitScoreJSON,
              job.fitScores.isEmpty else { continue }
        let record = JobFitScore(
            fitScore: job.fitScore,
            fitStatus: .succeeded,
            fitScoreJSON: json,
            model: nil,
            scoredAt: job.updatedAt
        )
        context.insert(record)
        record.job = job
        inserted += 1
        let label = job.jobNumber.map { "#\($0)" } ?? job.id
        print("  \(label): score \(job.fitScore.map(String.init) ?? "?") → JobFitScore created")
    }

    do {
        try context.save()
    } catch {
        fputs("Error saving: \(error)\n", stderr)
        return 0
    }
    return inserted
}

// MARK: - Patch Fit Scores: replace resume-less stubs with proper per-resume records

func patchFitScores(src: DBHandle, context: ModelContext) {
    guard tableExists(src, "job_fit_scores") else {
        print("No job_fit_scores table in SQLite — nothing to do.")
        return
    }

    let allJobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
    let allResumes = (try? context.fetch(FetchDescriptor<Resume>())) ?? []
    let jobMap = Dictionary(uniqueKeysWithValues: allJobs.map { ($0.id, $0) })
    let resumeMap = Dictionary(uniqueKeysWithValues: allResumes.map { ($0.id, $0) })

    // Delete all stubs (JobFitScore records with no resume link).
    // App-scored records always have a resume; stubs from repair never do.
    let allScores = (try? context.fetch(FetchDescriptor<JobFitScore>())) ?? []
    let stubs = allScores.filter { $0.resume == nil }
    print("Deleting \(stubs.count) resume-less stub record(s)…")
    for stub in stubs {
        context.delete(stub)
    }
    do { try context.save() } catch {
        fputs("Error deleting stubs: \(error)\n", stderr); return
    }

    // Import succeeded per-resume scores from SQLite
    var inserted = 0
    var skipped = 0
    let rows = queryRows(src, "SELECT * FROM job_fit_scores WHERE fit_status = 'succeeded'")
    for row in rows {
        guard let jobId = row.str("job_id") else { skipped += 1; continue }
        guard let job = jobMap[jobId] else { skipped += 1; continue }

        let resumeId = row.str("resume_id")
        let resume = resumeId.flatMap { resumeMap[$0] }

        // Skip if an identical (job, resume) pair is already present (app may have rescored)
        let alreadyPresent = job.fitScores.contains { $0.resume?.id == resumeId }
        if alreadyPresent { skipped += 1; continue }

        let rec = JobFitScore(
            fitScore: row.int("fit_score"),
            fitStatus: row.str("fit_status").flatMap { FitStatus(rawValue: $0) } ?? .none,
            fitScoreJSON: row.str("fit_score_json"),
            model: row.str("model"),
            scoredAt: row.date("scored_at"),
            createdAt: row.dateOrNow("created_at"),
            updatedAt: row.dateOrNow("updated_at")
        )
        context.insert(rec)
        rec.job = job
        rec.resume = resume
        inserted += 1

        let resumeName = resume?.name ?? resumeId ?? "?"
        let jobLabel = job.jobNumber.map { "#\($0)" } ?? jobId
        print("  \(jobLabel): \(resumeName) → score \(row.str("fit_score") ?? "?")")
    }

    do {
        try context.save()
        print("\nPhase 1 done: \(inserted) record(s) inserted, \(skipped) skipped.")
    } catch {
        fputs("Error saving fit scores: \(error)\n", stderr); return
    }

    // Phase 2: create stubs for jobs that have a succeeded fit score on the Job model
    // but no JobFitScore record (their scores were never in job_fit_scores table).
    let updatedJobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
    var stubs2 = 0
    for job in updatedJobs {
        guard job.fitStatus == .succeeded,
              let json = job.fitScoreJSON,
              job.fitScores.isEmpty else { continue }
        let stub = JobFitScore(
            fitScore: job.fitScore,
            fitStatus: .succeeded,
            fitScoreJSON: json,
            model: job.extractionModel,
            scoredAt: job.updatedAt
        )
        context.insert(stub)
        stub.job = job
        stubs2 += 1
        let label = job.jobNumber.map { "#\($0)" } ?? job.id
        print("  \(label): stub created (no per-resume data available)")
    }
    if stubs2 > 0 {
        do {
            try context.save()
            print("Phase 2 done: \(stubs2) stub(s) created for jobs with no per-resume data.")
        } catch {
            fputs("Error saving stubs: \(error)\n", stderr)
        }
    } else {
        print("Phase 2: no stubs needed.")
    }
}
