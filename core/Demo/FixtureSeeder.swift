// swiftlint:disable line_length file_length function_body_length large_tuple
import Foundation
import SwiftData

// MARK: - FixtureSeeder

/// Seeds a comprehensive, deterministic fixture dataset for testing.
/// Covers every JobStatus, all data-quality edge cases, duplicate groups,
/// JobActions (overdue/upcoming/completed), Sites, and SavedSearches.
///
/// IDs are deterministic strings (e.g. "fixture_job_001") — safe to call
/// repeatedly when `skipIfPopulated` is true (the default).
public enum FixtureSeeder {
    // MARK: - Public API

    /// Insert fixture data into `store`.
    /// - Parameter skipIfPopulated: When true (default), skips seeding if any jobs already exist.
    public static func seed(into store: BackgroundStore, skipIfPopulated: Bool = true) async throws {
        try await store.performFixtureSeed(skipIfPopulated: skipIfPopulated)
    }
}

// MARK: - BackgroundStore fixture seed helpers

extension BackgroundStore {
    func performFixtureSeed(skipIfPopulated: Bool) throws {
        if skipIfPopulated {
            let existing = try fetch(FetchDescriptor<Job>())
            guard existing.isEmpty else { return }
        }
        try executeFixtureSeed()
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func executeFixtureSeed() throws {
        // TASK-421: a FIXED base date so regenerating the fixture yields byte-stable SQLite + manifest
        // (no wall-clock drift). All fixture timestamps derive from this. 1_750_000_000 =
        // 2025-06-15T07:46:40Z — see docs/test-db-spec.md.
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86400) }
        func daysFromNow(_ n: Double) -> Date { now.addingTimeInterval(n * 86400) }

        // MARK: - SeedJob struct (same shape as DemoSeeder)

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
            let extractionConfidence: Double?
            let fitScore: Int?
            let fitStatus: FitStatus
            let note: String?
            let duplicateOfJobID: String?
            // Raw-text byte hints (used to trigger shortRawText / shortCleanedText quality issues)
            let rawTextBytes: Int?
            let cleanedTextBytes: Int?
        }

        // MARK: - Job fixtures

        let jobs: [SeedJob] = [

            // ── .new — remote ────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_001", jobId: "fixture_job_001", jobNum: 1001,
                url: "https://boards.greenhouse.io/stripe/jobs/tpm-remote-001",
                pageTitle: "Senior Technical Program Manager · Stripe",
                company: "Stripe", title: "Senior Technical Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 230_000, salaryMax: 290_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .new,
                summary: "Lead cross-functional programs across Stripe's payments and financial infrastructure. Drive delivery of API reliability and latency initiatives with engineering and product. Own program health dashboards and OKR tracking for Stripe's core infrastructure org.",
                requirements: "8+ years TPM. Experience with distributed payment systems. Strong stakeholder management across engineering and product.",
                skills: ["payments", "distributed systems", "OKRs", "program management"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, extractionConfidence: 0.93,
                fitScore: 88, fitStatus: .succeeded,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 4200, cleanedTextBytes: 3100
            ),

            // ── .new — onsite ────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_002", jobId: "fixture_job_002", jobNum: 1002,
                url: "https://careers.apple.com/en-us/details/tpm-silicon-1002",
                pageTitle: "Principal TPM, Silicon Programs · Apple",
                company: "Apple", title: "Principal Technical Program Manager, Silicon",
                location: "Cupertino, CA", remoteType: .onsite,
                salaryMin: 240_000, salaryMax: 320_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .new,
                summary: "Drive delivery of Apple Silicon chip programs from architecture through mass production. Coordinate across hardware engineering, EDA, and manufacturing partners in Asia. Own schedule risk and executive communication for A-series and M-series programs.",
                requirements: "10+ years TPM in hardware or semiconductor. Experience with chip tape-out schedules. Strong cross-cultural communication.",
                skills: ["silicon", "hardware programs", "manufacturing", "risk management"],
                capturedAt: daysAgo(2), extractedAt: daysAgo(2),
                extractionStatus: .succeeded, extractionConfidence: 0.91,
                fitScore: 74, fitStatus: .succeeded,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 5100, cleanedTextBytes: 3800
            ),

            // ── .new — hybrid ────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_003", jobId: "fixture_job_003", jobNum: 1003,
                url: "https://www.linkedin.com/jobs/view/fixture-003",
                pageTitle: "Staff TPM, Platform · Airbnb",
                company: "Airbnb", title: "Staff Technical Program Manager, Platform",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 220_000, salaryMax: 285_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .new,
                summary: "Own delivery of Airbnb platform initiatives including payments localization and trust infrastructure. Work with engineering managers and product leads across 6 platform teams. Drive quarterly planning, dependency mapping, and roadmap communication to VP-level stakeholders.",
                requirements: "8+ years TPM. Platform or marketplace background. Excellent written communication. Experience with international expansion programs.",
                skills: ["platform", "marketplace", "international", "program management"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, extractionConfidence: 0.89,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3900, cleanedTextBytes: 2900
            ),

            // ── .new — missing title (triggers missingTitle quality issue) ────────────
            SeedJob(
                capId: "fixture_cap_004", jobId: "fixture_job_004", jobNum: 1004,
                url: "https://www.linkedin.com/jobs/view/fixture-004",
                pageTitle: "Job at Databricks · LinkedIn",
                company: "Databricks", title: nil,
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 200_000, salaryMax: 260_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: nil,
                status: .new,
                summary: "Drive delivery of Databricks Lakehouse programs across data engineering and ML platform teams.",
                requirements: "6+ years TPM. Data platform experience.",
                skills: ["data platform", "ML", "program management"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, extractionConfidence: 0.55,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 2800, cleanedTextBytes: 2100
            ),

            // ── .new — missing company (triggers missingCompany quality issue) ────────
            SeedJob(
                capId: "fixture_cap_005", jobId: "fixture_job_005", jobNum: 1005,
                url: "https://jobs.lever.co/unknown-stealth/tpm-005",
                pageTitle: "Senior TPM · Stealth Startup",
                company: nil, title: "Senior Technical Program Manager",
                location: "New York, NY", remoteType: .hybrid,
                salaryMin: 180_000, salaryMax: 230_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .new,
                summary: "Stealth-mode fintech startup building next-gen payment infrastructure. Looking for a senior TPM to drive foundational platform delivery.",
                requirements: "5+ years TPM. Fintech or startup experience preferred.",
                skills: ["fintech", "startup", "program management"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, extractionConfidence: 0.48,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 1800, cleanedTextBytes: 1400
            ),

            // ── .pursuing × 4 ────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_006", jobId: "fixture_job_006", jobNum: 1006,
                url: "https://openai.com/careers/tpm-research-006",
                pageTitle: "Technical Program Manager, Research · OpenAI",
                company: "OpenAI", title: "Technical Program Manager, Research Coordination",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 260_000, salaryMax: 370_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Own delivery of OpenAI's frontier model research programs. Drive coordination between research scientists, infrastructure, and safety teams. Own timeline tracking and dependency resolution for model training runs.",
                requirements: "6+ years TPM in fast-paced AI or research org. Strong quantitative background. Experience managing technically complex projects.",
                skills: ["AI research", "model training", "program management", "cross-functional leadership"],
                capturedAt: daysAgo(5), extractedAt: daysAgo(5),
                extractionStatus: .succeeded, extractionConfidence: 0.94,
                fitScore: 92, fitStatus: .succeeded,
                note: "Recruiter reached out. Warm intro from former colleague on the safety team.",
                duplicateOfJobID: nil,
                rawTextBytes: 5500, cleanedTextBytes: 4200
            ),

            SeedJob(
                capId: "fixture_cap_007", jobId: "fixture_job_007", jobNum: 1007,
                url: "https://careers.netflix.com/jobs/tpm-infra-007",
                pageTitle: "Engineering Program Manager, Infrastructure · Netflix",
                company: "Netflix", title: "Engineering Program Manager, Infrastructure",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 280_000, salaryMax: 380_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Drive delivery of Netflix streaming infrastructure programs. Coordinate across encoding, CDN, and reliability engineering teams. Own program health communication to director and VP stakeholders.",
                requirements: "7+ years program management at high-scale engineering companies. Strong written communication. Experience with streaming or media tech a plus.",
                skills: ["streaming infrastructure", "CDN", "program management"],
                capturedAt: daysAgo(4), extractedAt: daysAgo(4),
                extractionStatus: .succeeded, extractionConfidence: 0.91,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 4800, cleanedTextBytes: 3600
            ),

            // ── .pursuing — missing location (triggers missingLocation quality issue) ──
            SeedJob(
                capId: "fixture_cap_008", jobId: "fixture_job_008", jobNum: 1008,
                url: "https://jobs.ashbyhq.com/figma/tpm-platform-008",
                pageTitle: "Senior TPM, Design Platform · Figma",
                company: "Figma", title: "Senior Technical Program Manager, Design Platform",
                location: nil, remoteType: .hybrid,
                salaryMin: 215_000, salaryMax: 270_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Lead Figma platform initiatives including multiplayer infrastructure and plugin ecosystem. Drive cross-team delivery with engineering and design systems teams.",
                requirements: "6+ years TPM. Developer platform or design tools experience preferred.",
                skills: ["developer platform", "design systems", "program management"],
                capturedAt: daysAgo(3), extractedAt: daysAgo(3),
                extractionStatus: .succeeded, extractionConfidence: 0.72,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3200, cleanedTextBytes: 2400
            ),

            SeedJob(
                capId: "fixture_cap_009", jobId: "fixture_job_009", jobNum: 1009,
                url: "https://www.linkedin.com/jobs/view/fixture-009",
                pageTitle: "Principal TPM, Cloud Platform · Google",
                company: "Google", title: "Principal Technical Program Manager, Cloud",
                location: "Sunnyvale, CA", remoteType: .hybrid,
                salaryMin: 235_000, salaryMax: 320_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .pursuing,
                summary: "Drive multi-year GCP platform programs spanning Compute, Networking, and Storage. Own program health and executive communications for org-wide engineering initiatives.",
                requirements: "10+ years TPM or engineering leadership. Cloud infrastructure background strongly preferred.",
                skills: ["GCP", "cloud", "networking", "program management"],
                capturedAt: daysAgo(2), extractedAt: daysAgo(2),
                extractionStatus: .succeeded, extractionConfidence: 0.88,
                fitScore: 81, fitStatus: .succeeded,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 4600, cleanedTextBytes: 3500
            ),

            // ── .applied — 1 day ago ─────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_010", jobId: "fixture_job_010", jobNum: 1010,
                url: "https://boards.greenhouse.io/microsoft/jobs/tpm-azure-010",
                pageTitle: "Principal TPM, Azure Platform · Microsoft",
                company: "Microsoft", title: "Principal Technical Program Manager, Azure",
                location: "Redmond, WA", remoteType: .hybrid,
                salaryMin: 200_000, salaryMax: 280_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .applied,
                summary: "Lead Azure platform programs spanning compute, storage, and networking. Drive alignment across 10+ engineering teams on quarterly roadmap commitments.",
                requirements: "8+ years TPM in cloud or platform. Proven track record of delivery in large matrixed orgs.",
                skills: ["Azure", "cloud platforms", "matrixed orgs", "program management"],
                capturedAt: daysAgo(5), extractedAt: daysAgo(5),
                extractionStatus: .succeeded, extractionConfidence: 0.90,
                fitScore: 78, fitStatus: .succeeded,
                note: "Applied via LinkedIn Easy Apply. Referral from TPM community Slack.",
                duplicateOfJobID: nil,
                rawTextBytes: 4400, cleanedTextBytes: 3300
            ),

            // ── .applied — 7 days ago ────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_011", jobId: "fixture_job_011", jobNum: 1011,
                url: "https://jobs.ashbyhq.com/databricks/tpm-data-011",
                pageTitle: "Staff TPM, Data Platform · Databricks",
                company: "Databricks", title: "Staff Technical Program Manager, Data Platform",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 225_000, salaryMax: 295_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .applied,
                summary: "Drive delivery of Databricks Lakehouse programs. Coordinate across Data Engineering, MLflow, and Unity Catalog teams on cross-cutting initiatives.",
                requirements: "7+ years TPM. Data engineering or ML platform background preferred.",
                skills: ["Databricks", "data platform", "MLflow", "program management"],
                capturedAt: daysAgo(12), extractedAt: daysAgo(12),
                extractionStatus: .succeeded, extractionConfidence: 0.86,
                fitScore: 83, fitStatus: .succeeded,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 4100, cleanedTextBytes: 3000
            ),

            // ── .applied — 30 days ago ───────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_012", jobId: "fixture_job_012", jobNum: 1012,
                url: "https://www.linkedin.com/jobs/view/fixture-012",
                pageTitle: "Senior TPM, Ads Platform · Snap",
                company: "Snap", title: "Senior Technical Program Manager, Ads Platform",
                location: "Los Angeles, CA", remoteType: .hybrid,
                salaryMin: 195_000, salaryMax: 255_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .applied,
                summary: "Drive ad tech program delivery across Snap's auction, targeting, and measurement infrastructure. Coordinate with monetization engineers and product managers.",
                requirements: "5+ years TPM. Ad tech or auction systems experience preferred.",
                skills: ["ad tech", "auctions", "measurement", "program management"],
                capturedAt: daysAgo(35), extractedAt: daysAgo(35),
                extractionStatus: .succeeded, extractionConfidence: 0.82,
                fitScore: 69, fitStatus: .succeeded,
                note: "Submitted application. No response yet — will follow up soon.",
                duplicateOfJobID: nil,
                rawTextBytes: 3700, cleanedTextBytes: 2800
            ),

            // ── .applied — 60 days ago ───────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_013", jobId: "fixture_job_013", jobNum: 1013,
                url: "https://careers.salesforce.com/jobs/tpm-crm-013",
                pageTitle: "Senior TPM, CRM Platform · Salesforce",
                company: "Salesforce", title: "Senior Technical Program Manager, CRM Platform",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 190_000, salaryMax: 245_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .applied,
                summary: "Manage Customer 360 platform programs across Salesforce CRM orgs. Partner with engineering leads to deliver quarterly milestones and manage cross-team dependencies.",
                requirements: "6+ years TPM. Enterprise SaaS background. Experience with Agile at scale.",
                skills: ["CRM", "enterprise SaaS", "Agile", "program management"],
                capturedAt: daysAgo(65), extractedAt: daysAgo(65),
                extractionStatus: .succeeded, extractionConfidence: 0.79,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3500, cleanedTextBytes: 2600
            ),

            // ── .applied — 90 days ago ───────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_014", jobId: "fixture_job_014", jobNum: 1014,
                url: "https://www.linkedin.com/jobs/view/fixture-014",
                pageTitle: "Principal TPM, Supply Chain · Amazon",
                company: "Amazon", title: "Principal Technical Program Manager, Supply Chain",
                location: "Seattle, WA", remoteType: .hybrid,
                salaryMin: 185_000, salaryMax: 260_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .applied,
                summary: "Drive supply chain reliability programs for Amazon's fulfillment network. Manage dependencies across robotics, software, and operations engineering teams.",
                requirements: "8+ years engineering or TPM. Supply chain or logistics systems experience preferred.",
                skills: ["supply chain", "robotics", "operations", "program management"],
                capturedAt: daysAgo(95), extractedAt: daysAgo(95),
                extractionStatus: .succeeded, extractionConfidence: 0.84,
                fitScore: 72, fitStatus: .succeeded,
                note: "Applied via Amazon Jobs portal.",
                duplicateOfJobID: nil,
                rawTextBytes: 4000, cleanedTextBytes: 3000
            ),

            // ── .applied — 45 days ago, stale, no follow-up (stale application DQ) ──
            SeedJob(
                capId: "fixture_cap_015", jobId: "fixture_job_015", jobNum: 1015,
                url: "https://jobs.lever.co/plaid/tpm-infra-015",
                pageTitle: "Senior TPM, Infrastructure · Plaid",
                company: "Plaid", title: "Senior Technical Program Manager, Infrastructure",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 210_000, salaryMax: 270_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .applied,
                summary: "Lead infrastructure programs across Plaid's financial data platform. Drive reliability and scalability initiatives with engineering and product teams.",
                requirements: "5+ years TPM. Financial data or API platform experience preferred.",
                skills: ["fintech", "API platform", "reliability", "program management"],
                capturedAt: daysAgo(50), extractedAt: daysAgo(50),
                extractionStatus: .succeeded, extractionConfidence: 0.81,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3600, cleanedTextBytes: 2700
            ),

            // ── .interview × 3 ───────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_016", jobId: "fixture_job_016", jobNum: 1016,
                url: "https://www.anthropic.com/careers/staff-tpm-research",
                pageTitle: "Staff TPM, Research Programs · Anthropic",
                company: "Anthropic", title: "Staff Technical Program Manager, Research",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 265_000, salaryMax: 350_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .interview,
                summary: "Own delivery of safety-critical AI research programs at Anthropic. Partner with research leads to translate model work into product milestones. Drive cross-team coordination across interpretability, alignment, and infrastructure teams.",
                requirements: "8+ years TPM. Prior work in AI/ML or safety-focused environments a plus. Strong technical background.",
                skills: ["AI safety", "research coordination", "technical program management"],
                capturedAt: daysAgo(18), extractedAt: daysAgo(18),
                extractionStatus: .succeeded, extractionConfidence: 0.95,
                fitScore: 85, fitStatus: .succeeded,
                note: "Onsite scheduled for next Tuesday. Prepping behavioral questions.",
                duplicateOfJobID: nil,
                rawTextBytes: 5800, cleanedTextBytes: 4300
            ),

            SeedJob(
                capId: "fixture_cap_017", jobId: "fixture_job_017", jobNum: 1017,
                url: "https://careers.google.com/jobs/results/fixture-017",
                pageTitle: "Staff TPM, Infrastructure · Google",
                company: "Google", title: "Staff Technical Program Manager, Infrastructure",
                location: "Sunnyvale, CA", remoteType: .hybrid,
                salaryMin: 225_000, salaryMax: 310_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .interview,
                summary: "Drive SRE and infrastructure programs across Google data center and network teams. Own program health communication to L8+ stakeholders. Lead quarterly planning across 15+ engineering teams.",
                requirements: "10+ years TPM or engineering leadership. Infra or SRE background strongly preferred.",
                skills: ["SRE", "data center", "infrastructure", "program management"],
                capturedAt: daysAgo(14), extractedAt: daysAgo(14),
                extractionStatus: .succeeded, extractionConfidence: 0.92,
                fitScore: 80, fitStatus: .succeeded,
                note: "Phone screen passed. Loop scheduled in two weeks.",
                duplicateOfJobID: nil,
                rawTextBytes: 5200, cleanedTextBytes: 3900
            ),

            // .interview — has a pending JobAction (follow-up due yesterday)
            SeedJob(
                capId: "fixture_cap_018", jobId: "fixture_job_018", jobNum: 1018,
                url: "https://jobs.ashbyhq.com/scale-ai/tpm-data-018",
                pageTitle: "Senior TPM, Data Operations · Scale AI",
                company: "Scale AI", title: "Senior Technical Program Manager, Data Operations",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 200_000, salaryMax: 260_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .interview,
                summary: "Lead programs across Scale AI's data labeling and model evaluation infrastructure. Coordinate between ML engineers, labeling operations, and product. Drive quarterly OKR tracking and program health reporting.",
                requirements: "5+ years TPM. ML data operations or annotation pipeline experience preferred.",
                skills: ["ML data", "data ops", "program management"],
                capturedAt: daysAgo(20), extractedAt: daysAgo(20),
                extractionStatus: .succeeded, extractionConfidence: 0.87,
                fitScore: 76, fitStatus: .succeeded,
                note: "Phone screen complete. Waiting on loop scheduling.",
                duplicateOfJobID: nil,
                rawTextBytes: 4300, cleanedTextBytes: 3200
            ),

            // ── .offer × 2 ───────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_019", jobId: "fixture_job_019", jobNum: 1019,
                url: "https://boards.greenhouse.io/stripe/jobs/tpm-offer-019",
                pageTitle: "Staff TPM, Payments · Stripe",
                company: "Stripe", title: "Staff Technical Program Manager, Payments",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 250_000, salaryMax: 310_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .offer,
                summary: "Lead strategic payment infrastructure programs at Stripe. Drive multi-year technical roadmaps with engineering and product leadership.",
                requirements: "8+ years TPM. Financial infrastructure or payment systems experience preferred.",
                skills: ["payments", "infrastructure", "program management"],
                capturedAt: daysAgo(28), extractedAt: daysAgo(28),
                extractionStatus: .succeeded, extractionConfidence: 0.96,
                fitScore: 91, fitStatus: .succeeded,
                note: "Verbal offer received: $290K base + equity. Negotiating start date and sign-on.",
                duplicateOfJobID: nil,
                rawTextBytes: 5000, cleanedTextBytes: 3700
            ),

            SeedJob(
                capId: "fixture_cap_020", jobId: "fixture_job_020", jobNum: 1020,
                url: "https://www.linkedin.com/jobs/view/fixture-020",
                pageTitle: "Senior TPM, Platform · Cloudflare",
                company: "Cloudflare", title: "Senior Technical Program Manager, Platform",
                location: "Austin, TX", remoteType: .hybrid,
                salaryMin: 195_000, salaryMax: 250_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .offer,
                summary: "Drive delivery of Cloudflare Workers and edge platform programs. Coordinate across runtime, storage, and developer experience teams.",
                requirements: "5+ years TPM. Edge computing or developer platform experience preferred.",
                skills: ["edge computing", "developer platform", "program management"],
                capturedAt: daysAgo(22), extractedAt: daysAgo(22),
                extractionStatus: .succeeded, extractionConfidence: 0.88,
                fitScore: 84, fitStatus: .succeeded,
                note: "Offer in hand: $235K base. Comp is lower end — holding for Stripe decision.",
                duplicateOfJobID: nil,
                rawTextBytes: 4700, cleanedTextBytes: 3500
            ),

            // ── .rejected × 4 ────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_021", jobId: "fixture_job_021", jobNum: 1021,
                url: "https://careers.meta.com/jobs/tpm-infra-021",
                pageTitle: "Senior TPM, Infrastructure · Meta",
                company: "Meta", title: "Senior Technical Program Manager, Infrastructure",
                location: "Menlo Park, CA", remoteType: .hybrid,
                salaryMin: 210_000, salaryMax: 270_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .rejected,
                summary: "Drive delivery of Meta infrastructure programs including data center expansion, network reliability, and capacity planning.",
                requirements: "7+ years program management. Data center or network infra experience preferred.",
                skills: ["infrastructure", "data center", "program management"],
                capturedAt: daysAgo(45), extractedAt: daysAgo(45),
                extractionStatus: .succeeded, extractionConfidence: 0.90,
                fitScore: 71, fitStatus: .succeeded,
                note: "Rejected after 2nd phone screen. Went with internal candidate.",
                duplicateOfJobID: nil,
                rawTextBytes: 4200, cleanedTextBytes: 3100
            ),

            SeedJob(
                capId: "fixture_cap_022", jobId: "fixture_job_022", jobNum: 1022,
                url: "https://zoom.us/careers/tpm-platform-022",
                pageTitle: "Senior TPM, Platform · Zoom",
                company: "Zoom", title: "Senior Technical Program Manager, Platform",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 155_000, salaryMax: 195_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .rejected,
                summary: "Drive platform program delivery across Zoom's meetings, webinars, and collaboration infrastructure.",
                requirements: "5+ years TPM. Video or conferencing tech background a plus.",
                skills: ["collaboration tools", "meetings", "program management"],
                capturedAt: daysAgo(40), extractedAt: daysAgo(40),
                extractionStatus: .succeeded, extractionConfidence: 0.83,
                fitScore: 58, fitStatus: .succeeded,
                note: "Rejected after technical screen. Salary too low anyway.",
                duplicateOfJobID: nil,
                rawTextBytes: 3300, cleanedTextBytes: 2500
            ),

            SeedJob(
                capId: "fixture_cap_023", jobId: "fixture_job_023", jobNum: 1023,
                url: "https://www.linkedin.com/jobs/view/fixture-023",
                pageTitle: "Principal TPM, Supply Chain · Rivian",
                company: "Rivian", title: "Principal Technical Program Manager, Supply Chain",
                location: "Normal, IL", remoteType: .onsite,
                salaryMin: 175_000, salaryMax: 220_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .rejected,
                summary: "Lead supply chain and manufacturing programs for Rivian's EV production. Coordinate across procurement, engineering, and factory operations teams.",
                requirements: "7+ years TPM. Hardware or manufacturing background preferred.",
                skills: ["supply chain", "manufacturing", "EV", "program management"],
                capturedAt: daysAgo(55), extractedAt: daysAgo(55),
                extractionStatus: .succeeded, extractionConfidence: 0.75,
                fitScore: 54, fitStatus: .succeeded,
                note: "No offer — not a great culture fit, and fully onsite in Illinois.",
                duplicateOfJobID: nil,
                rawTextBytes: 3800, cleanedTextBytes: 2900
            ),

            SeedJob(
                capId: "fixture_cap_024", jobId: "fixture_job_024", jobNum: 1024,
                url: "https://jobs.lever.co/palantir/tpm-024",
                pageTitle: "Technical Program Manager · Palantir",
                company: "Palantir", title: "Technical Program Manager",
                location: "New York, NY", remoteType: .hybrid,
                salaryMin: 160_000, salaryMax: 200_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "mid",
                status: .rejected,
                summary: "Drive delivery of Palantir platform programs for government and commercial customers. Coordinate between engineers, forward deployed engineers, and customer stakeholders.",
                requirements: "4+ years TPM or technical delivery. Willingness to work with US government clients.",
                skills: ["platform", "government tech", "program management"],
                capturedAt: daysAgo(38), extractedAt: daysAgo(38),
                extractionStatus: .succeeded, extractionConfidence: 0.77,
                fitScore: 62, fitStatus: .succeeded,
                note: "Rejected after final round. Government focus not a good fit.",
                duplicateOfJobID: nil,
                rawTextBytes: 3100, cleanedTextBytes: 2300
            ),

            // ── .passed × 3 ──────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_025", jobId: "fixture_job_025", jobNum: 1025,
                url: "https://www.lyft.com/jobs/tpm-marketplace-025",
                pageTitle: "Technical Program Manager, Marketplace · Lyft",
                company: "Lyft", title: "Technical Program Manager, Marketplace",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 165_000, salaryMax: 210_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "mid",
                status: .passed,
                summary: "Drive marketplace and pricing programs at Lyft. Coordinate across data science, product, and engineering teams on two-sided marketplace initiatives.",
                requirements: "4+ years TPM. Marketplace or ride-sharing background preferred.",
                skills: ["marketplace", "data science", "program management"],
                capturedAt: daysAgo(50), extractedAt: daysAgo(50),
                extractionStatus: .succeeded, extractionConfidence: 0.82,
                fitScore: 63, fitStatus: .succeeded,
                note: "Passed — too junior and company has had layoffs.",
                duplicateOfJobID: nil,
                rawTextBytes: 3400, cleanedTextBytes: 2600
            ),

            SeedJob(
                capId: "fixture_cap_026", jobId: "fixture_job_026", jobNum: 1026,
                url: "https://www.linkedin.com/jobs/view/fixture-026",
                pageTitle: "Senior TPM, Consumer · Twitter/X",
                company: "X (Twitter)", title: "Senior Technical Program Manager, Consumer",
                location: "San Francisco, CA", remoteType: .onsite,
                salaryMin: 170_000, salaryMax: 220_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .passed,
                summary: "Lead consumer product programs at X across feed, notifications, and monetization. Work with engineering and product leadership on quarterly delivery.",
                requirements: "5+ years TPM. Consumer social product experience preferred.",
                skills: ["consumer product", "social", "program management"],
                capturedAt: daysAgo(60), extractedAt: daysAgo(60),
                extractionStatus: .succeeded, extractionConfidence: 0.79,
                fitScore: nil, fitStatus: .none,
                note: "Passed — fully onsite requirement and current culture concerns.",
                duplicateOfJobID: nil,
                rawTextBytes: 3600, cleanedTextBytes: 2700
            ),

            SeedJob(
                capId: "fixture_cap_027", jobId: "fixture_job_027", jobNum: 1027,
                url: "https://techcrunch.com/article/state-of-tpm-hiring-2025",
                pageTitle: "State of TPM Hiring 2025 · TechCrunch",
                company: nil, title: nil,
                location: nil, remoteType: nil,
                salaryMin: nil, salaryMax: nil, salaryCurrency: "USD",
                employmentType: nil, seniority: nil,
                status: .passed,
                summary: nil, requirements: nil, skills: [],
                capturedAt: daysAgo(7), extractedAt: daysAgo(7),
                extractionStatus: .succeeded, extractionConfidence: nil,
                fitScore: nil, fitStatus: .none,
                note: "Accidentally captured — not a job posting.",
                duplicateOfJobID: nil,
                rawTextBytes: nil, cleanedTextBytes: nil
            ),

            // ── .archived × 3 ────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_028", jobId: "fixture_job_028", jobNum: 1028,
                url: "https://www.linkedin.com/jobs/view/fixture-028",
                pageTitle: "Senior TPM, Platform · Uber",
                company: "Uber", title: "Senior Technical Program Manager, Platform",
                location: "San Francisco, CA", remoteType: .hybrid,
                salaryMin: 200_000, salaryMax: 260_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .archived,
                summary: "Drive platform program delivery across Uber's ride, delivery, and freight engineering orgs.",
                requirements: "6+ years TPM. Two-sided marketplace or logistics background preferred.",
                skills: ["marketplace", "logistics", "program management"],
                capturedAt: daysAgo(90), extractedAt: daysAgo(90),
                extractionStatus: .succeeded, extractionConfidence: 0.85,
                fitScore: 70, fitStatus: .succeeded,
                note: "Archived — offer from Stripe accepted.",
                duplicateOfJobID: nil,
                rawTextBytes: 3900, cleanedTextBytes: 2900
            ),

            SeedJob(
                capId: "fixture_cap_029", jobId: "fixture_job_029", jobNum: 1029,
                url: "https://www.linkedin.com/jobs/view/fixture-029",
                pageTitle: "Staff TPM, Ads · Pinterest",
                company: "Pinterest", title: "Staff Technical Program Manager, Ads",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 190_000, salaryMax: 245_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .archived,
                summary: "Lead ad tech programs across Pinterest's shopping and performance ads infrastructure.",
                requirements: "6+ years TPM. Ad tech or e-commerce background preferred.",
                skills: ["ad tech", "shopping", "program management"],
                capturedAt: daysAgo(85), extractedAt: daysAgo(85),
                extractionStatus: .succeeded, extractionConfidence: 0.80,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3700, cleanedTextBytes: 2800
            ),

            SeedJob(
                capId: "fixture_cap_030", jobId: "fixture_job_030", jobNum: 1030,
                url: "https://jobs.lever.co/shopify/tpm-platform-030",
                pageTitle: "Senior TPM, Platform · Shopify",
                company: "Shopify", title: "Senior Technical Program Manager, Platform",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 185_000, salaryMax: 240_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .archived,
                summary: "Drive platform programs across Shopify's merchant tools and storefront infrastructure.",
                requirements: "5+ years TPM. E-commerce or merchant tools background preferred.",
                skills: ["e-commerce", "merchant tools", "program management"],
                capturedAt: daysAgo(80), extractedAt: daysAgo(80),
                extractionStatus: .succeeded, extractionConfidence: 0.83,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3500, cleanedTextBytes: 2600
            ),

            // ── .closed × 2 ──────────────────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_031", jobId: "fixture_job_031", jobNum: 1031,
                url: "https://www.linkedin.com/jobs/view/fixture-031",
                pageTitle: "Principal TPM, AI Platform · Nvidia",
                company: "Nvidia", title: "Principal Technical Program Manager, AI Platform",
                location: "Santa Clara, CA", remoteType: .hybrid,
                salaryMin: 245_000, salaryMax: 330_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .closed,
                summary: "Drive AI platform programs across Nvidia's GPU computing and CUDA software stack.",
                requirements: "10+ years TPM. GPU computing or AI infrastructure experience preferred.",
                skills: ["GPU", "AI platform", "CUDA", "program management"],
                capturedAt: daysAgo(70), extractedAt: daysAgo(70),
                extractionStatus: .succeeded, extractionConfidence: 0.88,
                fitScore: 77, fitStatus: .succeeded,
                note: "Job closed — posted for only a week.",
                duplicateOfJobID: nil,
                rawTextBytes: 4100, cleanedTextBytes: 3100
            ),

            SeedJob(
                capId: "fixture_cap_032", jobId: "fixture_job_032", jobNum: 1032,
                url: "https://www.linkedin.com/jobs/view/fixture-032",
                pageTitle: "Senior TPM, Developer Tools · JetBrains",
                company: "JetBrains", title: "Senior Technical Program Manager, Developer Tools",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 170_000, salaryMax: 220_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .closed,
                summary: "Lead developer tools program delivery at JetBrains across IDE and CI/CD products.",
                requirements: "5+ years TPM. Developer tools or IDE experience preferred.",
                skills: ["developer tools", "IDE", "CI/CD", "program management"],
                capturedAt: daysAgo(65), extractedAt: daysAgo(65),
                extractionStatus: .succeeded, extractionConfidence: 0.78,
                fitScore: nil, fitStatus: .none,
                note: "Job closed before I could apply.",
                duplicateOfJobID: nil,
                rawTextBytes: 3300, cleanedTextBytes: 2500
            ),

            // ── .expired × 4 (dead URLs) ─────────────────────────────────────────────
            SeedJob(
                capId: "fixture_cap_033", jobId: "fixture_job_033", jobNum: 1033,
                url: "https://jobs.example-defunct.com/posting/expired-001",
                pageTitle: "Senior TPM · Unknown Startup",
                company: "Acme Corp", title: "Senior Technical Program Manager",
                location: "Remote", remoteType: .remote,
                salaryMin: 180_000, salaryMax: 230_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .expired,
                summary: "Lead platform programs at Acme Corp's infrastructure team. Drive cross-functional delivery with engineering and product.",
                requirements: "5+ years TPM. Platform background preferred.",
                skills: ["platform", "program management"],
                capturedAt: daysAgo(120), extractedAt: daysAgo(120),
                extractionStatus: .succeeded, extractionConfidence: 0.70,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 2900, cleanedTextBytes: 2200
            ),

            SeedJob(
                capId: "fixture_cap_034", jobId: "fixture_job_034", jobNum: 1034,
                url: "https://jobs.example-defunct.com/posting/expired-002",
                pageTitle: "Principal TPM · TechCo",
                company: "TechCo Inc", title: "Principal Technical Program Manager",
                location: "Austin, TX", remoteType: .hybrid,
                salaryMin: 195_000, salaryMax: 250_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "principal",
                status: .expired,
                summary: "Lead infrastructure and reliability programs at TechCo. Own executive communication for critical platform initiatives.",
                requirements: "8+ years TPM. Cloud or infrastructure background preferred.",
                skills: ["infrastructure", "reliability", "program management"],
                capturedAt: daysAgo(115), extractedAt: daysAgo(115),
                extractionStatus: .succeeded, extractionConfidence: 0.73,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3000, cleanedTextBytes: 2300
            ),

            SeedJob(
                capId: "fixture_cap_035", jobId: "fixture_job_035", jobNum: 1035,
                url: "https://jobs.example-defunct.com/posting/expired-003",
                pageTitle: "Staff TPM · BuildCo",
                company: "BuildCo", title: "Staff Technical Program Manager",
                location: "Denver, CO", remoteType: .hybrid,
                salaryMin: 200_000, salaryMax: 255_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .expired,
                summary: "Drive platform and developer experience programs at BuildCo. Coordinate across CI/CD, tooling, and infra teams.",
                requirements: "6+ years TPM. Developer tooling or CI/CD background preferred.",
                skills: ["CI/CD", "developer experience", "program management"],
                capturedAt: daysAgo(110), extractedAt: daysAgo(110),
                extractionStatus: .succeeded, extractionConfidence: 0.68,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 2800, cleanedTextBytes: 2100
            ),

            SeedJob(
                capId: "fixture_cap_036", jobId: "fixture_job_036", jobNum: 1036,
                url: "https://jobs.example-defunct.com/posting/expired-004",
                pageTitle: "Senior TPM · DataCorp",
                company: "DataCorp", title: "Senior Technical Program Manager",
                location: "Chicago, IL", remoteType: .onsite,
                salaryMin: 165_000, salaryMax: 210_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .expired,
                summary: "Manage data platform programs at DataCorp. Drive delivery across data engineering and analytics engineering teams.",
                requirements: "5+ years TPM. Data engineering or analytics background preferred.",
                skills: ["data platform", "analytics", "program management"],
                capturedAt: daysAgo(105), extractedAt: daysAgo(105),
                extractionStatus: .succeeded, extractionConfidence: 0.65,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 2700, cleanedTextBytes: 2000
            ),

            // ── extractionStatus: .pending × 2 (triggers extractionPending DQ) ───────
            SeedJob(
                capId: "fixture_cap_037", jobId: "fixture_job_037", jobNum: 1037,
                url: "https://www.linkedin.com/jobs/view/fixture-037",
                pageTitle: "Senior TPM · Wix",
                company: "Wix", title: "Senior Technical Program Manager",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: nil, salaryMax: nil, salaryCurrency: "USD",
                employmentType: nil, seniority: nil,
                status: .new,
                summary: nil, requirements: nil, skills: [],
                capturedAt: daysAgo(0.5), extractedAt: nil,
                extractionStatus: .pending, extractionConfidence: nil,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3500, cleanedTextBytes: 2600
            ),

            SeedJob(
                capId: "fixture_cap_038", jobId: "fixture_job_038", jobNum: 1038,
                url: "https://jobs.lever.co/square/tpm-payments-038",
                pageTitle: "Staff TPM, Payments · Block (Square)",
                company: "Block", title: "Staff Technical Program Manager, Payments",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: nil, salaryMax: nil, salaryCurrency: "USD",
                employmentType: nil, seniority: nil,
                status: .new,
                summary: nil, requirements: nil, skills: [],
                capturedAt: daysAgo(0.25), extractedAt: nil,
                extractionStatus: .pending, extractionConfidence: nil,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 4100, cleanedTextBytes: 3000
            ),

            // ── extractionStatus: .failed × 2 (triggers extractionFailed DQ) ─────────
            SeedJob(
                capId: "fixture_cap_039", jobId: "fixture_job_039", jobNum: 1039,
                url: "https://www.linkedin.com/jobs/view/fixture-039",
                pageTitle: "TPM · InternalCorp",
                company: nil, title: nil,
                location: nil, remoteType: nil,
                salaryMin: nil, salaryMax: nil, salaryCurrency: "USD",
                employmentType: nil, seniority: nil,
                status: .new,
                summary: nil, requirements: nil, skills: [],
                capturedAt: daysAgo(3), extractedAt: daysAgo(3),
                extractionStatus: .failed, extractionConfidence: nil,
                fitScore: nil, fitStatus: .none,
                note: "Extraction failed — page may require login.",
                duplicateOfJobID: nil,
                rawTextBytes: 800, cleanedTextBytes: 400
            ),

            SeedJob(
                capId: "fixture_cap_040", jobId: "fixture_job_040", jobNum: 1040,
                url: "https://careers.oracle.com/tpm-cloud-040",
                pageTitle: "Cloud TPM · Oracle",
                company: nil, title: nil,
                location: nil, remoteType: nil,
                salaryMin: nil, salaryMax: nil, salaryCurrency: "USD",
                employmentType: nil, seniority: nil,
                status: .pursuing,
                summary: nil, requirements: nil, skills: [],
                capturedAt: daysAgo(5), extractedAt: daysAgo(5),
                extractionStatus: .failed, extractionConfidence: nil,
                fitScore: nil, fitStatus: .none,
                note: "Extraction failed — Oracle careers page is heavily JS-gated.",
                duplicateOfJobID: nil,
                rawTextBytes: 600, cleanedTextBytes: 300
            ),

            // ── Low confidence × 2 (extractionConfidence: 0.45, triggers lowConfidence) ─
            SeedJob(
                capId: "fixture_cap_041", jobId: "fixture_job_041", jobNum: 1041,
                url: "https://www.indeed.com/viewjob?jk=fixture041",
                pageTitle: "Technical Program Manager · Indeed Posting",
                company: "Accenture", title: "Technical Program Manager",
                location: "Chicago, IL", remoteType: .hybrid,
                salaryMin: 150_000, salaryMax: 190_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "mid",
                status: .new,
                summary: "Drive program delivery for Accenture's federal and commercial cloud migration programs. Coordinate across engineering, consulting, and delivery teams.",
                requirements: "4+ years TPM. Consulting or systems integration background.",
                skills: ["cloud migration", "consulting", "program management"],
                capturedAt: daysAgo(2), extractedAt: daysAgo(2),
                extractionStatus: .succeeded, extractionConfidence: 0.45,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 2200, cleanedTextBytes: 1600
            ),

            SeedJob(
                capId: "fixture_cap_042", jobId: "fixture_job_042", jobNum: 1042,
                url: "https://www.glassdoor.com/job-listing/fixture-042",
                pageTitle: "Senior Technical Program Manager · Unknown",
                company: "BizTech Solutions", title: "Senior Technical Program Manager",
                location: "Dallas, TX", remoteType: .hybrid,
                salaryMin: 155_000, salaryMax: 195_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .pursuing,
                summary: "Lead enterprise technology programs at BizTech. Own delivery of ERP and CRM migration initiatives for Fortune 500 clients.",
                requirements: "5+ years TPM or project management. ERP or CRM implementation experience.",
                skills: ["ERP", "CRM", "enterprise", "program management"],
                capturedAt: daysAgo(4), extractedAt: daysAgo(4),
                extractionStatus: .succeeded, extractionConfidence: 0.45,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 2400, cleanedTextBytes: 1800
            ),

            // ── Duplicates — Group 1: same sourceURL, .new + .new ────────────────────
            // Primary: fixture_job_043
            SeedJob(
                capId: "fixture_cap_043", jobId: "fixture_job_043", jobNum: 1043,
                url: "https://boards.greenhouse.io/coinbase/jobs/tpm-wallet-shared",
                pageTitle: "Senior TPM, Wallet · Coinbase",
                company: "Coinbase", title: "Senior Technical Program Manager, Wallet",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 200_000, salaryMax: 260_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .new,
                summary: "Drive wallet and custody programs at Coinbase. Coordinate across blockchain engineering and product.",
                requirements: "5+ years TPM. Fintech or crypto experience preferred.",
                skills: ["crypto", "wallet", "fintech", "program management"],
                capturedAt: daysAgo(3), extractedAt: daysAgo(3),
                extractionStatus: .succeeded, extractionConfidence: 0.88,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 3800, cleanedTextBytes: 2900
            ),

            // Duplicate of 043 — same URL captured again
            SeedJob(
                capId: "fixture_cap_044", jobId: "fixture_job_044", jobNum: 1044,
                url: "https://boards.greenhouse.io/coinbase/jobs/tpm-wallet-shared",
                pageTitle: "Senior TPM, Wallet · Coinbase",
                company: "Coinbase", title: "Senior Technical Program Manager, Wallet",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 200_000, salaryMax: 260_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .new,
                summary: "Drive wallet and custody programs at Coinbase.",
                requirements: "5+ years TPM. Fintech or crypto experience preferred.",
                skills: ["crypto", "wallet", "program management"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, extractionConfidence: 0.85,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: "fixture_job_043",
                rawTextBytes: 3500, cleanedTextBytes: 2700
            ),

            // ── Duplicates — Group 2: near-identical title + same company, .pursuing ──
            // Primary: fixture_job_045
            SeedJob(
                capId: "fixture_cap_045", jobId: "fixture_job_045", jobNum: 1045,
                url: "https://careers.google.com/jobs/results/fixture-045",
                pageTitle: "Staff TPM, Developer Products · Google",
                company: "Google", title: "Staff Technical Program Manager, Developer Products",
                location: "Mountain View, CA", remoteType: .hybrid,
                salaryMin: 230_000, salaryMax: 315_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .pursuing,
                summary: "Lead developer product programs at Google, spanning APIs, SDKs, and developer experience tooling.",
                requirements: "8+ years TPM. Developer tools or API platform experience.",
                skills: ["developer tools", "APIs", "program management"],
                capturedAt: daysAgo(6), extractedAt: daysAgo(6),
                extractionStatus: .succeeded, extractionConfidence: 0.91,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: nil,
                rawTextBytes: 4500, cleanedTextBytes: 3400
            ),

            // Near-duplicate of 045 — same company, nearly same title
            SeedJob(
                capId: "fixture_cap_046", jobId: "fixture_job_046", jobNum: 1046,
                url: "https://careers.google.com/jobs/results/fixture-046",
                pageTitle: "Staff TPM, Developer Platforms · Google",
                company: "Google", title: "Staff Technical Program Manager, Developer Platforms",
                location: "Sunnyvale, CA", remoteType: .hybrid,
                salaryMin: 230_000, salaryMax: 315_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "staff",
                status: .pursuing,
                summary: "Drive developer platform programs at Google, including API lifecycle and SDK tooling.",
                requirements: "8+ years TPM. Developer platform background.",
                skills: ["developer platforms", "APIs", "program management"],
                capturedAt: daysAgo(4), extractedAt: daysAgo(4),
                extractionStatus: .succeeded, extractionConfidence: 0.89,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: "fixture_job_045",
                rawTextBytes: 4200, cleanedTextBytes: 3100
            ),

            // ── Duplicates — Group 3: .applied + .new, same company + role ───────────
            // Primary: fixture_job_047 (.applied)
            SeedJob(
                capId: "fixture_cap_047", jobId: "fixture_job_047", jobNum: 1047,
                url: "https://jobs.ashbyhq.com/vercel/tpm-platform-047",
                pageTitle: "Senior TPM, Platform · Vercel",
                company: "Vercel", title: "Senior Technical Program Manager, Platform",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 195_000, salaryMax: 255_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .applied,
                summary: "Drive platform programs at Vercel including Edge Network, Build infrastructure, and developer experience.",
                requirements: "5+ years TPM. Frontend infrastructure or developer platform experience.",
                skills: ["edge network", "build systems", "developer experience", "program management"],
                capturedAt: daysAgo(10), extractedAt: daysAgo(10),
                extractionStatus: .succeeded, extractionConfidence: 0.90,
                fitScore: 82, fitStatus: .succeeded,
                note: "Applied directly via Vercel careers site.",
                duplicateOfJobID: nil,
                rawTextBytes: 4000, cleanedTextBytes: 3000
            ),

            // Duplicate of 047 — same company and role, captured fresh
            SeedJob(
                capId: "fixture_cap_048", jobId: "fixture_job_048", jobNum: 1048,
                url: "https://www.linkedin.com/jobs/view/fixture-048-vercel",
                pageTitle: "Senior Technical Program Manager, Platform · Vercel",
                company: "Vercel", title: "Senior Technical Program Manager, Platform",
                location: "Remote - USA", remoteType: .remote,
                salaryMin: 195_000, salaryMax: 255_000, salaryCurrency: "USD",
                employmentType: "full_time", seniority: "senior",
                status: .new,
                summary: "Drive platform programs at Vercel across Edge Network, Build, and developer experience.",
                requirements: "5+ years TPM. Developer platform experience.",
                skills: ["edge network", "developer platform", "program management"],
                capturedAt: daysAgo(1), extractedAt: daysAgo(1),
                extractionStatus: .succeeded, extractionConfidence: 0.87,
                fitScore: nil, fitStatus: .none,
                note: nil, duplicateOfJobID: "fixture_job_047",
                rawTextBytes: 3700, cleanedTextBytes: 2800
            )
        ]

        // MARK: - Insert jobs + captures + events

        var jobObjectsByID: [String: Job] = [:]

        for seed in jobs {
            let visibleText = [seed.title, seed.company, seed.location, seed.summary, seed.requirements]
                .compactMap(\.self)
                .joined(separator: "\n")

            let rawHash = "fixture_hash_\(seed.capId)"
            let cleanedHash = seed.duplicateOfJobID != nil
                ? "fixture_dhash_dup_\(seed.duplicateOfJobID!)"
                : "fixture_chash_\(seed.capId)"

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

            let extractedJSON: String? = makeFixtureExtractedJSON(
                extractionStatus: seed.extractionStatus,
                title: seed.title, company: seed.company,
                location: seed.location, remoteType: seed.remoteType,
                salaryMin: seed.salaryMin, salaryMax: seed.salaryMax,
                salaryCurrency: seed.salaryCurrency,
                employmentType: seed.employmentType, seniority: seed.seniority,
                summary: seed.summary, requirements: seed.requirements,
                skills: seed.skills, url: seed.url,
                confidence: seed.extractionConfidence ?? 0.92
            )
            let fitScoreJSON: String? = makeFixtureFitScoreJSON(fitScore: seed.fitScore)

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
                salaryNote: fixturesSalaryNote(min: seed.salaryMin, max: seed.salaryMax),
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
                extractionConfidence: seed.extractionConfidence,
                createdAt: seed.capturedAt,
                updatedAt: seed.capturedAt
            )
            job.capture = capture
            if let rawBytes = seed.rawTextBytes { job.rawTextBytes = rawBytes }
            if let cleanedBytes = seed.cleanedTextBytes { job.cleanedTextBytes = cleanedBytes }
            job.capturedAtDenormalized = seed.capturedAt

            // Note event
            if let note = seed.note {
                let noteEvent = JobEvent(
                    id: "fixture_evt_note_\(seed.jobId)",
                    eventType: "note",
                    note: note,
                    occurredAt: seed.capturedAt,
                    createdAt: seed.capturedAt
                )
                job.events.append(noteEvent)
                modelContext.insert(noteEvent)
            }

            // Status change event for non-pursuing/new jobs
            if seed.status != .pursuing, seed.status != .new {
                let statusAt = seed.capturedAt.addingTimeInterval(2 * 86400)
                let statusEvent = JobEvent(
                    id: "fixture_evt_status_\(seed.jobId)",
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
            jobObjectsByID[seed.jobId] = job
        }

        // MARK: - JobActions

        // Overdue #1 — on fixture_job_018 (Scale AI, interview) — pending follow-up, due yesterday
        if let job018 = jobObjectsByID["fixture_job_018"] {
            let overdueAction1 = JobAction(
                id: "fixture_action_001",
                note: "Follow up with recruiter about loop scheduling",
                dueDate: daysAgo(1),
                completedAt: nil,
                createdAt: daysAgo(3),
                updatedAt: daysAgo(3)
            )
            overdueAction1.job = job018
            modelContext.insert(overdueAction1)
        }

        // Overdue #2 — on fixture_job_012 (Snap, applied 30 days) — follow-up overdue
        if let job012 = jobObjectsByID["fixture_job_012"] {
            let overdueAction2 = JobAction(
                id: "fixture_action_002",
                note: "Send follow-up email to Snap recruiter",
                dueDate: daysAgo(5),
                completedAt: nil,
                createdAt: daysAgo(10),
                updatedAt: daysAgo(10)
            )
            overdueAction2.job = job012
            modelContext.insert(overdueAction2)
        }

        // Upcoming — on fixture_job_016 (Anthropic, interview) — prep session in 7 days
        if let job016 = jobObjectsByID["fixture_job_016"] {
            let upcomingAction = JobAction(
                id: "fixture_action_003",
                note: "Prepare for Anthropic onsite — system design + behavioral",
                dueDate: daysFromNow(7),
                completedAt: nil,
                createdAt: daysAgo(2),
                updatedAt: daysAgo(2)
            )
            upcomingAction.job = job016
            modelContext.insert(upcomingAction)
        }

        // Completed #1 — on fixture_job_001 (Stripe, new)
        if let job001 = jobObjectsByID["fixture_job_001"] {
            let completedAction1 = JobAction(
                id: "fixture_action_004",
                note: "Research Stripe's engineering blog and recent infrastructure talks",
                dueDate: daysAgo(3),
                completedAt: daysAgo(2),
                createdAt: daysAgo(5),
                updatedAt: daysAgo(2)
            )
            completedAction1.job = job001
            modelContext.insert(completedAction1)
        }

        // Completed #2 — on fixture_job_017 (Google, interview)
        if let job017 = jobObjectsByID["fixture_job_017"] {
            let completedAction2 = JobAction(
                id: "fixture_action_005",
                note: "Complete Google's online assessment module",
                dueDate: daysAgo(7),
                completedAt: daysAgo(6),
                createdAt: daysAgo(10),
                updatedAt: daysAgo(6)
            )
            completedAction2.job = job017
            modelContext.insert(completedAction2)
        }

        // Completed #3 — on fixture_job_019 (Stripe, offer)
        if let job019 = jobObjectsByID["fixture_job_019"] {
            let completedAction3 = JobAction(
                id: "fixture_action_006",
                note: "Request written offer letter and review comp package",
                dueDate: daysAgo(4),
                completedAt: daysAgo(3),
                createdAt: daysAgo(6),
                updatedAt: daysAgo(3)
            )
            completedAction3.job = job019
            modelContext.insert(completedAction3)
        }

        // MARK: - Sites

        let siteReviewedAt = daysAgo(5)
        let siteNextReview = daysFromNow(9)

        let sitesData: [(id: String, url: String, origin: String, title: String, interval: Int)] = [
            (
                "fixture_site_001",
                "https://www.linkedin.com/jobs/search/?keywords=technical+program+manager&f_WT=2&f_E=4%2C5",
                "https://www.linkedin.com",
                "LinkedIn — Senior/Staff TPM Remote",
                7
            ),
            (
                "fixture_site_002",
                "https://boards.greenhouse.io/",
                "https://boards.greenhouse.io",
                "Greenhouse Job Boards",
                14
            ),
            (
                "fixture_site_003",
                "https://jobs.ashbyhq.com/",
                "https://jobs.ashbyhq.com",
                "Ashby Job Boards",
                14
            ),
            (
                "fixture_site_004",
                "https://jobs.lever.co/",
                "https://jobs.lever.co",
                "Lever Job Boards",
                14
            ),
            (
                "fixture_site_005",
                "https://jobs.example-defunct.com/",
                "https://jobs.example-defunct.com",
                "Defunct Job Board (404)",
                30
            )
        ]

        for siteData in sitesData {
            let site = Site(
                id: siteData.id,
                origin: siteData.origin,
                url: siteData.url,
                pageTitle: siteData.title,
                intervalDays: siteData.interval,
                lastReviewedAt: siteReviewedAt,
                nextReviewAt: siteNextReview,
                state: .reviewed,
                addedAt: siteReviewedAt,
                createdAt: siteReviewedAt,
                updatedAt: siteReviewedAt
            )
            modelContext.insert(site)
        }

        // MARK: - SavedSearches

        let savedSearches: [SavedSearch] = [
            {
                let s = SavedSearch(
                    name: "Active Pipeline",
                    sortOrder: 0,
                    statusFilterRaw: [
                        JobStatus.new.rawValue,
                        JobStatus.pursuing.rawValue,
                        JobStatus.applied.rawValue,
                        JobStatus.interview.rawValue,
                        JobStatus.offer.rawValue
                    ],
                    sortKeyRaw: "capturedAt",
                    sortAscending: false
                )
                return s
            }(),
            {
                let s = SavedSearch(
                    name: "Remote Only — High Fit",
                    sortOrder: 1,
                    statusFilterRaw: [],
                    remoteFilterRaw: [RemoteType.remote.rawValue],
                    searchText: "",
                    minFitScore: 80,
                    sortKeyRaw: "fitScore",
                    sortAscending: false
                )
                return s
            }(),
            {
                let s = SavedSearch(
                    name: "Needs Action — Applied",
                    sortOrder: 2,
                    statusFilterRaw: [JobStatus.applied.rawValue],
                    sortKeyRaw: "capturedAt",
                    sortAscending: true
                )
                return s
            }()
        ]

        for search in savedSearches {
            modelContext.insert(search)
        }

        try modelContext.save()
    }

    // MARK: - JSON builders (private)

    // swiftlint:disable:next function_parameter_count
    private func makeFixtureExtractedJSON(
        extractionStatus: ExtractionStatus,
        title: String?, company: String?, location: String?, remoteType: RemoteType?,
        salaryMin: Int?, salaryMax: Int?, salaryCurrency: String,
        employmentType: String?, seniority: String?, summary: String?,
        requirements: String?, skills: [String], url: String,
        confidence: Double
    ) -> String? {
        guard extractionStatus == .succeeded, title != nil else { return nil }
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
            "confidence": confidence
        ]
        if let min = salaryMin, let max = salaryMax {
            dict["salary_note"] = "$\(min / 1000)K–$\(max / 1000)K"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func makeFixtureFitScoreJSON(fitScore: Int?) -> String? {
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

    private func fixturesSalaryNote(min: Int?, max: Int?) -> String? {
        guard let min, let max else { return nil }
        return "$\(min / 1000)K–$\(max / 1000)K"
    }
}

// swiftlint:enable line_length file_length function_body_length large_tuple
