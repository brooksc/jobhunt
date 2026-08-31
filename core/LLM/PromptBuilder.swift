// swiftlint:disable line_length
import Foundation

// MARK: - PromptBuilder

/// Builds system + user chat messages for extraction and fit-score prompts.
/// Mirrors server/extract.js systemPrompt(), userPrompt(), fitSystemPrompt(), fitUserPrompt().
public enum PromptBuilder {
    // MARK: - Extraction prompt

    /// Build messages for job-extraction LLM call.
    /// - Parameters:
    ///   - description: Raw job description text (will be truncated to LLMConstants.maxDescriptionChars).
    ///   - url: Canonical or page URL.
    ///   - pageTitle: Page title from the capture.
    ///   - locationContext: Optional `LocationContext` for location-preference rules.
    ///   - boardLocation: The ATS board row's own structured location field, when the capture came
    ///     from discovery. Nil for extension / MCP captures, which keeps their prompt byte-identical
    ///     to the pre-TASK-693 one.
    public static func buildExtractionPrompt(
        description: String,
        url: String,
        pageTitle: String,
        locationContext: LocationContext = .none,
        boardLocation: String? = nil
    ) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: systemPrompt()),
            ChatMessage(role: "user", content: userPrompt(
                description: description,
                url: url,
                pageTitle: pageTitle,
                locationContext: locationContext,
                boardLocation: boardLocation
            ))
        ]
    }

    /// Build messages for fit-score LLM call.
    /// - Parameters:
    ///   - extractedJob: The parsed extraction result (title, company, requirements, etc.).
    ///   - resumeText: Full resume text (will be truncated to LLMConstants.maxResumeChars).
    public static func buildFitPrompt(
        extractedJob: ExtractedJobContext,
        resumeText: String
    ) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: fitSystemPrompt()),
            ChatMessage(role: "user", content: fitUserPrompt(
                extractedJob: extractedJob,
                resumeText: resumeText
            ))
        ]
    }

    // MARK: - Overhead measurement

    /// Returns the number of chars in an empty extraction + fit prompt (overhead above JD / resume).
    public static func promptOverheadChars(locationContext: LocationContext = .none)
        -> (extractChars: Int, fitChars: Int) {
        let extractChars = systemPrompt().count +
            userPrompt(description: "", url: "", pageTitle: "", locationContext: locationContext).count
        let fitChars = fitSystemPrompt().count +
            fitUserPrompt(extractedJob: ExtractedJobContext(), resumeText: "").count
        return (extractChars, fitChars)
    }

    // MARK: - Private prompt builders

    static func systemPrompt() -> String {
        "You extract structured job posting data. Return only one valid JSON object. Do not include markdown, commentary, or guessed values. If a field is not present in the source, use null for scalar fields and [] for list fields."
    }

    static func userPrompt(
        description: String,
        url: String,
        pageTitle: String,
        locationContext: LocationContext,
        boardLocation: String? = nil
    ) -> String {
        let locationRules = """

        Location and remote_type rules:
        - Set location to the raw location(s) listed in the posting (city, state, region, or "Multiple Locations").
        - Infer remote_type from the work arrangement, NOT the location field:
          - "remote" → posting says remote, WFH, work from home, 0 days in office, fully remote, telecommute.
          - "hybrid" → posting specifies a mix (e.g. "2 days/week in office", "hybrid").
          - "onsite" → posting requires in-person / in-office with no remote option.
          - "unknown" → no work arrangement information found.
        - Examples: "Work site 0 days/week in-office – remote" → remote_type="remote". "Work site 3 days/week in-office" → remote_type="hybrid".
        """
        let locationPrefRules = locationPreferencePrompt(locationContext)
        let boardLocationRules = boardLocationPrompt(boardLocation)
        let truncated = String(description.prefix(LLMConstants.maxDescriptionChars))

        return """
        Extract job information from the posting below.

        Return JSON with exactly these keys:
        - company: string or null
        - title: string or null
        - location: string or null
        - remote_type: one of "remote", "hybrid", "onsite", "unknown"
        - salary_min: integer or null
        - salary_max: integer or null
        - salary_hourly_min: number or null
        - salary_hourly_max: number or null
        - salary_currency: string or null
        - salary_note: string or null
        - employment_type: one of "full_time", "part_time", "contract", "internship", "temporary", "unknown"
        - seniority: one of \(SeniorityLevel
            .promptList), or null — the LEVEL, not the years. Use null when the posting states only an experience range ("5+ years") or a bare grade ("III"), which carry no level on their own.
        - skills: array of strings
        - summary: string or null
        - requirements: array of strings
        - nice_to_haves: array of strings
        - benefits: array of strings
        - application_url: string or null
        - application_instructions: string or null — verbatim text of any explicit submission instructions the posting gives about HOW to apply (e.g. "include phrase X at the top of your resume", "submit via this link", "include your salary expectations"). These are submission mechanics, NOT job qualifications. Null when no special submission instructions are present.
        - confidence: a single number from 0 to 1 — your overall confidence in this extraction

        Salary rules:
        - ALWAYS extract salary_min and salary_max when any numeric pay range appears in the posting.
        - Retirement/benefit plan names are NOT pay: "401k", "401(k)", "403(b)", "457(b)", "529", "RRSP", "pension" — never read the number in these as a salary. If the only numbers in the posting are benefit-plan names, leave salary_min, salary_max and salary_note null.
        - If hourly pay appears, extract the raw hourly rate range into salary_hourly_min and salary_hourly_max.
        - Store values as annual integers (e.g. 119800, not "119,800" or "$119,800").
        - Some job boards (e.g. Workday) express annual salary without a $ sign: "133,400 - 226,600 USD Annual". Treat these as annual USD amounts.
        - If the posting lists an hourly rate, convert to annual using exactly 2,080 hours/year:
          hourly × 40 hours/week × 52 weeks/year = hourly × 2080.
          Do not subtract holidays, PTO, unpaid time, or use any other annual-hours estimate.
          Examples: $75/hr → salary_min=156000; $75–$95/hr → salary_min=156000, salary_max=197600.
          Example: $85/hr–$105/hr → salary_min=176800, salary_max=218400.
        - When the posting lists multiple annual salary bands, include all salary bands in salary_note.
          The application verifies salary_min/salary_max from salary_note and uses the lowest and highest salary values found there.
        - When multiple bands exist for seniority or job family (not location), use the absolute lowest/highest.
        - Always put the original salary text in salary_note, including any location-specific bands omitted from salary_min/max.
        - If salary bands differ by location, preserve each location label with its range in salary_note, such as "WA: $205,000-$216,500 USD".
        - If salary bands differ by currency, preserve each currency label and range in salary_note; do not combine currencies into one range.

        List extraction rules:
        - Extract every distinct concrete skill, technology, tool, or domain named anywhere in the posting (responsibilities, requirements, role scope, and team/charter description), even when there is no "Skills" heading. Aim for completeness (typically 6-15); do not stop at a handful. Do not invent skills that are not in the posting.
        - Extract hard requirements into requirements. If the posting lists qualifications without separating "required" from "preferred" (e.g. a single "What we're looking for", "Qualifications", or "Minimum qualifications" list), treat every bullet in that list as a requirement and capture them all.
        - Extract preferred qualifications and useful background signals into nice_to_haves. When the posting has no explicit "Preferred" or "Nice to have" section, mine the responsibilities, role summary, and required qualifications for domain signals: technologies, industry verticals, cross-functional partner teams (e.g. "engineering, design, research"), and products or platforms mentioned as context. Even a single mention is enough — nice_to_haves must not be empty when the posting names any relevant domain, partner, product, or technology.
        - Do NOT record statements about cultural fit or alignment with the company's values, mission, or principles (e.g. "Alignment with Acme's core values", "Embodies our culture", "Passion for our mission") as requirements or nice_to_haves. They describe a disposition the posting cannot define and a resume cannot evidence, so they are not qualifications. Concrete requirements that merely sound soft — communication, leadership, mentoring, stakeholder management — ARE qualifications; keep those.
        - Some boards state the work arrangement as days in the office rather than the word remote/hybrid/onsite (e.g. "Work site: 0 days / week in-office" = remote, "2 days / week in-office" = hybrid, "5 days / week in-office" = onsite). Read remote_type from that phrasing when it appears.
        - COMPOUND REQUIREMENTS: when one bullet asks for two or more DISTINCT capabilities that a candidate could satisfy independently, record each as its own requirement. "Working and driving strategic programs and building a remote-friendly culture" is two requirements — someone can do the first without the second, and collapsing them hides which one is missing. Do NOT split in these two cases: (a) alternatives, where any one suffices — "Bachelor's in Computer Science, Electrical Engineering, or equivalent practical experience" and "experience in one or more of the following: X, Y, Z" are each a SINGLE requirement, and splitting them would invent gaps the posting never asked for; (b) a list of examples, teams, tools or domains that merely qualifies one capability — "stakeholder management with Engineering, Product, Design and Analytics" is one requirement, not four. The test is whether the parts could be independently met or missed.
        - Use concise noun phrases copied or closely paraphrased from the posting.
        \(locationRules)
        \(locationPrefRules)\(boardLocationRules)
        Known metadata:
        URL: \(url)
        Page title: \(pageTitle)

        Job description:
        \(truncated)
        """
    }

    /// The board row's own location field, offered to the model as authoritative-but-checkable
    /// evidence (TASK-693).
    ///
    /// Emitted ONLY when a board location exists, so an extension or MCP capture — which has none —
    /// produces byte-for-byte the prompt it produced before this existed.
    ///
    /// It is a hint rather than a substitution because a measured comparison of 613 discovery jobs
    /// found the board value is not uniformly better: it is right where extraction found nothing,
    /// harmless where it is merely a longer form of the same place, and *worse* on ~63 rows where it
    /// says only "United States" or names an office for a role the body states is remote. Only the
    /// body can settle "or remote", "West Coast preferred" and Workday's arrangement breadcrumbs, so
    /// the reconciliation is left to the model and the deterministic fill is confined to the empty case.
    static func boardLocationPrompt(_ boardLocation: String?) -> String {
        guard let board = boardLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !board.isEmpty else { return "" }
        return """


        Board location field (authoritative unless the body contradicts it):
        - The job board's own structured location field for this posting is: \(board)
        - This is the employer's own statement of where the role sits, and it often does NOT appear in the description body below (it lives in the page header). Use it for location unless the body says something specific and contradictory about THIS role — e.g. the body says the role is remote, or names a different work location for the role itself.
        - A "we have offices in …" paragraph, an office list, or a headquarters address is NOT a contradiction. Never replace the board location with a list of company offices scraped from the prose.
        - Read remote_type from the body's work arrangement as usual. The board field sometimes encodes the arrangement too (e.g. a "Remote" prefix, or Workday's "OffsiteHome"); use that only when the body states no arrangement.
        """
    }

    static func locationPreferencePrompt(_ ctx: LocationContext) -> String {
        let terms = ctx.preferredLocations.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if terms.isEmpty && ctx.allowRemote && ctx.allowHybrid && ctx.allowOnsite {
            return "\nLocation preference context:\n- No location preferences configured. Extract all location/remote values present in the source.\n"
        }
        let termsText = terms.isEmpty ? "No location preference terms." : terms.joined(separator: ", ")
        var allowed: [String] = []
        if ctx.allowRemote { allowed.append("remote") }
        if ctx.allowHybrid { allowed.append("hybrid") }
        if ctx.allowOnsite { allowed.append("onsite") }
        let allowedText = allowed.joined(separator: ", ")
        return """

        Location preference context:
        - Preferred locations: \(termsText)
        - Allowed remote modes: \(allowedText)
        - Keep state abbreviations and city names as they appear in source text (e.g. "WA", "Seattle", "Redmond"), and prefer exact string matches.
        - If the posting has one of the preferred locations, keep that location text and mark remote_type accordingly.
        """
    }

    static func fitSystemPrompt() -> String {
        "You are a recruiting analyst. Compare a candidate's resume against a job posting and judge how well the candidate fits the role. Return only one valid JSON object. Do not include markdown, commentary, or guessed values. Be objective: base scores only on evidence in the resume and the job description."
    }

    static func fitUserPrompt(
        extractedJob: ExtractedJobContext,
        resumeText: String
    ) -> String {
        let fitDimensions = [
            "required_qualifications",
            "preferred_qualifications",
            "skills",
            "experience_level",
            "domain_fit"
        ]
        let fitDimensionGuide: [String: String] = [
            "required_qualifications": "how well the resume satisfies the job's hard requirements / must-haves",
            "preferred_qualifications": "how well the resume satisfies the nice-to-have / preferred qualifications",
            "skills": "overlap between the candidate's skills and the skills the job lists",
            "experience_level": "alignment between the candidate's seniority/years and the role's level",
            "domain_fit": "relevance of the candidate's INDUSTRY and PRODUCT background to this role — the field the company operates in and the kind of thing it builds, NOT how transferable the candidate's craft is. Excellent program management in one industry is not domain fit for another: score domain_fit low when the candidate has not worked in this industry or on this class of product, however strong they are otherwise. The other dimensions already credit transferable skill; do not credit it twice here."
        ]

        func block(_ label: String, _ value: String?) -> String {
            "\(label): \(value ?? "(not specified)")"
        }

        func listBlock(_ label: String, _ items: [String]) -> String {
            if items.isEmpty { return "\(label):\n- (none listed)" }
            return "\(label):\n" + items.map { "- \($0)" }.joined(separator: "\n")
        }

        var jobParts: [String] = [
            block("Title", extractedJob.title),
            block("Company", extractedJob.company),
            block("Seniority", extractedJob.seniority),
            block("Summary", extractedJob.summary),
            listBlock("Required qualifications", extractedJob.requirements),
            listBlock("Preferred / nice-to-have", extractedJob.niceToHaves),
            listBlock("Skills", extractedJob.skills)
        ]
        if let appInstructions = extractedJob.applicationInstructions {
            jobParts
                .append(
                    "Application instructions (submission mechanics — DO NOT factor into scores): \(appInstructions)"
                )
        }

        let jobSection = jobParts.joined(separator: "\n")

        let dimensionLines = fitDimensions.map { name in
            "  - \"\(name)\": \(fitDimensionGuide[name] ?? "")"
        }.joined(separator: "\n")
        let dimensionNames = fitDimensions.map { "\"\($0)\"" }.joined(separator: ", ")
        let truncatedResume = String(resumeText.prefix(LLMConstants.maxResumeChars))

        return """
        Score how well the candidate fits this job.

        IMPORTANT: Application instructions (labeled "submission mechanics" in the job posting below) describe HOW to apply — e.g. "include phrase X at the top of your resume". These are NOT job qualifications. Never include them in requirement_assessments, and never penalize any dimension for the candidate not following them.

        Return JSON with exactly these keys:
        - summary: string — 1-3 sentences explaining the overall fit
        - requirement_assessments: array — assess EVERY qualification listed under "Required qualifications" and "Preferred / nice-to-have" in the job posting below. Output exactly one object per listed qualification: do not skip any, do not merge them, and do not invent qualifications that aren't listed. (This list is the SAME for every candidate scored against this job, so judge each consistently.) Each object has:
          - requirement: the qualification text (verbatim or lightly paraphrased)
          - kind: "required" if the qualification is listed under "Required qualifications", or "preferred" if it is listed under "Preferred / nice-to-have"
          - status: "met" (clear, direct evidence in the resume), "partial" (some or indirect evidence), or "missing" (no clear evidence in the resume)
          - NAMED-TECHNOLOGY RULE: when the qualification names a specific technology, framework, product, certification, standard or regulation (e.g. CUDA, Kubernetes, InfiniBand, Terraform, PCI DSS, SOC 2, ISO 27001, FedRAMP, HIPAA, GDPR), "met" requires the resume to name that same thing or an unambiguous equivalent. Adjacent, analogical or one-layer-removed experience is "partial" at best — working with hardware that runs CUDA is not CUDA expertise, and compliance experience with one regime is not experience with a different named regime. Do not generalise across named things that merely share a domain.
          - The evidence string must quote or closely paraphrase what the resume actually says. Never assert a capability the resume does not state.
          - ALTERNATIVES RULE: when a qualification offers a menu ("A or B or C", "electrical, software, mechanical, or systems") or an escape clause ("or equivalent experience", "or related field"), do NOT simply pick whichever option the candidate happens to satisfy. Judge against the option this POSTING is actually about, inferred from what the rest of the job description emphasises. If the candidate satisfies only a peripheral option while the emphasised one is absent, that is "partial", not "met". A single word inside a parenthetical does not outweigh the role's evident subject matter.
          - evidence: one sentence citing the specific resume evidence, or stating what is absent
          Exclude any submission mechanics.
        - dimensions: array of exactly \(fitDimensions.count) objects, one per dimension, each with:
          - name: one of \(dimensionNames)
          - score: integer 0-100
          - rationale: string — one sentence justifying the score

        Dimensions to evaluate (use these exact names):
        \(dimensionLines)

        Scoring guidance:
        - 0 = no evidence of fit; 50 = partial / mixed fit; 100 = clearly exceeds what the role needs.
        - If the job omits information for a dimension, score conservatively and say so in the rationale.
        - Do not provide an overall score. The application computes it from the dimension scores.
        - In requirement_assessments, judge against the listed qualifications, not generic praise; when evidence is indirect mark "partial", and when there is none mark "missing" (explain what is absent).
        - Application instructions (labeled above as "submission mechanics") describe HOW to apply, not whether the candidate is qualified. Do NOT include them in requirement_assessments. Do NOT penalize any dimension score for them — they can be acted on at application time.
        - Statements about cultural fit or alignment with the company's values, mission, or principles (e.g. "Alignment with Acme's core values") are not assessable from a resume: the posting never defines what would satisfy them, so marking one "missing" says nothing about the candidate. Omit them from requirement_assessments and do NOT let them lower any dimension score. This does not apply to concrete professional qualifications that happen to sound soft (communication, leadership, mentoring, stakeholder management) — assess those normally.

        Job posting:
        \(jobSection)

        Candidate resume:
        \(truncatedResume)
        """
    }
}

// MARK: - Supporting types

/// Location preferences for prompt building.
public struct LocationContext: Sendable {
    public let preferredLocations: String
    /// Where the user may work remotely, when they've said so explicitly.
    public let remoteEligibilityRegions: String
    public let allowRemote: Bool
    public let allowHybrid: Bool
    public let allowOnsite: Bool

    public static let none = LocationContext(
        preferredLocations: "",
        allowRemote: true,
        allowHybrid: true,
        allowOnsite: true
    )

    public init(
        preferredLocations: String = "",
        remoteEligibilityRegions: String = "",
        allowRemote: Bool = true,
        allowHybrid: Bool = true,
        allowOnsite: Bool = true
    ) {
        self.preferredLocations = preferredLocations
        self.remoteEligibilityRegions = remoteEligibilityRegions
        self.allowRemote = allowRemote
        self.allowHybrid = allowHybrid
        self.allowOnsite = allowOnsite
    }
}

/// Job fields needed to build the fit-score prompt.
public struct ExtractedJobContext: Sendable {
    public let title: String?
    public let company: String?
    public let seniority: String?
    public let summary: String?
    public let requirements: [String]
    public let niceToHaves: [String]
    public let skills: [String]
    public let applicationInstructions: String?

    public init(
        title: String? = nil,
        company: String? = nil,
        seniority: String? = nil,
        summary: String? = nil,
        requirements: [String] = [],
        niceToHaves: [String] = [],
        skills: [String] = [],
        applicationInstructions: String? = nil
    ) {
        self.title = title
        self.company = company
        self.seniority = seniority
        self.summary = summary
        self.requirements = requirements
        self.niceToHaves = niceToHaves
        self.skills = skills
        self.applicationInstructions = applicationInstructions
    }

    /// Every piece of posting text the model is shown when scoring fit, as one string.
    ///
    /// Used to tell "the model quoted the job description back at me" from "the model made this up".
    /// It has to be what the model *saw* — checking against the raw captured page would accuse it of
    /// copying text that was never in its context.
    public var quotableText: String {
        ([title, company, seniority, summary, applicationInstructions].compactMap(\.self)
            + requirements + niceToHaves + skills).joined(separator: "\n")
    }
}

// swiftlint:enable line_length function_body_length
