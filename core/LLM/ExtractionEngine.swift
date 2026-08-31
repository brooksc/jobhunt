// swiftlint:disable function_body_length
import Foundation

// MARK: - Sendable snapshots

//
// Callers fetch live SwiftData models, snapshot the needed fields into these structs,
// then pass the snapshots to the engine. The engine never holds a SwiftData model reference.

public struct JobExtractionSnapshot: Sendable {
    public let captureURL: String
    public let captureCanonicalURL: String?
    public let capturePageTitle: String
    public let captureCleanedDescription: String?
    public let captureVisibleText: String?
    public let captureSelectedText: String?
    /// The ATS board row's own location field, when this capture came from discovery (TASK-693).
    /// Nil for extension / MCP / paste captures, which have no board row.
    public let captureBoardLocation: String?

    public init(
        captureURL: String,
        captureCanonicalURL: String?,
        capturePageTitle: String,
        captureCleanedDescription: String?,
        captureVisibleText: String?,
        captureSelectedText: String?,
        captureBoardLocation: String? = nil
    ) {
        self.captureURL = captureURL
        self.captureCanonicalURL = captureCanonicalURL
        self.capturePageTitle = capturePageTitle
        self.captureCleanedDescription = captureCleanedDescription
        self.captureVisibleText = captureVisibleText
        self.captureSelectedText = captureSelectedText
        self.captureBoardLocation = captureBoardLocation
    }
}

public struct JobFitSnapshot: Sendable {
    public let title: String?
    public let company: String?
    public let seniority: String?
    public let extractedJSON: String?
    public let extractionModel: String?

    public init(
        title: String?,
        company: String?,
        seniority: String?,
        extractedJSON: String?,
        extractionModel: String?
    ) {
        self.title = title
        self.company = company
        self.seniority = seniority
        self.extractedJSON = extractedJSON
        self.extractionModel = extractionModel
    }
}

public struct ResumeSnapshot: Sendable {
    public let text: String
    public init(text: String) {
        self.text = text
    }
}

// MARK: - ExtractionResult

public struct ExtractionResult: Sendable {
    public let extractedJSON: String
    public let title: String?
    public let company: String?
    public let location: String?
    public let remoteType: RemoteType?
    public let salaryMin: Int?
    public let salaryMax: Int?
    public let salaryHourlyMin: Double?
    public let salaryHourlyMax: Double?
    public let salaryCurrency: String?
    public let salaryNote: String?
    public let employmentType: String?
    public let seniority: String?
    public let applicationURL: String?
    public let extractionConfidence: Double?
    public let extractionModel: String
    public let promptChars: Int
    public let responseChars: Int
    /// Actual provider-reported token usage when available (TASK-538); nil when the provider doesn't
    /// report usage (char counts are the fallback).
    public let promptTokens: Int?
    public let completionTokens: Int?
    /// Format the provider actually used (may be a downgrade from what was requested) — TASK-454.
    public let responseFormat: ResponseFormat
    /// Whether the job passed the user's location/remote criteria (TASK-464).
    public let meetsCriteria: Bool
}

// MARK: - ExtractionEngine

public enum ExtractionEngine {
    // MARK: - Extract

    /// Extract job fields from a capture via LLM.
    /// Mirrors processRequest (extract path) in server/extract.js.
    public static func extract(
        snapshot: JobExtractionSnapshot,
        provider: any LLMProvider,
        settings: ExtractionSettings
    ) async throws -> ExtractionResult {
        let description = captureText(snapshot)
        guard !description.isEmpty else {
            throw ExtractionEngineError.noCaptureText
        }
        guard !isBlank(settings.llmModel) else {
            throw ExtractionEngineError.noModelSelected
        }

        let url = snapshot.captureCanonicalURL ?? snapshot.captureURL
        let pageTitle = snapshot.capturePageTitle

        let locationContext = LocationContext(
            preferredLocations: settings.preferredLocations,
            remoteEligibilityRegions: settings.remoteEligibilityRegions,
            allowRemote: settings.locationAllowRemote,
            allowHybrid: settings.locationAllowHybrid,
            allowOnsite: settings.locationAllowOnsite
        )

        let messages = PromptBuilder.buildExtractionPrompt(
            description: description,
            url: url,
            pageTitle: pageTitle,
            locationContext: locationContext,
            boardLocation: snapshot.captureBoardLocation
        )

        let promptText = messages.map(\.content).joined()
        let promptChars = promptText.count

        // TASK-461: send a strict json_schema as the preferred format. The OpenAICompatibleTransport
        // ladder falls back to json_object then text on a 400 format rejection; Anthropic already
        // enforces the same schema via `structuredOutput`, and Google treats jsonSchema as JSON mode.
        let extractionSchema = StructuredOutputSchemas.schema(for: .jobExtraction)
        let request = ChatRequest(
            messages: messages, model: settings.llmModel,
            responseFormat: .jsonSchema(name: extractionSchema.name, schema: extractionSchema.schema),
            structuredOutput: .jobExtraction
        )
        let response = try await provider.complete(request)
        let responseChars = response.content.count

        // Carry the VERBATIM model response on any parse failure (repair threw, or repaired to a
        // non-object) so the queue can persist it into the attempt's responsePreview for debugging.
        // The error message stays generic — the raw text is never surfaced in errorDescription.
        let repairedJSON: String
        do {
            repairedJSON = try repairJSON(response.content)
        } catch {
            throw ExtractionEngineError.invalidJSON(response.content)
        }
        guard let data = repairedJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionEngineError.invalidJSON(response.content)
        }

        // TASK-456: validate provider JSON into the typed extraction schema before normalization.
        // Incompatible field shapes throw (retryable) instead of being silently dropped; the rebuilt
        // dict carries the same snake_case keys the normalization pipeline reads. `confidence` is in
        // the schema (a single 0–1 number, TASK-562) but is read leniently outside the throwing DTO —
        // it's a soft hint, so it's preserved verbatim from the raw payload and must never fail
        // extraction (a legacy per-field object is still tolerated by computeConfidence).
        let dto = try ExtractionDTO(raw: raw)
        var extracted: [String: Any?] = dto.asDict()
        if let confidence = raw["confidence"] { extracted["confidence"] = confidence }

        let normalizer = JobFieldNormalizer()
        extracted = normalizer.normalize(
            extracted: extracted,
            // Cap the source fed to the salary regexes to the same bound the prompt uses. The normalizer
            // runs backtracking regexes over this text; an untrusted ~MB capture would otherwise cause
            // quadratic (ReDoS) CPU blowup on the extraction actor (CWE-1333). PromptBuilder already
            // prefixes to this cap for the model; mirror it here (TASK-644 review / F10/F11).
            sourceText: String(description.prefix(LLMConstants.maxDescriptionChars)),
            url: url,
            preferredLocations: settings.locationFilterEnabled ? settings.preferredLocations : nil
        )

        // TASK-693: the board row's own location field, used ONLY to fill a location the model left
        // empty. The posting's location is frequently in the ATS page header rather than the body we
        // capture, so the model never sees it and returns null — job #1524 had a fit of 90 and no
        // location at all, which `LocationCriteria` reads as on-site and badges as failing criteria.
        //
        // Fill only, never overwrite. Across 613 measured jobs the board value wins outright on the
        // 183 rows where extraction produced nothing, and loses ~63-to-20 on the rows where the two
        // genuinely disagree (the board says a bare "United States", or names an office for a role the
        // body states is remote). No mechanical rule separates those, so preferring the board value
        // wholesale would be net-negative; the contested set is left to the prompt hint instead.
        if let board = snapshot.captureBoardLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !board.isEmpty,
           (extracted["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            extracted["location"] = board
        }

        let confidence = computeConfidence(extracted["confidence"])

        let resultJSON = (try? JSONSerialization.data(withJSONObject: extracted.compactMapValues { $0 }))
            .flatMap { String(data: $0, encoding: .utf8) } ?? repairedJSON

        let remoteTypeStr = extracted["remote_type"] as? String
        var remoteType: RemoteType? = remoteTypeStr.flatMap { RemoteType(rawValue: $0) }

        // The model sometimes returns a location that states the arrangement outright ("United States
        // - Remote") while leaving remote_type null. Fill it from the location before it's used for
        // the criteria verdict, or the job reads as on-site (job #525).
        remoteType = RemoteTypeInference.infer(remoteType: remoteType, location: extracted["location"] as? String)

        // TASK-464: compute meets_criteria from the EXTRACTED remote mode (before the clamp below) +
        // location against the user's location/remote settings — Electron parity.
        let meetsCriteria = LocationCriteria.meets(
            remoteType: remoteType,
            location: extracted["location"] as? String,
            preferredLocations: settings.preferredLocations,
            remoteEligibilityRegions: settings.remoteEligibilityRegions,
            allowRemote: settings.locationAllowRemote,
            allowHybrid: settings.locationAllowHybrid,
            allowOnsite: settings.locationAllowOnsite,
            filterEnabled: settings.locationFilterEnabled
        )

        // TASK-270: Clamp remoteType to nil when the user has disallowed that mode.
        // The prompt already asks the LLM to prefer allowed modes, but it can still return
        // a disallowed value. Clear it post-extraction so disallowed modes are never persisted.
        if settings.locationFilterEnabled, let rt = remoteType {
            let allowed =
                (rt == .remote && settings.locationAllowRemote) ||
                (rt == .hybrid && settings.locationAllowHybrid) ||
                (rt == .onsite && settings.locationAllowOnsite) ||
                rt == .unknown
            if !allowed { remoteType = nil }
        }

        return ExtractionResult(
            extractedJSON: resultJSON,
            title: extracted["title"] as? String,
            company: extracted["company"] as? String,
            location: extracted["location"] as? String,
            remoteType: remoteType,
            salaryMin: extracted["salary_min"] as? Int,
            salaryMax: extracted["salary_max"] as? Int,
            salaryHourlyMin: extracted["salary_hourly_min"] as? Double,
            salaryHourlyMax: extracted["salary_hourly_max"] as? Double,
            salaryCurrency: extracted["salary_currency"] as? String,
            salaryNote: extracted["salary_note"] as? String,
            employmentType: extracted["employment_type"] as? String,
            seniority: extracted["seniority"] as? String,
            applicationURL: validatedApplicationURL(extracted["application_url"] as? String),
            extractionConfidence: confidence,
            extractionModel: response.model,
            promptChars: promptChars,
            responseChars: responseChars,
            promptTokens: response.promptTokens,
            completionTokens: response.completionTokens,
            responseFormat: response.responseFormat,
            meetsCriteria: meetsCriteria
        )
    }

    // MARK: - Score Fit

    /// Score job fit against a single resume via LLM.
    /// Mirrors processFitScoreRequest in server/extract.js.
    public static func scoreFit(
        job: JobFitSnapshot,
        resume: ResumeSnapshot,
        model: String,
        provider: any LLMProvider,
        feedback: [ScoringFeedback] = [],
        jobNumber: Int? = nil
    ) async throws -> FitScoreOutput {
        guard !resume.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionEngineError.emptyResumeText
        }
        guard !isBlank(model) else {
            throw ExtractionEngineError.noModelSelected
        }

        let extractedContext = buildJobContext(from: job)
        let messages = PromptBuilder.buildFitPrompt(
            extractedJob: extractedContext,
            resumeText: resume.text
        )

        let promptChars = messages.map(\.content).joined().count

        // TASK-461: strict json_schema (same ladder/fallback as extraction).
        let fitSchema = StructuredOutputSchemas.schema(for: .fitScore)
        let request = ChatRequest(
            messages: messages, model: model,
            responseFormat: .jsonSchema(name: fitSchema.name, schema: fitSchema.schema),
            structuredOutput: .fitScore
        )
        let response = try await provider.complete(request)

        let responseChars = response.content.count

        // Carry the VERBATIM model response on any parse failure (see extract() above) so the queue
        // can persist it for debugging; the error message stays generic.
        let repairedJSON: String
        do {
            repairedJSON = try repairJSON(response.content)
        } catch {
            throw ExtractionEngineError.invalidJSON(response.content)
        }
        guard let data = repairedJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionEngineError.invalidJSON(response.content)
        }

        // TASK-453: validate the exact dimension contract before scoring — a malformed dimensions
        // payload throws (retryable) instead of being stored as a misleading low score.
        let dimensions = try FitScorer.validateDimensions(raw["dimensions"])
        // TASK-602: build the gap list (kind × partial/missing) from the structured per-requirement
        // assessments — this drives the severity-weighted penalty (no more hardware-keyword heuristic).
        // Fall back to the legacy free-form `requirements_not_met` (as missing *required* gaps) for
        // responses that don't send assessments.
        // The model is asked to quote its evidence, and often quotes something the résumé doesn't
        // say — 32% of quoted spans corpus-wide, three-quarters of them lifted verbatim from the
        // posting it was just shown. Checked here, at the one point where both documents are in
        // hand, and the outcome is stamped into the stored JSON so the UI and any later recompute
        // see the same judgement without redoing it.
        let checked = EvidenceCheck.apply(
            to: (raw["requirement_assessments"] as? [[String: Any]]) ?? [],
            resumes: [resume.text],
            // What the model was actually shown of the posting. Using the raw capture instead would
            // credit it with copying text it never saw.
            posting: extractedContext.quotableText
        )
        let assessments = checked.assessments
        let gaps: [FitScorer.RequirementGap]
        let counts: FitScorer.RequirementCounts?
        if assessments.isEmpty {
            let legacy = (raw["requirements_not_met"] as? [Any])?.compactMap { $0 as? String } ?? []
            gaps = legacy.map { .init(requirement: $0, kind: .required, status: .missing) }
            counts = nil
        } else {
            gaps = FitScorer.requirementGaps(
                fromAssessments: assessments, feedback: feedback, jobNumber: jobNumber
            )
            counts = FitScorer.requirementCounts(
                fromAssessments: assessments, feedback: feedback, jobNumber: jobNumber
            )
        }

        let score = FitScorer.computeScore(dimensions: dimensions, gaps: gaps, counts: counts)
        // A live scoring call IS a fresh assessment, so stamp the current prompt version. Recompute
        // takes the other branch and preserves whatever the score was originally assessed under.
        var stamped = raw
        stamped["assessment_prompt_version"] = FitScorer.assessmentPromptVersion
        // Persist the checked assessments, not the model's originals — otherwise the score reflects a
        // demotion the stored explanation doesn't show, which is the score/rows disagreement this app
        // has already shipped once.
        if !assessments.isEmpty { stamped["requirement_assessments"] = assessments }
        let mergedJSON = FitScorer.buildMergedJSON(result: score, rawLLMDict: stamped)
        return FitScoreOutput(
            score: score, fitScoreJSON: mergedJSON, promptChars: promptChars,
            responseChars: responseChars,
            promptTokens: response.promptTokens, completionTokens: response.completionTokens,
            modelReturned: response.model,
            responseFormat: response.responseFormat
        )
    }

    // MARK: - Private helpers

    /// LLM output is untrusted: only persist an extracted application URL if it's an absolute
    /// http/https URL (reusing the shared ingestion policy). Schemeless, `javascript:`, or malformed
    /// values become nil so they can't shadow the safe capture/canonical URL in apply/availability
    /// precedence (TASK-564). Returns the normalized URL for valid input.
    static func validatedApplicationURL(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? URLNormalizer.validatedForIngestion(raw)
    }

    private static func captureText(_ snapshot: JobExtractionSnapshot) -> String {
        snapshot.captureCleanedDescription ?? snapshot.captureVisibleText ?? snapshot.captureSelectedText ?? ""
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Read the extraction confidence. The contract is a single 0–1 number (TASK-562), but we stay
    /// lenient: a legacy per-field object (older/non-strict providers) is averaged for back-compat,
    /// and anything else is treated as absent — confidence is a soft UI hint and must never fail
    /// extraction.
    static func computeConfidence(_ raw: Any??) -> Double? {
        guard let outer = raw, let inner = outer else { return nil }
        if let dbl = inner as? Double { return dbl }
        if let int = inner as? Int { return Double(int) }
        if let dict = inner as? [String: Any] {
            let values = dict.values.compactMap { val -> Double? in
                if let dbl = val as? Double { return dbl }
                if let int = val as? Int { return Double(int) }
                return nil
            }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        return nil
    }

    /// Internal rather than private so a test can pin the JSON keys it reads. An eval fixture
    /// written with `nice_to_have` instead of `nice_to_haves` silently dropped the preferred list,
    /// and the resulting miss was recorded as a model regression.
    static func buildJobContext(from job: JobFitSnapshot) -> ExtractedJobContext {
        var title = job.title
        var company = job.company
        var seniority = job.seniority
        var summary: String?
        var requirements: [String] = []
        var niceToHaves: [String] = []
        var skills: [String] = []
        var applicationInstructions: String?

        if let jsonStr = job.extractedJSON,
           let data = jsonStr.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = title ?? raw["title"] as? String
            company = company ?? raw["company"] as? String
            seniority = seniority ?? raw["seniority"] as? String
            summary = raw["summary"] as? String
            requirements = (raw["requirements"] as? [Any])?.compactMap { $0 as? String } ?? []
            niceToHaves = (raw["nice_to_haves"] as? [Any])?.compactMap { $0 as? String } ?? []
            skills = (raw["skills"] as? [Any])?.compactMap { $0 as? String } ?? []
            applicationInstructions = raw["application_instructions"] as? String
        }

        return ExtractedJobContext(
            title: title,
            company: company,
            seniority: seniority,
            summary: summary,
            requirements: requirements,
            niceToHaves: niceToHaves,
            skills: skills,
            applicationInstructions: applicationInstructions
        )
    }

    // Dimension parsing moved to FitScorer.validateDimensions (TASK-453) so the exact dimension
    // contract is validated (missing/unknown/duplicate/non-numeric → error) before scoring.
}

// MARK: - ExtractionEngineError

public enum ExtractionEngineError: Error, LocalizedError {
    /// Whether a response's braces/brackets never close — the signature of a truncated answer.
    /// Quote-aware so punctuation inside strings can't skew the count.
    static func isUnbalanced(_ text: String) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for ch in text {
            if escaped { escaped = false; continue }
            if ch == "\\", inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            if ch == "{" || ch == "[" { depth += 1 }
            if ch == "}" || ch == "]" { depth -= 1 }
        }
        return depth != 0 || inString
    }

    case noCaptureText
    case emptyResumeText
    case invalidJSON(String)
    case noModelSelected
    /// A field in the provider response had an incompatible shape for the extraction schema (TASK-456).
    case malformedField(field: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noCaptureText:
            "Job has no capture text to extract from"
        case .emptyResumeText:
            "Resume has no text to score against"
        case let .invalidJSON(raw):
            // Classify WHY without ever echoing the model's text: an unbalanced response means it was
            // cut off (the actionable case), which the bare message hid. The verbatim response is
            // still persisted to the attempt's responsePreview for debugging.
            ExtractionEngineError.isUnbalanced(raw)
                ? "LLM response was incomplete — it ended mid-JSON, so the model was likely cut off"
                // Carry the parser's own account of WHERE and WHY. Job #861 failed three times with
                // the bare message against a response that was neither truncated nor malformed at
                // either end — the fault was somewhere in the middle, and nothing recorded said
                // where. JSONSerialization already knows ("Unescaped control character around line
                // 12, column 5"); it was simply being discarded.
                : jsonParseFailureMessage(raw)
        case .noModelSelected:
            "No model selected — choose a model in Settings → AI"
        case let .malformedField(field, reason):
            "LLM response field '\(field)' was invalid: \(reason)"
        }
    }
}

// swiftlint:enable function_body_length
