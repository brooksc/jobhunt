// swiftlint:disable line_length function_body_length large_tuple
import Foundation
import SwiftData

// MARK: - ModelContainerFactory demo extension

public extension ModelContainerFactory {
    /// In-memory container pre-seeded with demo data — isolated from the user store.
    static func demo() async throws -> ModelContainer {
        let container = try inMemory()
        let store = BackgroundStore(modelContainer: container)
        try await DemoSeeder.seedDemo(into: store)
        return container
    }
}

// MARK: - DemoSeeder

/// Seeds a representative dataset into a SwiftData container for demo mode.
/// Ported from server/demo.js `seedDemoDb` / `reseedDemoDb`.
public enum DemoSeeder {
    // MARK: - Public API

    /// Insert ~15 sample jobs, 3 sites, 2 resumes, and assorted events into the given store.
    /// Safe to call on an empty container; silently skips seed if jobs already exist.
    public static func seedDemo(into store: BackgroundStore) async throws {
        try await store.seedIfEmpty()
    }

    /// Delete all demo data and re-seed from scratch.
    public static func reseedDemo(into store: BackgroundStore) async throws {
        try await store.deleteAll()
        try await store.seedIfEmpty()
    }
}

// MARK: - BackgroundStore seeding helpers

extension BackgroundStore {
    // MARK: Internal helpers

    func seedIfEmpty() throws {
        let existingJobs = try fetch(FetchDescriptor<Job>())
        guard existingJobs.isEmpty else { return }
        try performSeed()
    }

    func deleteAll() throws {
        try deleteAll(LLMRequestAttempt.self)
        try deleteAll(LLMRequest.self)
        try deleteAll(DataQualityReview.self)
        try deleteAll(JobEvent.self)
        try deleteAll(JobAction.self)
        try deleteAll(DuplicateDecision.self)
        try deleteAll(JobFitScore.self)
        try deleteAll(Job.self)
        try deleteAll(Capture.self)
        try deleteAll(Site.self)
        try deleteAll(Resume.self)
        try deleteAll(Setting.self)
    }

    // MARK: Seed execution

    private func performSeed() throws {
        let now = Date()
        func daysAgo(_ numDays: Double) -> Date {
            Date(timeIntervalSinceNow: -numDays * 86400)
        }

        // MARK: Resumes

        let resume1 = Resume(
            id: "resume_001",
            name: "TPM Resume — Full",
            filename: "tpm_resume.pdf",
            text: """
            Senior Technical Program Manager with 10+ years driving cross-functional programs for \
            distributed systems, cloud platforms, and AI/ML products. Expertise in OKRs, risk \
            management, and executive stakeholder communication. AWS certified. PMP certified.
            """,
            charCount: 280,
            active: true,
            sortOrder: 0,
            createdAt: daysAgo(60),
            updatedAt: daysAgo(60)
        )

        let resume2 = Resume(
            id: "resume_002",
            name: "TPM Resume — Condensed",
            filename: "tpm_resume_short.pdf",
            text: """
            Technical Program Manager with strong background in infrastructure and platform programs. \
            10 years TPM experience. Led programs at FAANG scale. Remote-friendly.
            """,
            charCount: 175,
            active: false,
            sortOrder: 1,
            createdAt: daysAgo(30),
            updatedAt: daysAgo(30)
        )

        // MARK: Jobs + Captures + Events

        struct SeedJob {
            let capId: String
            let jobId: String
            let jobNum: Int
            let url: String
            let pageTitle: String
            let company: String?
            let title: String?
            let location: String?
            let remoteType: RemoteType?
            let salaryMin: Int?
            let salaryMax: Int?
            let salaryCurrency: String
            let employmentType: String?
            let seniority: String?
            let status: JobStatus
            let summary: String?
            let requirements: String?
            let skills: [String]
            let capturedAt: Date
            let extractedAt: Date?
            let extractionStatus: ExtractionStatus
            let fitScore: Int?
            let fitStatus: FitStatus
            let note: String?
            let duplicateOfJobID: String?
            // Optional shared cleaned-hash so a pair of seed jobs is detected as a duplicate pair in
            // the Duplicates review screen (the detector groups by identical cleanedHash + company).
            var dupGroupHash: String? = nil
        }

        let jobs: [SeedJob] = [
            SeedJob(
                capId: "cap_001", jobId: "job_001", jobNum: 1,
                url: "https://www.linkedin.com/jobs/view/4001234567",
                pageTitle: "Senior Technical Program Manager · Stripe",
                company: "Stripe", title: "Senior Technical Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 230_000, salaryMax: 295_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .offer,
                summary: "Lead cross-functional programs for Stripe's payment infrastructure, coordinating between engineering, product, and legal to ship global expansion initiatives.",
                requirements: "BS/MS in CS or related. 8+ years of technical program management. Experience with distributed systems and API platforms. Strong stakeholder management.",
                skills: ["program management", "distributed systems", "APIs", "OKRs", "cross-functional leadership"],
                capturedAt: daysAgo(21), extractedAt: daysAgo(21),
                extractionStatus: .succeeded, fitScore: 91, fitStatus: .succeeded,
                note: "Verbal offer received — negotiating comp. Recruiter mentioned they can move on equity.",
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_002", jobId: "job_002", jobNum: 2,
                url: "https://careers.google.com/jobs/results/98765432",
                pageTitle: "Staff Technical Program Manager, Infrastructure · Google Careers",
                company: "Google", title: "Staff Technical Program Manager, Infrastructure",
                location: "Sunnyvale, CA", remoteType: .hybrid,
                salaryMin: 220_000, salaryMax: 310_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .interview,
                summary: "Drive multi-year infrastructure programs across SRE, SWE, and Cloud teams. Own program health, risk mitigation, and executive communication for planet-scale systems.",
                requirements: "10+ years TPM or engineering leadership. Experience with large-scale infra or platform programs. Excellent written and verbal communication.",
                skills: ["infrastructure", "SRE", "program management", "executive communication", "risk management"],
                capturedAt: daysAgo(18), extractedAt: daysAgo(18),
                extractionStatus: .succeeded, fitScore: 84, fitStatus: .succeeded,
                note: "Final round scheduled for Thursday — 4 interviews. Prep: system design + behavioral.",
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_003", jobId: "job_003", jobNum: 3,
                url: "https://www.anthropic.com/careers/staff-tpm",
                pageTitle: "Staff Technical Program Manager · Anthropic",
                company: "Anthropic", title: "Staff Technical Program Manager",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 250_000, salaryMax: 340_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .interview,
                summary: "Own delivery of safety-critical AI research and deployment programs. Partner with research leads to translate model work into product milestones.",
                requirements: "Strong technical background (CS or equivalent). 8+ years TPM. Prior work in AI/ML or safety-focused environments a plus.",
                skills: ["AI/ML", "safety programs", "research coordination", "technical program management"],
                capturedAt: daysAgo(10), extractedAt: daysAgo(10),
                extractionStatus: .succeeded, fitScore: 79, fitStatus: .succeeded,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_004", jobId: "job_004", jobNum: 4,
                url: "https://www.linkedin.com/jobs/view/4009876543",
                pageTitle: "Principal Technical Program Manager · Microsoft",
                company: "Microsoft", title: "Principal Technical Program Manager",
                location: "Redmond, WA", remoteType: .hybrid,
                salaryMin: 195_000, salaryMax: 275_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .applied,
                summary: "Lead Azure platform programs spanning multiple engineering orgs. Drive clarity on scope, schedule, and dependencies across 10+ teams.",
                requirements: "7+ years TPM in cloud or platform. Proven ability to drive alignment in large matrixed orgs.",
                skills: ["Azure", "cloud platforms", "matrixed orgs", "program management"],
                capturedAt: daysAgo(9), extractedAt: daysAgo(9),
                extractionStatus: .succeeded, fitScore: 76, fitStatus: .succeeded,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_005", jobId: "job_005", jobNum: 5,
                url: "https://www.builtinseattle.com/job/senior-tpm/9001122",
                pageTitle: "Senior Technical Program Manager · Datadog",
                company: "Datadog", title: "Senior Technical Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 185_000, salaryMax: 240_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .applied,
                summary: "Manage programs across Datadog's observability platform. Own delivery for infrastructure monitoring features used by tens of thousands of customers.",
                requirements: "5+ years TPM. SaaS background preferred. Familiarity with observability or monitoring tools.",
                skills: ["SaaS", "observability", "agile", "program management"],
                capturedAt: daysAgo(7), extractedAt: daysAgo(7),
                extractionStatus: .succeeded, fitScore: 82, fitStatus: .succeeded,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_006", jobId: "job_006", jobNum: 6,
                url: "https://openai.com/careers/technical-program-manager",
                pageTitle: "Technical Program Manager · OpenAI",
                company: "OpenAI", title: "Technical Program Manager",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 250_000, salaryMax: 360_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Drive critical programs across OpenAI's research and product orgs. Manage dependencies between frontier model research and consumer/API product teams.",
                requirements: "BS/MS in CS or engineering. 6+ years program management in fast-paced AI or product org.",
                skills: ["AI products", "research coordination", "program management", "fast-paced environment"],
                capturedAt: daysAgo(5), extractedAt: daysAgo(5),
                extractionStatus: .succeeded, fitScore: 88, fitStatus: .succeeded,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_007", jobId: "job_007", jobNum: 7,
                url: "https://boards.greenhouse.io/netflix/jobs/senior-pm",
                pageTitle: "Senior Engineering Program Manager · Netflix",
                company: "Netflix", title: "Senior Engineering Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 260_000, salaryMax: 350_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Lead delivery of high-visibility initiatives across Netflix streaming infrastructure. Drive accountability, remove blockers, and communicate program status to leadership.",
                requirements: "7+ years program management in a high-scale engineering environment.",
                skills: ["streaming infrastructure", "program management", "leadership communication"],
                capturedAt: daysAgo(4), extractedAt: daysAgo(4),
                extractionStatus: .succeeded, fitScore: nil, fitStatus: .none,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_008", jobId: "job_008", jobNum: 8,
                url: "https://jobs.ashbyhq.com/coinbase/tpm-senior",
                pageTitle: "Senior Technical Program Manager · Coinbase",
                company: "Coinbase", title: "Senior Technical Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 195_000, salaryMax: 265_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Own delivery of Coinbase platform programs including wallet, custody, and exchange reliability. Work with crypto infrastructure teams globally.",
                requirements: "5+ years TPM. Fintech or high-regulation environment experience preferred.",
                skills: ["fintech", "crypto", "platform", "program management"],
                capturedAt: daysAgo(3), extractedAt: daysAgo(3),
                extractionStatus: .succeeded, fitScore: nil, fitStatus: .none,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_009", jobId: "job_009", jobNum: 9,
                url: "https://www.builtinseattle.com/job/tpm-amazon/8883344",
                pageTitle: "Principal Technical Program Manager · Amazon",
                company: "Amazon", title: "Principal Technical Program Manager",
                location: "Seattle, WA", remoteType: .hybrid,
                salaryMin: 180_000, salaryMax: 250_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .pursuing,
                summary: "Drive technical programs for AWS reliability engineering, managing Tier-1 service health initiatives across multiple S-team goals.",
                requirements: "8+ years engineering or TPM. AWS experience strongly preferred.",
                skills: ["AWS", "reliability engineering", "S-team programs", "technical leadership"],
                capturedAt: daysAgo(2), extractedAt: nil,
                extractionStatus: .pending, fitScore: nil, fitStatus: .none,
                note: nil,
                duplicateOfJobID: nil,
                dupGroupHash: "demo_dhash_amazon"
            ),
            SeedJob(
                capId: "cap_010", jobId: "job_010", jobNum: 10,
                url: "https://www.linkedin.com/jobs/view/4007654321",
                pageTitle: "Senior Technical Program Manager · Salesforce",
                company: "Salesforce", title: "Senior Technical Program Manager",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 190_000, salaryMax: 245_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Manage CRM platform programs across Salesforce Customer 360. Partner with product and engineering to deliver quarterly milestones.",
                requirements: "6+ years TPM. Enterprise SaaS background. Experience with Agile at scale.",
                skills: ["CRM", "enterprise SaaS", "agile at scale", "program management"],
                capturedAt: daysAgo(1), extractedAt: nil,
                extractionStatus: .pending, fitScore: nil, fitStatus: .none,
                note: nil,
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_011", jobId: "job_011", jobNum: 11,
                url: "https://careers.meta.com/jobs/senior-pm-infra",
                pageTitle: "Senior Program Manager, Infrastructure · Meta",
                company: "Meta", title: "Senior Program Manager, Infrastructure",
                location: "Menlo Park, CA", remoteType: .hybrid,
                salaryMin: 210_000, salaryMax: 270_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .rejected,
                summary: "Drive delivery of Meta infrastructure programs including data center expansion and network reliability.",
                requirements: "7+ years program management. Data center or network infra experience preferred.",
                skills: ["infrastructure", "data center", "program management"],
                capturedAt: daysAgo(30), extractedAt: daysAgo(30),
                extractionStatus: .succeeded, fitScore: 71, fitStatus: .succeeded,
                note: "Phone screen went well but they went with an internal candidate.",
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_012", jobId: "job_012", jobNum: 12,
                url: "https://zoom.us/careers/tpm-senior",
                pageTitle: "Senior Technical Program Manager · Zoom",
                company: "Zoom", title: "Senior Technical Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 155_000, salaryMax: 195_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .rejected,
                summary: "Manage product delivery programs across Zoom's meetings and collaboration platform.",
                requirements: "5+ years TPM. Video/conferencing industry experience a plus.",
                skills: ["collaboration tools", "product delivery", "program management"],
                capturedAt: daysAgo(25), extractedAt: daysAgo(25),
                extractionStatus: .succeeded, fitScore: 58, fitStatus: .succeeded,
                note: "Rejected after technical screen. Salary was low end anyway.",
                duplicateOfJobID: nil
            ),
            SeedJob(
                capId: "cap_013", jobId: "job_013", jobNum: 13,
                url: "https://www.lyft.com/jobs/tpm",
                pageTitle: "Technical Program Manager · Lyft",
                company: "Lyft", title: "Technical Program Manager",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 170_000, salaryMax: 215_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "mid",
                status: .passed,
                summary: "Manage Lyft marketplace and pricing programs. Coordinate across data science, product, and engineering.",
                requirements: "4+ years TPM. Marketplace or two-sided platform experience preferred.",
                skills: ["marketplace", "data science", "program management"],
                capturedAt: daysAgo(45), extractedAt: daysAgo(45),
                extractionStatus: .succeeded, fitScore: 62, fitStatus: .succeeded,
                note: "Decided not to pursue — role is too junior and company has had layoffs.",
                duplicateOfJobID: nil
            ),
            // Duplicate capture — same Amazon job as #9, from a different URL
            SeedJob(
                capId: "cap_014", jobId: "job_014", jobNum: 14,
                url: "https://www.amazon.jobs/en/jobs/9988776/principal-technical-program-manager",
                pageTitle: "Principal Technical Program Manager · Amazon Jobs",
                company: "Amazon", title: "Principal Technical Program Manager",
                location: "Seattle, WA", remoteType: .hybrid,
                salaryMin: 180_000, salaryMax: 250_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .pursuing,
                summary: "Drive technical programs for AWS reliability engineering.",
                requirements: "8+ years engineering or TPM.",
                skills: ["AWS", "reliability engineering"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, fitScore: nil, fitStatus: .none,
                note: nil,
                duplicateOfJobID: "job_009",
                dupGroupHash: "demo_dhash_amazon"
            ),
            // Accidentally captured non-job page
            SeedJob(
                capId: "cap_015", jobId: "job_015", jobNum: 15,
                url: "https://techcrunch.com/2024/11/the-state-of-ai-hiring",
                pageTitle: "The State of AI Hiring in 2024 · TechCrunch",
                company: nil, title: nil,
                location: nil, remoteType: nil,
                salaryMin: nil, salaryMax: nil, salaryCurrency: "USD",
                employmentType: nil, seniority: nil,
                status: .passed,
                summary: nil, requirements: nil, skills: [],
                capturedAt: daysAgo(6), extractedAt: daysAgo(6),
                extractionStatus: .succeeded, fitScore: nil, fitStatus: .none,
                note: "Accidentally captured — not a job posting.",
                duplicateOfJobID: nil
            )
        ]

        // Insert resumes
        modelContext.insert(resume1)
        modelContext.insert(resume2)

        // Insert captures, jobs, and events
        for seed in jobs {
            let visibleText = [seed.title, seed.company, seed.location, seed.summary, seed.requirements]
                .compactMap(\.self)
                .joined(separator: "\n")

            let rawHash = "demo_hash_\(seed.capId)"
            // A shared dupGroupHash makes the two tagged jobs collide into one duplicate pair; all
            // others get a unique hash so they're never flagged as duplicates.
            let cleanedHash = seed.dupGroupHash ?? "demo_chash_\(seed.capId)"

            let capture = Capture(
                id: seed.capId,
                url: seed.url,
                canonicalURL: seed.url,
                pageTitle: seed.pageTitle,
                visibleText: visibleText.isEmpty ? nil : visibleText,
                cleanedDescription: visibleText.isEmpty ? nil : visibleText,
                rawHash: rawHash,
                cleanedHash: cleanedHash,
                capturedAt: seed.capturedAt,
                createdAt: seed.capturedAt
            )

            let extractedJSON: String? = makeExtractedJSON(
                extractionStatus: seed.extractionStatus,
                title: seed.title, company: seed.company,
                location: seed.location, remoteType: seed.remoteType,
                salaryMin: seed.salaryMin, salaryMax: seed.salaryMax,
                salaryCurrency: seed.salaryCurrency,
                employmentType: seed.employmentType, seniority: seed.seniority,
                summary: seed.summary, requirements: seed.requirements,
                skills: seed.skills, url: seed.url
            )
            let fitScoreJSON: String? = makeFitScoreJSON(fitScore: seed.fitScore)

            let job = Job(
                id: seed.jobId,
                jobNumber: seed.jobNum,
                company: seed.company,
                title: seed.title,
                location: seed.location,
                remoteType: seed.remoteType,
                salaryMin: seed.salaryMin,
                salaryMax: seed.salaryMax,
                salaryCurrency: seed.salaryCurrency,
                salaryNote: salaryNote(min: seed.salaryMin, max: seed.salaryMax),
                employmentType: seed.employmentType,
                seniority: seed.seniority,
                status: seed.status,
                extractedJSON: extractedJSON,
                extractionStatus: seed.extractionStatus,
                fitScore: seed.fitScore,
                fitStatus: seed.fitStatus,
                fitScoreJSON: fitScoreJSON,
                duplicateOfJobID: seed.duplicateOfJobID,
                extractedAt: seed.extractedAt,
                applicationURL: seed.url,
                createdAt: seed.capturedAt,
                updatedAt: seed.capturedAt
            )
            job.capture = capture

            // Note event
            if let note = seed.note {
                let noteEvent = JobEvent(
                    id: "evt_\(seed.jobId)",
                    eventType: "note",
                    note: note,
                    occurredAt: seed.capturedAt,
                    createdAt: seed.capturedAt
                )
                job.events.append(noteEvent)
                modelContext.insert(noteEvent)
            }

            // Status change event for non-saved jobs
            if seed.status != .pursuing {
                let statusAt = seed.capturedAt.addingTimeInterval(2 * 86400)
                let statusEvent = JobEvent(
                    id: "evt_status_\(seed.jobId)",
                    eventType: "status_change",
                    note: seed.status.rawValue,
                    occurredAt: statusAt,
                    createdAt: statusAt
                )
                job.events.append(statusEvent)
                modelContext.insert(statusEvent)
            }

            modelContext.insert(capture)
            modelContext.insert(job)
        }

        // MARK: Sites

        let reviewedAt = daysAgo(3)
        let nextReview = Date(timeIntervalSinceNow: 7 * 86400)

        let sites: [(id: String, url: String, origin: String, title: String, interval: Int)] = [
            (
                "site_001",
                "https://www.linkedin.com/jobs/search/?keywords=technical+program+manager&f_WT=2",
                "https://www.linkedin.com",
                "LinkedIn Jobs — TPM Remote",
                7
            ),
            (
                "site_002",
                "https://www.builtinseattle.com/jobs/remote",
                "https://www.builtinseattle.com",
                "Built In Seattle — Remote",
                7
            ),
            (
                "site_003",
                "https://levels.fyi/jobs?title=Technical+Program+Manager",
                "https://levels.fyi",
                "Levels.fyi — TPM Jobs",
                14
            )
        ]

        for siteData in sites {
            let site = Site(
                id: siteData.id,
                origin: siteData.origin,
                url: siteData.url,
                pageTitle: siteData.title,
                intervalDays: siteData.interval,
                lastReviewedAt: reviewedAt,
                nextReviewAt: nextReview,
                state: .reviewed,
                addedAt: reviewedAt,
                createdAt: reviewedAt,
                updatedAt: reviewedAt
            )
            modelContext.insert(site)
        }

        try modelContext.save()
    }

    // MARK: - JSON builders (private)

    // swiftlint:disable:next function_parameter_count
    private func makeExtractedJSON(
        extractionStatus: ExtractionStatus,
        title: String?, company: String?, location: String?, remoteType: RemoteType?,
        salaryMin: Int?, salaryMax: Int?, salaryCurrency: String,
        employmentType: String?, seniority: String?, summary: String?,
        requirements: String?, skills: [String], url: String
    ) -> String? {
        guard extractionStatus != .pending, title != nil else { return nil }
        var dict: [String: Any] = [
            "company": company as Any,
            "title": title as Any,
            "location": location as Any,
            "remote_type": remoteType?.rawValue as Any,
            "salary_min": salaryMin as Any,
            "salary_max": salaryMax as Any,
            "salary_currency": salaryCurrency,
            "employment_type": employmentType ?? "full_time",
            "seniority": seniority as Any,
            "summary": summary as Any,
            "requirements": requirements.map { [$0] } as Any,
            "nice_to_haves": [] as [String],
            "benefits": [] as [String],
            "skills": skills,
            "application_url": url,
            "confidence": 0.92
        ]
        if let min = salaryMin, let max = salaryMax {
            dict["salary_note"] = "$\(min / 1000)K–$\(max / 1000)K"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func makeFitScoreJSON(fitScore: Int?) -> String? {
        guard let score = fitScore else { return nil }
        let quality = score >= 85 ? "excellent" : score >= 75 ? "good" : "moderate"
        let dict: [String: Any] = [
            "score": score,
            "summary": "Strong match — \(quality) alignment with your background.",
            "strengths": ["Technical program management experience", "Cross-functional leadership"],
            "gaps": score < 80 ? ["Could strengthen domain-specific experience"] : [] as [String]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func salaryNote(min: Int?, max: Int?) -> String? {
        guard let min, let max else { return nil }
        return "$\(min / 1000)K–$\(max / 1000)K"
    }
}

// MARK: - DemoMode

/// Identifies whether the app is showing demo data or the user's real data.
public enum DemoMode: Sendable {
    case live
    case demo
}

// swiftlint:enable line_length file_length function_body_length large_tuple
